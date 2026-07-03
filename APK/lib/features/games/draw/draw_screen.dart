import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_colors.dart';
import '../../../shared/app_toast.dart';
import '../game_identity.dart';
import 'draw_canvas.dart';
import 'draw_game.dart';
import 'draw_models.dart';

/// Native Draw & Guess — full canvas game (live strokes, flood-fill, undo,
/// word-pick, hint reveal, guessing, scoring) over the shared Supabase backend,
/// so app players share rooms and standings with the website.
class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key});

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> {
  DrawGame? _g;
  GameIdentity? _id;
  final _nameCtrl = TextEditingController();
  final _joinCtrl = TextEditingController();
  final _chatCtrl = TextEditingController();
  final _settings = DrawSettings();
  bool _busy = false;

  // Drawing pointer state
  double _lastX = 0, _lastY = 0;

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
      _g = DrawGame(id);
    });
  }

  @override
  void dispose() {
    _g?.dispose();
    _nameCtrl.dispose();
    _joinCtrl.dispose();
    _chatCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshIdentityName() async {
    final id = await GameIdentity.resolve(guestName: _nameCtrl.text.trim());
    final old = _g;
    setState(() {
      _id = id;
      _g = DrawGame(id);
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
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (g.roomCode != null) {
          if (await _confirm('Leave the room?')) await _leaveToHub();
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
              title: const Text('Draw & Guess'),
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
            body: !inRoom
                ? _home(g)
                : switch (g.room!.status) {
                    'lobby' => _lobby(g),
                    'round_end' => _roundEnd(g),
                    'game_over' => _gameOver(g),
                    _ => _gameBoard(g),
                  },
          );
        },
      ),
    );
  }

  // ════════════════ HOME ════════════════
  Widget _home(DrawGame g) {
    final isGuest = _id?.isGuest ?? true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const SizedBox(height: 8),
        const Center(child: Text('🎨', style: TextStyle(fontSize: 56))),
        const SizedBox(height: 10),
        const Center(
          child: Text('Draw & Guess',
              style: TextStyle(color: AppColors.textBright, fontSize: 24, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text('One player draws, everyone else guesses. Faster guesses score more!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
        ),
        const SizedBox(height: 22),
        // Identity
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _panelDeco(),
          child: Row(
            children: [
              _avatar(_id?.playerId ?? '?', _nameCtrl.text, 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PLAYING AS',
                        style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    const SizedBox(height: 2),
                    if (!isGuest)
                      Text(_id?.playerName ?? '', style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700))
                    else
                      TextField(
                        controller: _nameCtrl,
                        maxLength: 20,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: AppColors.text, fontSize: 15),
                        decoration: const InputDecoration(
                          isDense: true,
                          counterText: '',
                          hintText: 'Enter your name…',
                          hintStyle: TextStyle(color: AppColors.muted),
                          border: UnderlineInputBorder(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Create / Join
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _panelDeco(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CREATE OR JOIN A ROOM',
                  style: TextStyle(color: AppColors.accentBright, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _onCreate(g),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7c3aed), padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create Room', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _joinCtrl,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, letterSpacing: 3),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'ROOM CODE',
                        hintStyle: const TextStyle(color: AppColors.muted, letterSpacing: 1),
                        filled: true,
                        fillColor: AppColors.bg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _busy ? null : () => _onJoin(g),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
                    child: const Text('Join', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _ensureGuestName(DrawGame g) async {
    if ((_id?.isGuest ?? false) && _nameCtrl.text.trim().isNotEmpty && g.identity.playerName.trim().isEmpty) {
      await _refreshIdentityName();
    }
  }

  Future<void> _onCreate(DrawGame g) async {
    if ((_id?.isGuest ?? false) && _nameCtrl.text.trim().isEmpty) {
      AppToast.show(context, 'Please enter your name first!');
      return;
    }
    await _ensureGuestName(g);
    final game = _g!;
    setState(() => _busy = true);
    final err = await game.createRoom(_settings);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) AppToast.show(context, err);
  }

  Future<void> _onJoin(DrawGame g) async {
    if ((_id?.isGuest ?? false) && _nameCtrl.text.trim().isEmpty) {
      AppToast.show(context, 'Please enter your name first!');
      return;
    }
    await _ensureGuestName(g);
    final game = _g!;
    setState(() => _busy = true);
    final err = await game.joinRoom(_joinCtrl.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) AppToast.show(context, err);
  }

  // ════════════════ LOBBY ════════════════
  Widget _lobby(DrawGame g) {
    final shown = g.players.where((p) => p.active).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _panelDeco(),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ROOM CODE', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  Text(g.roomCode ?? '',
                      style: const TextStyle(color: AppColors.accentBright, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4)),
                ],
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: g.roomCode ?? ''));
                  AppToast.show(context, 'Code copied');
                },
                icon: const Icon(Icons.copy_rounded, color: AppColors.accentBright, size: 20),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  if (await _confirm('Leave the room?')) await _leaveToHub();
                },
                child: const Text('Leave', style: TextStyle(color: AppColors.red)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Players
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _panelDeco(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PLAYERS  ${shown.length} / ${g.room?.maxPlayers ?? 8}',
                  style: const TextStyle(color: AppColors.accentBright, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 10),
              ...shown.map((p) => _lobbyPlayerRow(g, p)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Settings
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _panelDeco(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SETTINGS', style: TextStyle(color: AppColors.accentBright, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 8),
              if (g.isHost) ..._hostSettings(g) else ..._readonlySettings(g),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (g.isHost)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: shown.length >= 2 ? () => _onStart(g) : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(vertical: 15)),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(shown.length >= 2 ? 'Start Game' : 'Need at least 2 players',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          )
        else
          const Center(
            child: Text('Waiting for host to start the game…',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
      ],
    );
  }

  Widget _lobbyPlayerRow(DrawGame g, DrawPlayer p) {
    final on = g.online.contains(p.playerId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          _avatar(p.playerId, p.playerName, 30),
          const SizedBox(width: 9),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? const Color(0xFF34D399) : AppColors.muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(p.playerName, style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w600))),
          if (g.room?.hostId == p.playerId) _tag('HOST', const Color(0xFFFBBF24)),
          if (p.playerId == g.identity.playerId) ...[const SizedBox(width: 4), _tag('YOU', AppColors.accentBright)],
        ],
      ),
    );
  }

  List<Widget> _hostSettings(DrawGame g) {
    final r = g.room!;
    return [
      _settingRow('Rounds', r.roundsTotal, const [2, 3, 4, 5], (v) => g.updateSettings({'rounds_total': v})),
      _settingRow('Draw Time', r.drawTime, const [60, 80, 100, 120], (v) => g.updateSettings({'draw_time': v}), suffix: 's'),
      _settingRow('Max Players', r.maxPlayers, const [4, 6, 8, 10, 12], (v) => g.updateSettings({'max_players': v})),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Expanded(child: Text('Guest Access', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
            DropdownButton<bool>(
              value: r.guestsAllowed,
              dropdownColor: AppColors.card,
              underline: const SizedBox.shrink(),
              style: const TextStyle(color: AppColors.text, fontSize: 13),
              items: const [
                DropdownMenuItem(value: true, child: Text('🔓 Anyone')),
                DropdownMenuItem(value: false, child: Text('🔒 Login Required')),
              ],
              onChanged: (v) => g.updateSettings({'guests_allowed': v ?? true}),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _settingRow(String label, int value, List<int> opts, void Function(int) onPick, {String suffix = ''}) {
    final items = {...opts, value}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          DropdownButton<int>(
            value: value,
            dropdownColor: AppColors.card,
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            items: items.map((o) => DropdownMenuItem(value: o, child: Text('$o$suffix'))).toList(),
            onChanged: (v) {
              if (v != null) onPick(v);
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _readonlySettings(DrawGame g) {
    final r = g.room!;
    String row(String k, String v) => '$k: $v';
    return [
      const SizedBox(height: 4),
      Text(row('Rounds', '${r.roundsTotal}'), style: _roTextStyle),
      Text(row('Draw Time', '${r.drawTime}s'), style: _roTextStyle),
      Text(row('Max Players', '${r.maxPlayers}'), style: _roTextStyle),
      Text(row('Guest Access', r.guestsAllowed ? '🔓 Anyone' : '🔒 Login Required'), style: _roTextStyle),
    ];
  }

  static const _roTextStyle = TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.9);

  Future<void> _onStart(DrawGame g) async {
    final err = await g.startGame();
    if (err != null && mounted) AppToast.show(context, err);
  }

  // ════════════════ GAME BOARD ════════════════
  Widget _gameBoard(DrawGame g) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final kbOpen = MediaQuery.of(ctx).viewInsets.bottom > 0;
        // Reserve room for the fixed rows so the canvas shrinks (instead of the
        // chat collapsing) when the keyboard is up — drawing, hint gaps and the
        // chat input all stay on screen while a guesser types.
        final toolbarH = g.isDrawer ? 100.0 : 0.0;
        final scoresH = kbOpen ? 0.0 : 58.0;
        final reserved = 60 + 36 + toolbarH + scoresH + 64 + 96 + 24;
        final fullCanvasH = (c.maxWidth - 20) * kCanvasH / kCanvasW;
        final canvasH = (c.maxHeight - reserved).clamp(110.0, fullCanvasH);
        return Column(
          children: [
            ..._gameBoardRows(g, canvasH, hideScores: kbOpen),
          ],
        );
      },
    );
  }

  List<Widget> _gameBoardRows(DrawGame g, double canvasH, {required bool hideScores}) {
    final r = g.room!;
    final drawer = g.players.where((p) => p.playerId == r.currentDrawer).toList();
    final drawerName = drawer.isEmpty ? '?' : drawer.first.playerName;
    final left = g.secondsLeft;
    final low = left >= 0 && left <= 10;

    return [
        // Top bar
        Container(
          margin: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: _panelDeco(),
          child: Row(
            children: [
              Text('Round ${r.roundCurrent}/${r.roundsTotal}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  g.isDrawer ? 'You are drawing!' : '$drawerName is drawing',
                  style: const TextStyle(color: AppColors.accentBright, fontSize: 13, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (r.status == 'drawing')
                Text(left >= 0 ? '$left' : '—',
                    style: TextStyle(
                        color: low ? AppColors.red : const Color(0xFFFBBF24),
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
              if (g.isHost) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () async {
                    if (await _confirm('End the game and show standings?')) await g.endGame();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.flag_rounded, size: 18, color: AppColors.muted),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Hint line
        if (r.status == 'drawing')
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              g.isDrawer ? (r.currentWord ?? '') : formatHint(r.currentHint ?? ''),
              style: TextStyle(
                color: g.isDrawer ? const Color(0xFF34D399) : AppColors.text,
                fontSize: g.isDrawer ? 16 : 20,
                fontWeight: FontWeight.w700,
                letterSpacing: g.isDrawer ? 2 : 5,
              ),
            ),
          ),
        // Canvas
        _canvasArea(g, canvasH),
        // Toolbar
        if (g.isDrawer) _toolbar(g),
        // Scores
        if (!hideScores) _scoresStrip(g),
        // Chat
        Expanded(child: _chatPanel(g)),
    ];
  }

  Widget _canvasArea(DrawGame g, double maxH) {
    final r = g.room!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: LayoutBuilder(
        builder: (ctx, c) {
          var w = c.maxWidth;
          var h = w * kCanvasH / kCanvasW;
          if (h > maxH) {
            h = maxH;
            w = h * kCanvasW / kCanvasH;
          }
          return Center(
            child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                SizedBox(
                  width: w,
                  height: h,
                  child: Listener(
                    onPointerDown: g.isDrawer && r.status == 'drawing' ? (e) => _onPointerDown(g, e.localPosition, w, h) : null,
                    onPointerMove: g.isDrawer && r.status == 'drawing' ? (e) => _onPointerMove(g, e.localPosition, w, h) : null,
                    child: Container(
                      color: Colors.white,
                      child: CustomPaint(
                        painter: DrawCanvasPainter(g.canvas),
                        size: Size(w, h),
                      ),
                    ),
                  ),
                ),
                if (r.status == 'word_pick')
                  Positioned.fill(child: _wordPickOverlay(g)),
              ],
            ),
          ),
          );
        },
      ),
    );
  }

  void _onPointerDown(DrawGame g, Offset local, double w, double h) {
    final x = local.dx * kCanvasW / w;
    final y = local.dy * kCanvasH / h;
    _lastX = x;
    _lastY = y;
    g.strokeStart();
    if (g.currentTool == 'fill') g.doFill(x, y);
  }

  void _onPointerMove(DrawGame g, Offset local, double w, double h) {
    if (g.currentTool == 'fill') return;
    final x = local.dx * kCanvasW / w;
    final y = local.dy * kCanvasH / h;
    g.drawSegment(_lastX, _lastY, x, y);
    _lastX = x;
    _lastY = y;
  }

  Widget _wordPickOverlay(DrawGame g) {
    final r = g.room!;
    final dn = g.players.where((p) => p.playerId == r.currentDrawer).toList();
    final waitingFor = dn.isEmpty ? '?' : dn.first.playerName;
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: g.isDrawer
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Choose a word to draw',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Others cannot see your choice',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 16),
                ...r.wordChoices.map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        width: 220,
                        child: FilledButton(
                          onPressed: () => g.pickWord(w),
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF34D399).withValues(alpha: 0.18),
                              foregroundColor: const Color(0xFF34D399),
                              padding: const EdgeInsets.symmetric(vertical: 13)),
                          child: Text(w, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    )),
              ],
            )
          : Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Waiting for ', style: TextStyle(color: Colors.white70)),
                TextSpan(
                  text: waitingFor,
                  style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: ' to pick a word…', style: TextStyle(color: Colors.white70)),
              ]),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
    );
  }

  Widget _toolbar(DrawGame g) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: _panelDeco(),
      child: Column(
        children: [
          // Colours
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final c in kDrawColors)
                GestureDetector(
                  onTap: () => setState(() {
                    g.currentColor = Color(c);
                    if (g.currentTool == 'eraser') g.currentTool = 'pencil';
                  }),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: g.currentColor.toARGB32() == c && g.currentTool != 'eraser'
                            ? AppColors.text
                            : AppColors.border,
                        width: g.currentColor.toARGB32() == c && g.currentTool != 'eraser' ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Brush + tools
          Row(
            children: [
              for (final s in const [5.0, 12.0, 22.0])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => g.currentSize = s),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: g.currentSize == s ? AppColors.accent : AppColors.border, width: 2),
                      ),
                      child: Center(
                        child: Container(
                          width: s * 0.8,
                          height: s * 0.8,
                          decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              _toolBtn(g, 'pencil', Icons.edit_rounded),
              _toolBtn(g, 'eraser', Icons.cleaning_services_rounded),
              _toolBtn(g, 'fill', Icons.format_color_fill_rounded),
              const Spacer(),
              IconButton(
                onPressed: g.canvas.canUndo ? () => g.undo() : null,
                icon: const Icon(Icons.undo_rounded, size: 20),
                color: const Color(0xFF60A5FA),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () => g.clearCanvas(),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppColors.red,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(DrawGame g, String tool, IconData icon) {
    final sel = g.currentTool == tool;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => g.currentTool = tool),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: sel ? AppColors.accent.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? AppColors.accent : AppColors.border),
          ),
          child: Icon(icon, size: 18, color: sel ? AppColors.accentBright : AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _scoresStrip(DrawGame g) {
    final sorted = [...g.players]..sort((a, b) {
        final la = a.active ? 0 : 1, lb = b.active ? 0 : 1;
        return la != lb ? la - lb : b.score - a.score;
      });
    return Container(
      height: 52,
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = sorted[i];
          final left = !p.active;
          final offline = !left && !g.online.contains(p.playerId);
          final drawing = !left && p.playerId == g.room?.currentDrawer;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: drawing ? const Color(0xFFFBBF24) : AppColors.border),
            ),
            child: Opacity(
              opacity: left ? 0.45 : (offline ? 0.6 : 1),
              child: Row(
                children: [
                  _avatar(p.playerId, p.playerName, 24),
                  const SizedBox(width: 7),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(p.playerName.length > 9 ? '${p.playerName.substring(0, 9)}…' : p.playerName,
                              style: TextStyle(
                                  color: drawing ? const Color(0xFFFBBF24) : AppColors.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          if (p.hasGuessed && !drawing)
                            const Padding(
                              padding: EdgeInsets.only(left: 3),
                              child: Icon(Icons.check_rounded, size: 13, color: Color(0xFF34D399)),
                            ),
                        ],
                      ),
                      Text('${p.score} pts',
                          style: const TextStyle(color: AppColors.accentBright, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chatPanel(DrawGame g) {
    final canChat = !g.isDrawer && g.me?.hasGuessed != true && g.room?.status == 'drawing';
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: _panelDeco(),
      child: Column(
        children: [
          Expanded(
            child: g.chat.isEmpty
                ? const Center(
                    child: Text('Guesses appear here…', style: TextStyle(color: AppColors.muted, fontSize: 12)))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: g.chat.length,
                    itemBuilder: (_, i) {
                      final m = g.chat[g.chat.length - 1 - i];
                      final close = m.message.contains('(close!)');
                      if (m.isCorrect) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34D399).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4)),
                            ),
                            child: Text('${m.playerName} guessed it! 🎉',
                                style: const TextStyle(color: Color(0xFF34D399), fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.5),
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                            text: '${m.playerName}: ',
                            style: TextStyle(color: Color(drawAvatarColor(m.playerId)), fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: m.message,
                            style: TextStyle(color: close ? const Color(0xFFFBBF24) : AppColors.textSecondary, fontSize: 12.5),
                          ),
                        ])),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatCtrl,
                    enabled: canChat,
                    onSubmitted: (_) => _send(g),
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(color: AppColors.text, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: g.isDrawer
                          ? "You're drawing…"
                          : g.me?.hasGuessed == true
                              ? 'You already guessed!'
                              : 'Type your guess…',
                      hintStyle: const TextStyle(color: AppColors.muted),
                      filled: true,
                      fillColor: AppColors.bg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: canChat ? () => _send(g) : null,
                  icon: const Icon(Icons.send_rounded, size: 20),
                  color: AppColors.accent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send(DrawGame g) async {
    final t = _chatCtrl.text;
    if (t.trim().isEmpty) return;
    _chatCtrl.clear();
    await g.sendGuess(t);
  }

  // ════════════════ ROUND END ════════════════
  Widget _roundEnd(DrawGame g) {
    final players = g.roundEndPlayers;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: _panelDeco(),
          child: Column(
            children: [
              const Text('THE WORD WAS', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 6),
              Text(g.room?.currentWord ?? '?',
                  style: const TextStyle(color: Color(0xFF34D399), fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),
              const Text('SCORES', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 10),
              ...players.asMap().entries.map((e) {
                final i = e.key;
                final p = e.value;
                final gain = g.gainFor(p);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      SizedBox(width: 22, child: Text('${i + 1}', style: TextStyle(color: _rankColor(i), fontSize: 13, fontWeight: FontWeight.w800))),
                      _avatar(p.playerId, p.playerName, 28),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.playerName, style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w600))),
                      Text('${p.score}', style: const TextStyle(color: Color(0xFF34D399), fontSize: 14, fontWeight: FontWeight.w800)),
                      if (gain > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: Text('+$gain', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                        ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 14),
              if (g.isHost)
                FilledButton.icon(
                  onPressed: () => g.nextTurn(),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Next Turn'),
                )
              else
                const Text('Waiting for host…', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════ GAME OVER ════════════════
  Widget _gameOver(DrawGame g) {
    final players = g.gameOverPlayers;
    final winner = players.isEmpty ? null : players.first;
    const medals = ['🥇', '🥈', '🥉'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        const Center(child: Text('🏆', style: TextStyle(fontSize: 60))),
        const SizedBox(height: 6),
        const Center(child: Text('Game Over!', style: TextStyle(color: AppColors.textBright, fontSize: 26, fontWeight: FontWeight.w900))),
        const SizedBox(height: 6),
        if (winner != null)
          Center(
            child: Text('${winner.playerName} wins with ${winner.score} pts!',
                style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _panelDeco(),
          child: Column(
            children: players.asMap().entries.map((e) {
              final i = e.key;
              final p = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(width: 30, child: Text(i < 3 ? medals[i] : '${i + 1}', style: const TextStyle(fontSize: 18), textAlign: TextAlign.center)),
                    const SizedBox(width: 6),
                    _avatar(p.playerId, p.playerName, 30),
                    const SizedBox(width: 10),
                    Expanded(child: Text(p.playerName, style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600))),
                    Text('${p.score} pts', style: const TextStyle(color: Color(0xFF34D399), fontSize: 15, fontWeight: FontWeight.w900)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (g.isHost)
              FilledButton.icon(
                onPressed: () => g.backToLobby(),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7c3aed)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Play Again'),
              ),
            if (g.isHost) const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () async {
                if (await _confirm('Leave the game?')) await _leaveToHub();
              },
              icon: const Icon(Icons.door_front_door_rounded),
              label: const Text('Leave'),
            ),
          ],
        ),
      ],
    );
  }

  // ════════════════ shared bits ════════════════
  Color _rankColor(int i) => switch (i) {
        0 => const Color(0xFFFBBF24),
        1 => const Color(0xFF94A3B8),
        2 => const Color(0xFFB45309),
        _ => AppColors.muted,
      };

  BoxDecoration _panelDeco() => BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      );

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      );

  Widget _avatar(String id, String name, double size) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Color(drawAvatarColor(id)), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(letter, style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w800)),
    );
  }

  Future<bool> _confirm(String msg) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        content: Text(msg, style: const TextStyle(color: AppColors.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: AppColors.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    return res ?? false;
  }
}
