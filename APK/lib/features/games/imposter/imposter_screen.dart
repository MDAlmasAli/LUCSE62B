import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_colors.dart';
import '../../../shared/app_toast.dart';
import '../game_identity.dart';
import 'imposter_game.dart';
import 'imposter_models.dart';

/// Native Imposter game — full state machine (lobby → role reveal → discussion
/// → voting → results) over the shared Supabase backend, so app players join the
/// same rooms and standings as the website.
class ImposterScreen extends StatefulWidget {
  const ImposterScreen({super.key});

  @override
  State<ImposterScreen> createState() => _ImposterScreenState();
}

class _ImposterScreenState extends State<ImposterScreen> {
  ImposterGame? _g;
  GameIdentity? _id;
  final _nameCtrl = TextEditingController();
  final _joinCtrl = TextEditingController();
  final _settings = ImposterSettings();
  bool _busy = false;
  bool _standingsRecorded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final id = await GameIdentity.resolve();
    if (!mounted) return;
    _nameCtrl.text = id.playerName;
    setState(() {
      _id = id;
      _g = ImposterGame(id);
    });
  }

  @override
  void dispose() {
    _g?.dispose();
    _nameCtrl.dispose();
    _joinCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshIdentityName() async {
    // Persist a guest's typed name so a fresh controller is bound to it.
    final id = await GameIdentity.resolve(guestName: _nameCtrl.text.trim());
    final old = _g;
    final fresh = ImposterGame(id);
    setState(() {
      _id = id;
      _g = fresh;
    });
    old?.dispose();
  }

  Future<void> _leaveToHub() async {
    final g = _g;
    if (g != null && g.roomCode != null) await g.leaveRoom();
    if (mounted) context.canPop() ? context.pop() : context.go('/games');
  }

  @override
  Widget build(BuildContext context) {
    final g = _g;
    if (g == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (g.roomCode != null) {
          final yes = await _confirm('Leave the room?');
          if (yes) await _leaveToHub();
        } else {
          if (mounted) context.canPop() ? context.pop() : context.go('/games');
        }
      },
      child: AnimatedBuilder(
        animation: g,
        builder: (context, _) {
          final inRoom = g.roomCode != null && g.room != null;
          return Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(
              title: const Text('Imposter'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  if (g.roomCode != null) {
                    if (await _confirm('Leave the room?')) await _leaveToHub();
                  } else {
                    if (mounted) context.canPop() ? context.pop() : context.go('/games');
                  }
                },
              ),
            ),
            body: inRoom ? _roomBody(g) : _homeBody(g),
          );
        },
      ),
    );
  }

  // ── Home (create / join) ──
  Widget _homeBody(ImposterGame g) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        _hero('🕵️', 'Imposter', 'One player doesn\'t know the secret word. Blend in, find the imposter.'),
        const SizedBox(height: 18),
        if (_id?.isGuest ?? false) ...[
          _label('YOUR NAME'),
          TextField(
            controller: _nameCtrl,
            onChanged: (_) {},
            decoration: const InputDecoration(hintText: 'Enter a name to play'),
          ),
          const SizedBox(height: 16),
        ],
        _card(
          title: 'Create a room',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _settingsEditor(setStateLocal: () => setState(() {})),
              const SizedBox(height: 12),
              _primaryBtn('Create Room', Icons.add_rounded, _busy ? null : () => _create(g)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _card(
          title: 'Join a room',
          child: Column(
            children: [
              TextField(
                controller: _joinCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                decoration: const InputDecoration(hintText: '6-character code', counterText: ''),
              ),
              const SizedBox(height: 8),
              _primaryBtn('Join Room', Icons.login_rounded, _busy ? null : () => _join(g)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _syncGuestName() async {
    if ((_id?.isGuest ?? false) && _nameCtrl.text.trim().isNotEmpty) {
      await _refreshIdentityName();
    }
  }

  Future<void> _create(ImposterGame g) async {
    await _syncGuestName();
    final game = _g!;
    setState(() => _busy = true);
    final err = await game.createRoom(_settings);
    if (mounted) setState(() => _busy = false);
    if (err != null && mounted) AppToast.show(context, err, error: true);
  }

  Future<void> _join(ImposterGame g) async {
    await _syncGuestName();
    final game = _g!;
    setState(() => _busy = true);
    final err = await game.joinRoom(_joinCtrl.text);
    if (mounted) setState(() => _busy = false);
    if (err != null && mounted) AppToast.show(context, err, error: true);
  }

  // ── Room dispatcher ──
  Widget _roomBody(ImposterGame g) {
    switch (g.room!.status) {
      case 'role_reveal':
        return _roleReveal(g);
      case 'discuss':
        return _discuss(g);
      case 'vote':
        return _vote(g);
      case 'result':
        return _result(g);
      default:
        return _lobby(g);
    }
  }

  // ── Lobby ──
  Widget _lobby(ImposterGame g) {
    final approved = g.players.where((p) => p.active).toList();
    final pending = g.players.where((p) => !p.isApproved && p.leftAt == null).toList();
    final me = g.me;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppColors.accent.withValues(alpha: 0.16), AppColors.accentCyan.withValues(alpha: 0.08)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderAccent),
          ),
          child: Column(
            children: [
              Text('ROOM CODE', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: g.roomCode ?? ''));
                  AppToast.show(context, 'Code copied');
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(g.roomCode ?? '',
                        style: TextStyle(color: AppColors.textBright, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 6)),
                    const SizedBox(width: 8),
                    Icon(Icons.copy_rounded, size: 18, color: AppColors.accentBright),
                  ],
                ),
              ),
              Text('${approved.length}/${g.room!.maxPlayers} players',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (pending.isNotEmpty && g.isHost) ...[
          _label('PENDING APPROVAL'),
          ...pending.map((p) => _pendingRow(g, p)),
          const SizedBox(height: 12),
        ],
        _label('PLAYERS'),
        ...approved.map((p) => _playerRow(g, p)),
        const SizedBox(height: 16),
        if (g.isHost) ...[
          _card(title: 'Settings', child: _settingsEditor(setStateLocal: () {}, live: g)),
          const SizedBox(height: 14),
          _primaryBtn('Start Game', Icons.play_arrow_rounded, approved.length < 2 ? null : () => _startGame(g)),
        ] else
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Text('Waiting for the host to start…', style: TextStyle(color: AppColors.muted))),
          ),
        if (me != null && !me.isApproved)
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: Center(child: Text('Waiting for host approval…', style: TextStyle(color: AppColors.amberBright))),
          ),
        const SizedBox(height: 10),
        _secondaryBtn('Leave Room', Icons.logout_rounded, _leaveToHub),
      ],
    );
  }

  Future<void> _startGame(ImposterGame g) async {
    final err = await g.startGame();
    if (err != null && mounted) AppToast.show(context, err, error: true);
  }

  Widget _pendingRow(ImposterGame g, ImposterPlayer p) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.amberBright.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppColors.amberBright.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          _avatar(p.playerName, 34),
          const SizedBox(width: 10),
          Expanded(child: Text(p.playerName, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600))),
          IconButton(icon: Icon(Icons.check_circle, color: AppColors.greenBright), onPressed: () => g.approve(p.playerId)),
          IconButton(icon: Icon(Icons.cancel, color: AppColors.red), onPressed: () => g.reject(p.playerId)),
        ]),
      );

  Widget _playerRow(ImposterGame g, ImposterPlayer p) {
    final isMe = p.playerId == g.identity.playerId;
    final isOnline = g.online.contains(p.playerId);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? AppColors.accent.withValues(alpha: 0.08) : AppColors.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: isMe ? AppColors.borderAccent : AppColors.border),
      ),
      child: Row(children: [
        _avatar(p.playerName, 36),
        const SizedBox(width: 11),
        Expanded(
          child: Text('${p.playerName}${isMe ? ' (You)' : ''}',
              style: TextStyle(color: AppColors.textBright, fontWeight: FontWeight.w600)),
        ),
        if (p.isHost)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6)),
            child: Text('HOST', style: TextStyle(color: AppColors.accentBright, fontSize: 9.5, fontWeight: FontWeight.w800)),
          ),
        Icon(Icons.circle, size: 9, color: isOnline ? AppColors.greenBright : AppColors.muted),
      ]),
    );
  }

  // ── Role reveal ──
  Widget _roleReveal(ImposterGame g) {
    final imp = g.me?.isImposter ?? false;
    final approved = g.players.where((p) => p.active).toList();
    final ready = approved.where((p) => p.isReady).length;
    final color = imp ? AppColors.red : AppColors.greenBright;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
          ),
          child: Column(children: [
            Text(imp ? '🕵️' : '👥', style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 10),
            Text(imp ? 'IMPOSTER' : 'CREWMATE',
                style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 14),
            if (!imp) ...[
              Text('THE WORD', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(g.room!.word ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textBright, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text('Give clues — but don\'t say it directly. Find the imposter!',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ] else
              Text("You don't know the word. Blend in — don't get caught!",
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
          ]),
        ),
        const SizedBox(height: 18),
        Center(child: Text('$ready/${approved.length} players ready', style: TextStyle(color: AppColors.textSecondary))),
        const SizedBox(height: 14),
        if (!(g.me?.isReady ?? false))
          _primaryBtn('I\'m Ready', Icons.check_rounded, () => g.markReady()),
        if (g.isHost && ready == approved.length && approved.isNotEmpty) ...[
          const SizedBox(height: 10),
          _primaryBtn('Start Discussion', Icons.forum_rounded, () => g.startDiscussion()),
        ],
        if (g.isHost) ...[
          const SizedBox(height: 10),
          _secondaryBtn('End Match', Icons.flag_rounded, () => g.endGame()),
        ],
      ],
    );
  }

  // ── Discussion ──
  Widget _discuss(ImposterGame g) {
    final imp = g.me?.isImposter ?? false;
    final approved = g.players.where((p) => p.active).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _timerChip(g),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Text('THE WORD', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(imp ? '??? — You are the imposter!' : (g.room!.word ?? ''),
                textAlign: TextAlign.center,
                style: TextStyle(color: imp ? AppColors.red : AppColors.textBright, fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(height: 16),
        _label('PLAYERS — DISCUSS & GIVE CLUES'),
        Wrap(spacing: 10, runSpacing: 10, children: approved.map((p) => _playerChip(g, p)).toList()),
        const SizedBox(height: 20),
        if (g.isHost) _primaryBtn(g.room!.skipVote ? 'End Discussion' : 'Go to Voting', Icons.how_to_vote_rounded, () => g.advanceFromDiscuss()),
        if (g.isHost) ...[
          const SizedBox(height: 10),
          _secondaryBtn('End Match', Icons.flag_rounded, () => g.endGame()),
        ],
      ],
    );
  }

  // ── Voting ──
  Widget _vote(ImposterGame g) {
    final others = g.players.where((p) => p.active && p.playerId != g.identity.playerId).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _timerChip(g),
        const SizedBox(height: 8),
        Center(child: Text('Who is the imposter?', style: TextStyle(color: AppColors.textBright, fontSize: 17, fontWeight: FontWeight.w800))),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.85,
          children: others.map((p) {
            final voted = g.myVote == p.playerId;
            final disabled = g.myVote != null && !voted;
            return GestureDetector(
              onTap: g.myVote != null ? null : () => g.castVote(p.playerId),
              child: Opacity(
                opacity: disabled ? 0.4 : 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: voted ? AppColors.accent.withValues(alpha: 0.16) : AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: voted ? AppColors.accent : AppColors.border, width: voted ? 2 : 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _avatar(p.playerName, 44),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(p.playerName,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (g.myVote != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Center(
              child: Text('You voted for ${g.players.where((p) => p.playerId == g.myVote).map((p) => p.playerName).join()}',
                  style: TextStyle(color: AppColors.accentBright, fontWeight: FontWeight.w700)),
            ),
          ),
        if (g.isHost) ...[
          const SizedBox(height: 16),
          _secondaryBtn('End Match', Icons.flag_rounded, () => g.endGame()),
        ],
      ],
    );
  }

  // ── Result ──
  Widget _result(ImposterGame g) {
    final r = g.room!;
    final approved = g.players.where((p) => p.isApproved).toList();
    final imposters = approved.where((p) => p.isImposter).toList();
    final voters = approved.where((p) => p.voteFor != null).toList();

    // Record standings once at match end (host).
    final hasMore = r.roundsCurrent < r.roundsTotal;
    if (g.isHost && !hasMore && !_standingsRecorded) {
      _standingsRecorded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => g.recordStandings());
    }
    if (hasMore && _standingsRecorded) _standingsRecorded = false;

    // Outcome
    final counts = <String, int>{};
    for (final p in approved) {
      if (p.voteFor != null) counts[p.voteFor!] = (counts[p.voteFor!] ?? 0) + 1;
    }
    final maxVotes = counts.values.isEmpty ? 0 : counts.values.reduce((a, b) => a > b ? a : b);
    final top = counts.entries.where((e) => e.value == maxVotes).map((e) => e.key).toList();
    final crewWon = maxVotes > 0 && top.length == 1 && imposters.any((p) => p.playerId == top.first);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: (r.skipVote ? AppColors.accent : (crewWon ? AppColors.greenBright : AppColors.red)).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: (r.skipVote ? AppColors.accent : (crewWon ? AppColors.greenBright : AppColors.red)).withValues(alpha: 0.4)),
          ),
          child: Column(children: [
            Text(
              r.skipVote ? 'Discussion Over! 🎉' : (crewWon ? 'Crewmates Win! 🎉' : 'Imposter Wins! 🕵️'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textBright, fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              r.skipVote
                  ? 'No vote — discuss who you think it was!'
                  : (crewWon ? 'You identified the imposter!' : 'The imposter fooled everyone!'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (r.revealAtEnd) ...[
          _label('THE IMPOSTER(S) WERE'),
          Wrap(spacing: 8, runSpacing: 8, children: imposters.map((p) => _chip(p.playerName, AppColors.red)).toList()),
          const SizedBox(height: 16),
        ],
        if (!r.skipVote) ...[
          _label('VOTE RESULTS'),
          if (voters.isEmpty)
            Text('No votes cast', style: TextStyle(color: AppColors.muted))
          else
            ...voters.map((p) {
              final target = approved.where((t) => t.playerId == p.voteFor).toList();
              final tName = target.isEmpty ? '—' : target.first.playerName;
              final tImp = imposters.any((i) => i.playerId == p.voteFor);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Text(p.playerName, style: TextStyle(color: AppColors.text, fontSize: 13)),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.muted)),
                  Text('$tName${tImp ? ' 🕵️' : ''}',
                      style: TextStyle(color: tImp ? AppColors.red : AppColors.text, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              );
            }),
          const SizedBox(height: 16),
        ],
        if (r.roundsTotal > 1) ...[
          Row(children: [
            Expanded(child: _scoreBox('Crewmates', r.crewmateScore, AppColors.greenBright)),
            const SizedBox(width: 10),
            Expanded(child: _scoreBox('Imposters', r.imposterScore, AppColors.red)),
          ]),
          const SizedBox(height: 16),
        ],
        if (g.isHost) ...[
          if (hasMore)
            _primaryBtn('Start Round ${r.roundsCurrent + 1}', Icons.rotate_right_rounded, () => g.nextRound()),
          const SizedBox(height: 10),
          _secondaryBtn('Back to Lobby', Icons.home_rounded, () => g.backToLobby()),
        ] else
          Center(child: Padding(padding: EdgeInsets.all(8), child: Text('Waiting for host…', style: TextStyle(color: AppColors.muted)))),
        const SizedBox(height: 10),
        _secondaryBtn('Leave Room', Icons.logout_rounded, _leaveToHub),
      ],
    );
  }

  // ── Shared UI bits ──
  Widget _timerChip(ImposterGame g) {
    final s = g.secondsLeft;
    final txt = s < 0 ? '∞' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    final urgent = s >= 0 && s <= 10;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: (urgent ? AppColors.red : AppColors.accent).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: (urgent ? AppColors.red : AppColors.accent).withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timer_rounded, size: 16, color: urgent ? AppColors.red : AppColors.accentBright),
          const SizedBox(width: 6),
          Text(txt,
              style: TextStyle(
                  color: urgent ? AppColors.red : AppColors.accentBright,
                  fontSize: 16, fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }

  Widget _playerChip(ImposterGame g, ImposterPlayer p) {
    final isMe = p.playerId == g.identity.playerId;
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? AppColors.accent.withValues(alpha: 0.1) : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isMe ? AppColors.borderAccent : AppColors.border),
      ),
      child: Column(children: [
        _avatar(p.playerName, 44),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(p.playerName, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.text, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _settingsEditor({required VoidCallback setStateLocal, ImposterGame? live}) {
    // For an in-lobby host, edits push to the room; otherwise edit local settings.
    void apply(String col, Object v, void Function() local) {
      local();
      setState(() {});
      if (live != null) live.updateSettings({col: v});
    }

    Widget dropdown(String label, String value, Map<String, String> opts, void Function(String) onPick) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          DropdownButton<String>(
            value: value,
            dropdownColor: AppColors.surface,
            underline: const SizedBox.shrink(),
            style: TextStyle(color: AppColors.textBright, fontSize: 13, fontWeight: FontWeight.w600),
            items: opts.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) { if (v != null) onPick(v); },
          ),
        ]),
      );
    }

    Widget stepper(String label, int value, int minV, int maxV, void Function(int) onSet) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.remove_circle_outline, size: 20, color: AppColors.muted), onPressed: value > minV ? () => onSet(value - 1) : null),
          Text('$value', style: TextStyle(color: AppColors.textBright, fontWeight: FontWeight.w700)),
          IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.add_circle_outline, size: 20, color: AppColors.muted), onPressed: value < maxV ? () => onSet(value + 1) : null),
        ]),
      );
    }

    Widget toggle(String label, bool value, void Function(bool) onSet) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          Switch(value: value, activeThumbColor: AppColors.accent, onChanged: onSet),
        ]),
      );
    }

    final s = _settings;
    final wordPack = live?.room?.wordPack ?? s.wordPack;
    final impCount = live?.room?.imposterCount ?? s.imposterCount;
    final discuss = live?.room?.discussionTime ?? s.discussionTime;
    final voting = live?.room?.votingTime ?? s.votingTime;
    final rounds = live?.room?.roundsTotal ?? s.rounds;
    final maxP = live?.room?.maxPlayers ?? s.maxPlayers;
    final priv = live?.room?.isPrivate ?? s.isPrivate;
    final guests = live?.room?.guestsAllowed ?? s.guestsAllowed;
    final skipVote = live?.room?.skipVote ?? s.skipVote;
    final reveal = live?.room?.revealAtEnd ?? s.revealAtEnd;

    return Column(children: [
      dropdown('Word pack', wordPack, {for (final p in kWordPacks) p.key: '${p.icon} ${p.label}'},
          (v) => apply('word_pack', v, () => s.wordPack = v)),
      stepper('Imposters', impCount, 1, 3, (v) => apply('imposter_count', v, () => s.imposterCount = v)),
      stepper('Rounds', rounds, 1, 10, (v) => apply('rounds_total', v, () => s.rounds = v)),
      stepper('Max players', maxP, 3, 20, (v) => apply('max_players', v, () => s.maxPlayers = v)),
      dropdown('Discussion', '$discuss', {'30': '30s', '60': '60s', '90': '90s', '120': '120s', '0': '∞'},
          (v) => apply('discussion_time', int.parse(v), () => s.discussionTime = int.parse(v))),
      if (!skipVote)
        dropdown('Voting', '$voting', {'30': '30s', '45': '45s', '60': '60s', '90': '90s', '0': '∞'},
            (v) => apply('voting_time', int.parse(v), () => s.votingTime = int.parse(v))),
      toggle('Private (approve joins)', priv, (v) => apply('is_private', v, () => s.isPrivate = v)),
      toggle('Allow guests', guests, (v) => apply('guests_allowed', v, () => s.guestsAllowed = v)),
      toggle('Skip voting', skipVote, (v) => apply('skip_vote', v, () => s.skipVote = v)),
      toggle('Reveal at end', reveal, (v) => apply('reveal_at_end', v, () => s.revealAtEnd = v)),
    ]);
  }

  // ── Atoms ──
  Widget _hero(String emoji, String title, String sub) => Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 46)),
        const SizedBox(height: 8),
        Text(title, style: TextStyle(color: AppColors.textBright, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(sub, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
      ]);

  Widget _card({required String title, required Widget child}) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: AppColors.textBright, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: TextStyle(color: AppColors.accentBright, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
      );

  Widget _primaryBtn(String label, IconData icon, VoidCallback? onTap) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap,
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(vertical: 13)),
          icon: Icon(icon, size: 18),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );

  Widget _secondaryBtn(String label, IconData icon, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary, side: BorderSide(color: AppColors.border), padding: const EdgeInsets.symmetric(vertical: 12)),
          icon: Icon(icon, size: 16),
          label: Text(label),
        ),
      );

  Widget _scoreBox(String label, int v, Color c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.3))),
        child: Column(children: [
          Text('$v', style: TextStyle(color: c, fontSize: 26, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
      );

  Widget _chip(String name, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withValues(alpha: 0.35))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _avatar(name, 22),
          const SizedBox(width: 6),
          Text(name, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      );

  Widget _avatar(String name, double size) {
    final colors = [const Color(0xFF7c3aed), const Color(0xFF2563eb), const Color(0xFFdc2626), const Color(0xFF059669), const Color(0xFFd97706), const Color(0xFFdb2777), const Color(0xFF0891b2), const Color(0xFF65a30d)];
    var h = 0;
    for (final c in (name.isEmpty ? '?' : name).codeUnits) {
      h = ((h << 5) - h) + c;
    }
    final bg = colors[h.abs() % colors.length];
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).map((w) => w.isEmpty ? '' : w[0]).take(2).join().toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(initials, style: TextStyle(color: Colors.white, fontSize: size * 0.36, fontWeight: FontWeight.w700)),
    );
  }

  Future<bool> _confirm(String msg) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.card,
            content: Text(msg, style: TextStyle(color: AppColors.text)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Stay', style: TextStyle(color: AppColors.muted))),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Leave', style: TextStyle(color: AppColors.red))),
            ],
          ),
        ) ??
        false;
  }
}
