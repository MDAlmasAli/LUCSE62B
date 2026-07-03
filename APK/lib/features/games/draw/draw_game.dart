import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supa.dart';
import '../game_identity.dart';
import 'draw_canvas.dart';
import 'draw_models.dart';

/// Host-chosen room settings.
class DrawSettings {
  int roundsTotal = 3;
  int drawTime = 80;
  int maxPlayers = 8;
  bool guestsAllowed = true;
}

/// Drives one Draw & Guess session over the shared Supabase backend
/// (`draw_rooms` / `draw_players` / `draw_chat`, the `draw:CODE` realtime
/// channel with broadcast strokes/fills/clear/snapshot, and `bump_standing`),
/// so app players share rooms and standings with the website.
class DrawGame extends ChangeNotifier {
  DrawGame(this.identity);
  final GameIdentity identity;

  final DrawCanvas canvas = DrawCanvas();

  SupabaseClient get _sb => Supa.client;
  String get _pid => identity.playerId;
  String get _pname => identity.playerName;

  DrawRoom? room;
  List<DrawPlayer> players = [];
  DrawPlayer? me;
  bool isHost = false;
  bool isDrawer = false;
  String? roomCode;
  Set<String> online = {};
  final List<DrawChat> chat = [];

  // Tools (drawer only)
  Color currentColor = const Color(0xFF000000);
  double currentSize = 5;
  String currentTool = 'pencil'; // pencil | eraser | fill

  RealtimeChannel? _channel;
  final Map<String, Timer> _discTimers = {};
  Timer? _ticker;
  bool _disposed = false;

  // Host-only round bookkeeping
  Map<String, int> _roundStart = {};
  Map<String, int> _prevScores = {};
  bool _hint1 = false, _hint2 = false;

  // ── Queries ──
  Future<DrawRoom?> _getRoom(String code) async {
    final d = await _sb.from('draw_rooms').select().eq('room_code', code).maybeSingle();
    return d == null ? null : DrawRoom.fromMap(d);
  }

  Future<List<DrawPlayer>> _getPlayers(String code, {String orderBy = 'joined_at', bool asc = true}) async {
    final rows = await _sb.from('draw_players').select().eq('room_code', code).order(orderBy, ascending: asc);
    return (rows as List).map((r) => DrawPlayer.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<void> _updateRoom(Map<String, dynamic> patch) async {
    if (roomCode == null) return;
    await _sb.from('draw_rooms').update(patch).eq('room_code', roomCode!);
  }

  Future<void> _refreshPlayers() async {
    if (roomCode == null) return;
    players = await _getPlayers(roomCode!);
    final mine = players.where((p) => p.playerId == _pid).toList();
    me = mine.isEmpty ? null : mine.first;
  }

  List<DrawPlayer> get activePlayers => players.where((p) => p.active).toList();

  /// Words drawn anywhere (app or web) in the last 30 days — excluded from the
  /// next picks so a word that came up won't repeat for a month.
  Future<List<String>> _recentWords() async {
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();
      final rows = await _sb.from('draw_recent_words').select('word').gte('used_at', since);
      return (rows as List).map((r) => '${(r as Map)['word']}').toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _recordWord(String word) async {
    try {
      await _sb.from('draw_recent_words').upsert(
        {'word': word, 'used_at': DateTime.now().toUtc().toIso8601String()},
        onConflict: 'word',
      );
    } catch (_) {}
  }

  // ── Create / Join ──
  static String _genCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<String?> createRoom(DrawSettings s) async {
    if (_pname.trim().isEmpty) return 'Please enter your name first.';
    final code = _genCode();
    try {
      await _sb.from('draw_rooms').insert({
        'room_code': code,
        'host_id': _pid,
        'rounds_total': s.roundsTotal,
        'draw_time': s.drawTime,
        'max_players': s.maxPlayers,
        'is_private': false,
        'guests_allowed': s.guestsAllowed,
      });
      await _sb.from('draw_players').insert({
        'room_code': code,
        'player_id': _pid,
        'player_name': _pname,
      });
      roomCode = code;
      room = await _getRoom(code);
      isHost = true;
      await _refreshPlayers();
      _subscribe(code);
      notifyListeners();
      return null;
    } catch (e) {
      return 'Could not create room.';
    }
  }

  Future<String?> joinRoom(String rawCode) async {
    if (_pname.trim().isEmpty) return 'Please enter your name first.';
    final code = rawCode.trim().toUpperCase();
    if (code.length != 6) return 'Enter a 6-character room code.';
    final r = await _getRoom(code);
    if (r == null) return 'Room not found.';
    if (identity.isGuest && !r.guestsAllowed) return 'This room requires login.';

    if (r.status != 'lobby') {
      if (identity.isGuest) return 'This game has already started.';
      final existing = await _getPlayers(code);
      final was = existing.where((p) => p.playerId == _pid).toList();
      if (was.isEmpty) {
        await _sb.from('draw_players').insert({'room_code': code, 'player_id': _pid, 'player_name': _pname});
      } else {
        await _sb.from('draw_players').update({'left_at': null}).eq('room_code', code).eq('player_id', _pid);
      }
      await _enter(code, r);
      return null;
    }

    final existing = await _getPlayers(code);
    if (existing.length >= r.maxPlayers) return 'Room is full.';
    if (!existing.any((p) => p.playerId == _pid)) {
      await _sb.from('draw_players').insert({'room_code': code, 'player_id': _pid, 'player_name': _pname});
    }
    await _enter(code, r);
    return null;
  }

  Future<void> _enter(String code, DrawRoom r) async {
    roomCode = code;
    room = r;
    isHost = _pid == r.hostId;
    isDrawer = r.currentDrawer == _pid;
    await _refreshPlayers();
    _prevScores = {for (final p in players) p.playerId: p.score};
    await canvas.ensureReady();
    _subscribe(code);
    notifyListeners();
  }

  // ── Realtime ──
  void _subscribe(String code) {
    if (_channel != null) {
      _sb.removeChannel(_channel!);
      _channel = null;
    }
    online = {};
    final ch = _sb.channel('draw:$code');
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'draw_rooms',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_code', value: code),
          callback: (payload) => _onRoomChange(payload, code),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'draw_players',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_code', value: code),
          callback: (_) => _onPlayersChange(code),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'draw_chat',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_code', value: code),
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              chat.add(DrawChat.fromMap(payload.newRecord));
              notifyListeners();
            }
          },
        )
        .onBroadcast(event: 'stroke', callback: (p) => _onStroke(_bp(p)))
        .onBroadcast(event: 'fill', callback: (p) => _onFill(_bp(p)))
        .onBroadcast(event: 'clear', callback: (_) {
          if (!isDrawer) canvas.clearLocal();
        })
        .onBroadcast(event: 'snapshot', callback: (p) {
          final d = _bp(p);
          final img = d['img'];
          if (!isDrawer && img is String) canvas.applySnapshot(img);
        })
        .onPresenceSync((_) => _refreshPresence())
        .onPresenceLeave((payload) {
          for (final pres in payload.leftPresences) {
            final pid = pres.payload['player_id'];
            if (pid is String) _scheduleDisconnect(pid);
          }
        })
        .subscribe((status, error) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await ch.track({'player_id': _pid, 'player_name': _pname});
            if (roomCode != null) {
              await _sb.from('draw_players').update({'left_at': null}).eq('room_code', roomCode!).eq('player_id', _pid);
            }
          }
        });
    _channel = ch;
    _startTicker();
  }

  Map<String, dynamic> _bp(Map<String, dynamic> p) {
    final inner = p['payload'];
    return inner is Map ? inner.cast<String, dynamic>() : p;
  }

  void _onStroke(Map<String, dynamic> p) {
    if (isDrawer) return;
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final tool = '${p['tool']}';
    final color = tool == 'eraser' ? const Color(0xFFFFFFFF) : _parseColor('${p['color']}');
    canvas.addSegment(d(p['x0']) * kCanvasW, d(p['y0']) * kCanvasH, d(p['x1']) * kCanvasW, d(p['y1']) * kCanvasH,
        color, d(p['size']));
  }

  void _onFill(Map<String, dynamic> p) {
    if (isDrawer) return;
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    canvas.fill((d(p['x']) * kCanvasW).round(), (d(p['y']) * kCanvasH).round(), _parseColor('${p['color']}'));
  }

  static Color _parseColor(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFF000000);
  }

  static String _colorHex(Color c) {
    String two(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
    return '#${two(c.r)}${two(c.g)}${two(c.b)}';
  }

  Future<void> _onRoomChange(PostgresChangePayload payload, String code) async {
    final prevStatus = room?.status;
    final rec = payload.newRecord;
    room = rec.isNotEmpty ? DrawRoom.fromMap(rec) : await _getRoom(code);
    final r = room;
    if (r == null) return;
    isHost = _pid == r.hostId;
    isDrawer = r.currentDrawer == _pid;

    if (r.status != prevStatus) {
      if (r.status == 'drawing') {
        _hint1 = false;
        _hint2 = false;
        _prevScores = {for (final p in players) p.playerId: p.score};
        if (isHost) _roundStart = {for (final p in players) p.playerId: p.score};
        await canvas.clearLocal();
      } else if (r.status == 'round_end') {
        await _loadRoundEnd();
      } else if (r.status == 'game_over') {
        await _loadGameOver();
      }
    }
    notifyListeners();

    // After a host handoff, the new host advances if the drawer has left.
    if (isHost && (r.status == 'drawing' || r.status == 'word_pick')) {
      final drawerActive = players.any((p) => p.playerId == r.currentDrawer && p.active);
      if (!drawerActive) await nextTurn();
    }
  }

  Future<void> _onPlayersChange(String code) async {
    await _refreshPlayers();
    if (me?.leftAt != null) {
      await _sb.from('draw_players').update({'left_at': null}).eq('room_code', code).eq('player_id', _pid);
      return;
    }
    notifyListeners();
    final st = room?.status;
    if (isHost && (st == 'word_pick' || st == 'drawing' || st == 'round_end') && activePlayers.length < 2) {
      await _updateRoom({'status': 'game_over'});
      return;
    }
    if (isHost && (st == 'drawing' || st == 'word_pick')) {
      final drawerActive = players.any((p) => p.playerId == room?.currentDrawer && p.active);
      if (!drawerActive) {
        await nextTurn();
        return;
      }
    }
    if (isHost && st == 'drawing') await _checkAllGuessed();
  }

  void _refreshPresence() {
    if (_channel == null) return;
    final ids = <String>{};
    for (final st in _channel!.presenceState()) {
      for (final pres in st.presences) {
        final pid = pres.payload['player_id'];
        if (pid is String) ids.add(pid);
      }
    }
    final newcomers = ids.difference(online);
    online = ids;
    for (final pid in ids) {
      _discTimers.remove(pid)?.cancel();
    }
    // I'm the drawer and someone just connected mid-round → resend the canvas
    // so late joiners (app or web) see what's been drawn so far.
    if (isDrawer && room?.status == 'drawing' && newcomers.any((id) => id != _pid)) {
      _resendSnapshot();
    }
    notifyListeners();
  }

  Future<void> _resendSnapshot() async {
    final url = await canvas.snapshotDataUrl();
    if (url != null) {
      await _channel?.sendBroadcastMessage(event: 'snapshot', payload: {'img': url});
    }
  }

  void _scheduleDisconnect(String pid) {
    _discTimers[pid]?.cancel();
    _discTimers[pid] = Timer(const Duration(seconds: 7), () async {
      _discTimers.remove(pid);
      if (online.contains(pid)) return;
      if (!isHost || roomCode == null) return;
      if (room?.status == 'lobby') {
        await _sb.from('draw_players').delete().eq('room_code', roomCode!).eq('player_id', pid);
      } else {
        await _sb
            .from('draw_players')
            .update({'left_at': DateTime.now().toUtc().toIso8601String()})
            .eq('room_code', roomCode!)
            .eq('player_id', pid)
            .isFilter('left_at', null);
      }
    });
  }

  // ── Host phase timer ──
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_disposed) return;
      notifyListeners(); // countdown UI
      final r = room;
      if (!isHost || r == null || r.status != 'drawing' || r.phaseEndsAt == null) return;
      final total = r.drawTime;
      final left = max(0, r.phaseEndsAt!.toUtc().difference(DateTime.now().toUtc()).inSeconds);
      final elapsed = total - left;
      if (elapsed >= total * 0.4 && !_hint1 && r.currentWord != null && r.currentHint != null) {
        _hint1 = true;
        await _revealHintLetter();
      }
      if (elapsed >= total * 0.7 && !_hint2 && r.currentWord != null && r.currentHint != null) {
        _hint2 = true;
        await _revealHintLetter();
      }
      if (left <= 0) await _endRound();
    });
  }

  int get secondsLeft {
    final end = room?.phaseEndsAt;
    if (end == null) return -1;
    return max(0, end.toUtc().difference(DateTime.now().toUtc()).inSeconds);
  }

  Future<void> _revealHintLetter() async {
    final r = room;
    final word = r?.currentWord;
    final hint = r?.currentHint;
    if (word == null || hint == null) return;
    final hidden = <int>[];
    for (var i = 0; i < word.length && i < hint.length; i++) {
      if (hint[i] == '_' && RegExp(r'[a-zA-Z]').hasMatch(word[i])) hidden.add(i);
    }
    if (hidden.isEmpty) return;
    final idx = hidden[Random().nextInt(hidden.length)];
    final newHint = hint.substring(0, idx) + word[idx] + hint.substring(idx + 1);
    await _updateRoom({'current_hint': newHint});
  }

  // ── Settings (host) ──
  Future<void> updateSettings(Map<String, dynamic> patch) async {
    if (!isHost) return;
    await _updateRoom(patch);
  }

  // ── Start / turns ──
  Future<String?> startGame() async {
    if (!isHost || room == null) return null;
    final active = activePlayers;
    if (active.length < 2) return 'Need at least 2 players.';
    final order = [...active.map((p) => p.playerId)]..shuffle();
    final choices = WordBag.pick(3, await _recentWords());
    await _sb.from('draw_players').update({'score': 0, 'has_guessed': false}).eq('room_code', roomCode!);
    await _updateRoom({
      'status': 'word_pick',
      'draw_order': order,
      'draw_index': 0,
      'round_current': 1,
      'current_drawer': order.first,
      'word_choices': choices,
      'current_word': null,
      'current_hint': null,
      'used_words': <String>[],
      'phase_ends_at': null,
    });
    return null;
  }

  Future<void> pickWord(String word) async {
    if (!isDrawer || room == null) return;
    final used = [...room!.usedWords, word];
    final end = DateTime.now().toUtc().add(Duration(seconds: room!.drawTime)).toIso8601String();
    await _updateRoom({
      'status': 'drawing',
      'current_word': word,
      'current_hint': wordToHint(word),
      'used_words': used,
      'phase_ends_at': end,
    });
    await _sb.from('draw_players').update({'has_guessed': false}).eq('room_code', roomCode!);
    await _recordWord(word); // mark used for the global 30-day de-dup
    await canvas.clearLocal();
    await _channel?.sendBroadcastMessage(event: 'clear', payload: {});
  }

  Future<void> _checkAllGuessed() async {
    final r = room;
    if (r?.status != 'drawing') return;
    final nonDrawers = players.where((p) => p.playerId != r!.currentDrawer && p.active).toList();
    if (nonDrawers.isNotEmpty && nonDrawers.every((p) => p.hasGuessed)) await _endRound();
  }

  Future<void> _endRound() async {
    final r = room;
    if (!isHost || r?.status != 'drawing') return;
    // Skribbl-style: drawer earns the average of what the guessers scored.
    final drawerId = r!.currentDrawer;
    final gains = players
        .where((p) => p.playerId != drawerId && p.active && p.hasGuessed)
        .map((p) => max(0, p.score - (_roundStart[p.playerId] ?? 0)))
        .toList();
    if (gains.isNotEmpty) {
      final avg = (gains.reduce((a, b) => a + b) / gains.length).round();
      final drawer = players.where((p) => p.playerId == drawerId).toList();
      if (drawer.isNotEmpty && avg > 0) {
        await _sb
            .from('draw_players')
            .update({'score': drawer.first.score + avg})
            .eq('room_code', roomCode!)
            .eq('player_id', drawerId!);
      }
    }
    await _updateRoom({'status': 'round_end'});
  }

  Future<void> nextTurn() async {
    final r = room;
    if (!isHost || r == null) return;
    final order = r.drawOrder;
    final activeIds = activePlayers.map((p) => p.playerId).toSet();
    await _sb.from('draw_players').update({'has_guessed': false}).eq('room_code', roomCode!);
    final exclude = {...r.usedWords, ...await _recentWords()};

    var nextIndex = r.drawIndex + 1;
    while (nextIndex < order.length && !activeIds.contains(order[nextIndex])) {
      nextIndex++;
    }

    if (nextIndex >= order.length) {
      if (r.roundCurrent >= r.roundsTotal) {
        await _updateRoom({'status': 'game_over'});
      } else {
        final newOrder = [...activeIds]..shuffle();
        if (newOrder.isEmpty) {
          await _updateRoom({'status': 'game_over'});
          return;
        }
        final choices = WordBag.pick(3, exclude);
        await _updateRoom({
          'status': 'word_pick',
          'round_current': r.roundCurrent + 1,
          'draw_order': newOrder,
          'draw_index': 0,
          'current_drawer': newOrder.first,
          'word_choices': choices,
          'current_word': null,
          'current_hint': null,
          'phase_ends_at': null,
        });
      }
    } else {
      final choices = WordBag.pick(3, exclude);
      await _updateRoom({
        'status': 'word_pick',
        'draw_index': nextIndex,
        'current_drawer': order[nextIndex],
        'word_choices': choices,
        'current_word': null,
        'current_hint': null,
        'phase_ends_at': null,
      });
    }
  }

  Future<void> endGame() async {
    if (!isHost) return;
    await _updateRoom({'status': 'game_over'});
  }

  // ── Round-end / game-over data ──
  List<DrawPlayer> roundEndPlayers = [];
  List<DrawPlayer> gameOverPlayers = [];

  int gainFor(DrawPlayer p) => p.score - (_prevScores[p.playerId] ?? 0);

  Future<void> _loadRoundEnd() async {
    roundEndPlayers = await _getPlayers(roomCode!, orderBy: 'score', asc: false);
    notifyListeners();
    _prevScores = {for (final p in roundEndPlayers) p.playerId: p.score};
  }

  Future<void> _loadGameOver() async {
    gameOverPlayers = await _getPlayers(roomCode!, orderBy: 'score', asc: false);
    notifyListeners();
    await _recordStandings();
  }

  Future<void> _recordStandings() async {
    final r = room;
    if (!isHost || r == null || r.standingsDone) return;
    await _updateRoom({'standings_done': true});
    final finishers = gameOverPlayers.where((p) => p.active).toList();
    if (finishers.length < 2) return;
    final top = gameOverPlayers.fold<int>(0, (a, p) => max(a, p.score));
    for (final p in gameOverPlayers) {
      if (!p.playerId.startsWith('student_')) continue;
      final won = top > 0 && p.score == top && p.active;
      try {
        await _sb.rpc('bump_standing', params: {
          'p_id': p.playerId,
          'p_name': p.playerName,
          'p_points': p.score,
          'p_won': won,
          'p_bucket': 'draw',
        });
      } catch (_) {}
    }
  }

  Future<void> backToLobby() async {
    if (!isHost || roomCode == null) return;
    await _sb.from('draw_players').update({'score': 0, 'has_guessed': false}).eq('room_code', roomCode!);
    await _sb.from('draw_players').delete().eq('room_code', roomCode!).not('left_at', 'is', null);
    await _updateRoom({
      'status': 'lobby',
      'current_drawer': null,
      'current_word': null,
      'current_hint': null,
      'word_choices': <String>[],
      'draw_order': <String>[],
      'draw_index': 0,
      'round_current': 0,
      'phase_ends_at': null,
      'used_words': <String>[],
      'standings_done': false,
    });
    chat.clear();
  }

  // ── Guessing ──
  Future<void> sendGuess(String raw) async {
    final text = raw.trim();
    final r = room;
    if (text.isEmpty || isDrawer || r?.status != 'drawing') return;
    if (me?.hasGuessed == true) return;
    final word = r!.currentWord;
    if (word == null) return;
    final correct = text.toLowerCase() == word.toLowerCase();
    final close = !correct && levenshtein(text.toLowerCase(), word.toLowerCase()) == 1;

    if (correct) {
      final total = r.drawTime;
      final left = r.phaseEndsAt == null
          ? 0
          : max(0, r.phaseEndsAt!.toUtc().difference(DateTime.now().toUtc()).inSeconds);
      final pts = (100 * (left / total)).floor() + 50;
      await _sb
          .from('draw_players')
          .update({'has_guessed': true, 'score': (me?.score ?? 0) + pts})
          .eq('room_code', roomCode!)
          .eq('player_id', _pid);
      await _sb.from('draw_chat').insert({
        'room_code': roomCode,
        'player_id': _pid,
        'player_name': _pname,
        'message': 'guessed the word!',
        'is_correct': true,
      });
    } else {
      await _sb.from('draw_chat').insert({
        'room_code': roomCode,
        'player_id': _pid,
        'player_name': _pname,
        'message': close ? '$text (close!)' : text,
        'is_correct': false,
      });
    }
  }

  // ── Drawing actions (drawer) ──
  Future<void> strokeStart() => canvas.pushHistory();

  void drawSegment(double x0, double y0, double x1, double y1) {
    final color = currentTool == 'eraser' ? const Color(0xFFFFFFFF) : currentColor;
    canvas.addSegment(x0, y0, x1, y1, color, currentSize);
    _channel?.sendBroadcastMessage(event: 'stroke', payload: {
      'x0': x0 / kCanvasW,
      'y0': y0 / kCanvasH,
      'x1': x1 / kCanvasW,
      'y1': y1 / kCanvasH,
      'color': currentTool == 'eraser' ? '#ffffff' : _colorHex(currentColor),
      'size': currentSize,
      'tool': currentTool,
    });
  }

  Future<void> doFill(double x, double y) async {
    await canvas.fill(x.round(), y.round(), currentColor);
    await _channel?.sendBroadcastMessage(event: 'fill', payload: {
      'x': x / kCanvasW,
      'y': y / kCanvasH,
      'color': _colorHex(currentColor),
    });
  }

  Future<void> clearCanvas() async {
    if (!isDrawer) return;
    await canvas.clearWithHistory();
    await _channel?.sendBroadcastMessage(event: 'clear', payload: {});
    notifyListeners();
  }

  Future<void> undo() async {
    if (!isDrawer) return;
    final url = await canvas.undo();
    if (url != null) await _channel?.sendBroadcastMessage(event: 'snapshot', payload: {'img': url});
    notifyListeners();
  }

  // ── Leave ──
  Future<void> leaveRoom() async {
    if (roomCode == null) return;
    final code = roomCode!;
    final activeGame = room?.status != null && room?.status != 'lobby';
    final wasHost = isHost;
    if (_channel != null) {
      _sb.removeChannel(_channel!);
      _channel = null;
    }
    _ticker?.cancel();
    if (activeGame) {
      await _sb.from('draw_players').update({'left_at': DateTime.now().toUtc().toIso8601String()}).eq('room_code', code).eq('player_id', _pid);
    } else {
      await _sb.from('draw_players').delete().eq('room_code', code).eq('player_id', _pid);
    }
    final remaining = await _getPlayers(code);
    final stillActive = remaining.where((p) => p.active && p.playerId != _pid).toList();
    if (stillActive.isEmpty) {
      await _sb.from('draw_rooms').delete().eq('room_code', code);
    } else if (wasHost) {
      await _sb.from('draw_rooms').update({'host_id': stillActive.first.playerId}).eq('room_code', code);
    }
    roomCode = null;
    room = null;
    players = [];
    me = null;
    chat.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    for (final t in _discTimers.values) {
      t.cancel();
    }
    if (_channel != null) _sb.removeChannel(_channel!);
    canvas.dispose();
    super.dispose();
  }
}
