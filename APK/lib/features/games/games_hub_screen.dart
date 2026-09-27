import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/supa.dart';
import '../../data/session.dart';

/// Native Games hub — lists the multiplayer games and the overall standings,
/// mirroring the website's games lobby. Games run natively (not a WebView) but
/// against the same Supabase backend, so app and web players share rooms and
/// the combined leaderboard.
class GamesHubScreen extends StatefulWidget {
  const GamesHubScreen({super.key});

  @override
  State<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends State<GamesHubScreen> {
  late Future<List<_Standing>> _future = _loadStandings();
  String? _myId;

  @override
  void initState() {
    super.initState();
    final s = Session.instance.student;
    if (s != null && !Session.instance.isDemo) _myId = 'student_${s.id}';
  }

  Future<List<_Standing>> _loadStandings() async {
    try {
      final rows = await Supa.client.from('game_standings').select().limit(500);
      final data = (rows as List).cast<Map<String, dynamic>>();
      if (data.isEmpty) return [];
      // Bayesian-shrunk rating with a win bonus (mirrors the website exactly).
      final totGames = data.fold<int>(0, (s, p) => s + _i(p['games_played']));
      final totPts = data.fold<int>(0, (s, p) => s + _i(p['total_points']));
      final m = totGames > 0 ? totPts / totGames : 0.0;
      const c = 3, winBonus = 75;
      final list = data.map((p) {
        final g = _i(p['games_played']);
        final rating = g > 0 ? (_i(p['total_points']) + _i(p['wins']) * winBonus + c * m) / (g + c) : 0.0;
        return _Standing(
          id: '${p['player_id']}',
          name: '${p['player_name'] ?? 'Player'}',
          rating: rating,
          wins: _i(p['wins']),
          games: g,
        );
      }).toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));
      return list.take(20).toList();
    } catch (_) {
      return [];
    }
  }

  static int _i(Object? v) => v is int ? v : int.tryParse('${v ?? 0}') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Games'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.card,
        onRefresh: () async => setState(() => _future = _loadStandings()),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            _gameCard(
              emoji: '🕵️',
              title: 'Imposter',
              desc: "One player is the imposter who doesn't know the secret word. Can the crew catch them?",
              accent: const Color(0xFFf43f5e),
              onTap: () => context.push('/games/imposter'),
            ),
            const SizedBox(height: 12),
            _gameCard(
              emoji: '🎨',
              title: 'Draw & Guess',
              desc: 'One player draws a secret word while everyone races to guess it. Faster guesses score more!',
              accent: const Color(0xFF8b5cf6),
              onTap: () => context.push('/games/draw'),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFfbbf24), Color(0xFFfb923c)]).createShader(r),
                  child: const Text('Overall Standings',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Combined across all games · logged-in players only',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
            const SizedBox(height: 12),
            _standings(),
          ],
        ),
      ),
    );
  }

  Widget _gameCard({required String emoji, required String title, required String desc, required Color accent, required VoidCallback onTap}) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withValues(alpha: 0.12), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(15)),
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(title, style: TextStyle(color: AppColors.textBright, fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6)),
                        child: Text('Multiplayer', style: TextStyle(color: accent, fontSize: 9.5, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 5),
                    Text(desc, style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _standings() {
    return FutureBuilder<List<_Standing>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
          );
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Center(
              child: Text('No games played yet. Be the first to top the board! 🎮',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
          );
        }
        const medals = ['🥇', '🥈', '🥉'];
        return Container(
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(14, 11, 14, 9),
                child: Row(children: [
                  SizedBox(width: 28, child: Text('#', textAlign: TextAlign.center, style: _hStyle)),
                  Expanded(child: Text('PLAYER', style: _hStyle)),
                  SizedBox(width: 52, child: Text('RATING', textAlign: TextAlign.right, style: _hStyle)),
                  SizedBox(width: 42, child: Text('WINS', textAlign: TextAlign.right, style: _hStyle)),
                  SizedBox(width: 46, child: Text('PLAYED', textAlign: TextAlign.right, style: _hStyle)),
                ]),
              ),
              for (var i = 0; i < list.length; i++) _row(i, list[i], i < medals.length ? medals[i] : '${i + 1}'),
            ],
          ),
        );
      },
    );
  }

  Widget _row(int i, _Standing p, String rank) {
    final isMe = _myId != null && p.id == _myId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: i == 0 ? const Color(0xFFfbbf24).withValues(alpha: 0.06) : null,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        SizedBox(width: 28, child: Text(rank, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textBright))),
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text(p.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: isMe ? const Color(0xFF34d399) : AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
            if (isMe)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text('YOU', style: TextStyle(color: Color(0xFF34d399), fontSize: 9, fontWeight: FontWeight.w900)),
              ),
          ]),
        ),
        SizedBox(width: 52, child: Text('${p.rating.round()}', textAlign: TextAlign.right, style: TextStyle(color: AppColors.accentBright, fontSize: 13, fontWeight: FontWeight.w800))),
        SizedBox(width: 42, child: Text('${p.wins}', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
        SizedBox(width: 46, child: Text('${p.games}', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
      ]),
    );
  }

  static TextStyle get _hStyle => TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4);
}

class _Standing {
  final String id, name;
  final double rating;
  final int wins, games;
  const _Standing({required this.id, required this.name, required this.rating, required this.wins, required this.games});
}
