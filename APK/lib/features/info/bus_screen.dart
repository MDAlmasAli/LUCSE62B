import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../data/exam_repository.dart';

/// Bus schedule — Regular / Exam tabs, a live "Next Bus" countdown, day-group
/// chips, and side-by-side To LU / From LU timelines (past = red, next =
/// highlighted, upcoming = green). Mirrors the website's bus.js.
class BusScreen extends StatefulWidget {
  const BusScreen({super.key});

  @override
  State<BusScreen> createState() => _BusScreenState();
}

class _BusScreenState extends State<BusScreen> {
  late Future<Map<String, _Schedule>> _future = _load();
  Timer? _ticker;

  // Persisted UI state.
  String _tab = 'regular';
  String? _regDayGrp;
  String? _examDayGrp;
  bool _examDay = false;

  static const _green = Color(0xFF34D399);
  static const _blue = Color(0xFF38BDF8);
  static const _red = Color(0xFFF87171);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<Map<String, _Schedule>> _load() async {
    final results = await Future.wait([
      SheetsApi.instance.sheet('Bus').then<Object>((value) => value),
      ExamRepository.instance
          .hasExamToday(batch: '62', section: 'B')
          .then<Object>((value) => value)
          .catchError((_) => false),
    ]);
    _examDay = results[1] as bool;
    return _parse(results[0] as List<List<String>>);
  }

  Map<String, _Schedule> _parse(List<List<String>> rows) {
    final out = <String, _Schedule>{};
    if (rows.isEmpty) return out;
    final start =
        (rows[0].isNotEmpty && rows[0][0].toLowerCase().trim() == 'schedule')
        ? 1
        : 0;
    for (var i = start; i < rows.length; i++) {
      final r = rows[i];
      String at(int n) => n < r.length ? r[n].trim() : '';
      final sched = at(0),
          dayGrp = at(1),
          dir = at(2),
          time = at(3),
          note = at(4);
      if (sched.isEmpty || time.isEmpty) continue;
      final s = out.putIfAbsent(sched, () => _Schedule());
      final d = s.days.putIfAbsent(dayGrp, () => _DayData());
      if (dir.toLowerCase().contains('from')) {
        d.fromLU.add(_Trip(time, note));
      } else {
        d.toLU.add(_Trip(time, note));
      }
    }
    return out;
  }

  // ── time helpers ──
  static int _toMins(String t) {
    final m = RegExp(
      r'(\d+):(\d+)\s*(AM|PM)',
      caseSensitive: false,
    ).firstMatch(t);
    if (m == null) return -1;
    var h = int.parse(m[1]!);
    final mn = int.parse(m[2]!);
    final ap = m[3]!.toUpperCase();
    if (ap == 'PM' && h != 12) h += 12;
    if (ap == 'AM' && h == 12) h = 0;
    return h * 60 + mn;
  }

  static int _nowMins() {
    final n = DateTime.now();
    return n.hour * 60 + n.minute;
  }

  static String? _countdown(String t) {
    final diff = _toMins(t) - _nowMins();
    if (diff <= 0) return null;
    if (diff < 60) return '$diff min';
    final h = diff ~/ 60, m = diff % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  String _detectDayGroup(Iterable<String> groups) {
    final list = groups.toList();
    if (list.isEmpty) return '';
    final wd = DateTime.now().weekday; // Mon=1..Sun=7
    final isFri = wd == 5, isSat = wd == 6;
    for (final g in list) {
      final gl = g.toLowerCase();
      if (isFri && gl.contains('fri')) return g;
      if (isSat && gl == 'saturday') return g;
      if (!isFri &&
          !isSat &&
          (gl.contains('sun') ||
              gl.contains('mon') ||
              gl.contains('sat–thu') ||
              gl.contains('sat-thu'))) {
        return g;
      }
    }
    return list.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Bus Schedule'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/info'),
        ),
      ),
      body: FutureBuilder<Map<String, _Schedule>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          final data = snap.data;
          if (data == null || data.isEmpty) {
            return _msg('No bus schedule found.');
          }
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.card,
            onRefresh: () async => setState(() => _future = _load()),
            child: _content(data),
          );
        },
      ),
    );
  }

  Widget _content(Map<String, _Schedule> data) {
    final hasReg = data.containsKey('Regular');
    final examKeys = data.keys.where((k) => k.startsWith('Exam:')).toList();
    final hasExam = examKeys.isNotEmpty;
    if (!hasReg && !hasExam) return _msg('No schedule data available.');
    if (_examDay && hasExam) {
      _tab = 'exam';
    }
    if (hasReg && _tab == 'regular' || (!hasReg && !hasExam)) {
      // ok
    } else if (!hasReg && _tab == 'regular') {
      _tab = 'exam';
    }

    final reg = data['Regular'];
    _regDayGrp ??= reg != null ? _detectDayGroup(reg.days.keys) : null;
    final examFirst = hasExam ? data[examKeys.first]! : null;
    _examDayGrp ??= examFirst != null
        ? _detectDayGroup(examFirst.days.keys)
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        // tab bar
        if (hasReg && hasExam)
          Container(
            padding: const EdgeInsets.all(4),
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _tabBtn(
                  'regular',
                  'Regular',
                  Icons.directions_bus_rounded,
                  _green,
                ),
                _tabBtn('exam', 'Exam Days', Icons.event_note_rounded, _red),
              ],
            ),
          ),
        if (_tab == 'regular' && reg != null)
          ..._regular(reg)
        else if (hasExam)
          ..._exam(data, examKeys),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 12,
              color: AppColors.muted,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'Schedule may change · Always check the notice board',
                style: TextStyle(
                  color: AppColors.muted.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tabBtn(String id, String label, IconData icon, Color color) {
    final active = _tab == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            gradient: active
                ? LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.85),
                      color.withValues(alpha: 0.45),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Regular tab ──
  List<Widget> _regular(_Schedule reg) {
    final dayGrp =
        _regDayGrp ?? (reg.days.keys.isNotEmpty ? reg.days.keys.first : '');
    final day = reg.days[dayGrp];
    return [
      _nextBus(day),
      const SizedBox(height: 18),
      _dayChips(
        reg.days.keys.toList(),
        dayGrp,
        (g) => setState(() => _regDayGrp = g),
      ),
      const SizedBox(height: 14),
      _dirPanel(day),
    ];
  }

  Widget _nextBus(_DayData? day) {
    final now = _nowMins();
    _Trip? next(List<_Trip> list) {
      final up = list.where((t) => _toMins(t.time) >= now).toList()
        ..sort((a, b) => _toMins(a.time).compareTo(_toMins(b.time)));
      return up.isEmpty ? null : up.first;
    }

    final toLU = day == null ? null : next(day.toLU);
    final fromLU = day == null ? null : next(day.fromLU);
    final cards = <Widget>[];
    if (toLU != null) {
      cards.add(_nextCard('Next → To LU', toLU, _green, Icons.login_rounded));
    }
    if (fromLU != null) {
      cards.add(
        _nextCard('Next ← From LU', fromLU, _blue, Icons.logout_rounded),
      );
    }

    if (cards.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.nightlight_round, color: AppColors.muted, size: 18),
            SizedBox(width: 10),
            Text(
              'No more buses today',
              style: TextStyle(color: AppColors.muted, fontSize: 13.5),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  Widget _nextCard(String label, _Trip trip, Color color, IconData icon) {
    final cd = _countdown(trip.time);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            trip.time,
            style: const TextStyle(
              color: AppColors.textBright,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
              height: 1,
            ),
          ),
          if (cd != null) ...[
            const SizedBox(height: 5),
            Text(
              'in $cd',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (trip.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                trip.note,
                style: const TextStyle(
                  color: Color(0xFFFBBF24),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dayChips(
    List<String> groups,
    String active,
    ValueChanged<String> onPick,
  ) {
    if (groups.length <= 1) return const SizedBox.shrink();
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 5, right: 2),
          child: Icon(
            Icons.calendar_today_rounded,
            size: 13,
            color: AppColors.muted,
          ),
        ),
        for (final g in groups)
          GestureDetector(
            onTap: () => onPick(g),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: g == active
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: g == active
                      ? AppColors.accent.withValues(alpha: 0.4)
                      : AppColors.border,
                ),
              ),
              child: Text(
                g,
                style: TextStyle(
                  color: g == active
                      ? AppColors.accentBright
                      : AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dirPanel(_DayData? day) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _dirCol('To LU', Icons.login_rounded, _green, day?.toLU ?? []),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _dirCol(
            'From LU',
            Icons.logout_rounded,
            _blue,
            day?.fromLU ?? [],
          ),
        ),
      ],
    );
  }

  Widget _dirCol(String title, IconData icon, Color color, List<_Trip> trips) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 15,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 5),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _timeline(trips, color),
        ],
      ),
    );
  }

  Widget _timeline(List<_Trip> trips, Color color) {
    if (trips.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No buses scheduled',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      );
    }
    final now = _nowMins();
    _Trip? next;
    for (final t in trips) {
      if (_toMins(t.time) >= now) {
        next = t;
        break;
      }
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: trips.map((t) {
        final mins = _toMins(t.time);
        final isPast = mins != -1 && mins < now;
        final isNext = next != null && t.time == next.time;
        final (bg, fg, border) = isPast
            ? (_red.withValues(alpha: 0.12), _red, _red.withValues(alpha: 0.3))
            : isNext
            ? (color, Colors.white, color)
            : (
                color.withValues(alpha: 0.12),
                color,
                color.withValues(alpha: 0.3),
              );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border),
                boxShadow: isNext
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.time,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (isNext) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.directions_bus_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
                  ],
                ],
              ),
            ),
            if (t.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  t.note,
                  style: const TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        );
      }).toList(),
    );
  }

  // ── Exam tab ──
  List<Widget> _exam(Map<String, _Schedule> data, List<String> examKeys) {
    final examDayGroups = data[examKeys.first]!.days.keys.toList();
    final dayGrp =
        _examDayGrp ?? (examDayGroups.isNotEmpty ? examDayGroups.first : '');
    final combinedDay = _combinedExamDayData(data, examKeys, dayGrp);
    return [
      if (_examDay) ...[_nextBus(combinedDay), const SizedBox(height: 18)],
      _dayChips(examDayGroups, dayGrp, (g) => setState(() => _examDayGrp = g)),
      const SizedBox(height: 14),
      for (final key in examKeys) ...[
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: _red.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _red.withValues(alpha: 0.22)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.08),
                  border: Border(
                    bottom: BorderSide(color: _red.withValues(alpha: 0.15)),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 14, color: _red),
                    const SizedBox(width: 7),
                    Text(
                      '${key.replaceFirst('Exam: ', '')} Exam',
                      style: const TextStyle(
                        color: _red,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: _dirPanel(data[key]!.days[dayGrp]),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  _DayData _combinedExamDayData(
    Map<String, _Schedule> data,
    List<String> examKeys,
    String dayGrp,
  ) {
    final out = _DayData();
    for (final key in examKeys) {
      final day = data[key]?.days[dayGrp];
      if (day == null) continue;
      out.toLU.addAll(day.toLU);
      out.fromLU.addAll(day.fromLU);
    }
    out.toLU.sort((a, b) => _toMins(a.time).compareTo(_toMins(b.time)));
    out.fromLU.sort((a, b) => _toMins(a.time).compareTo(_toMins(b.time)));
    return out;
  }

  Widget _msg(String m) => ListView(
    children: [
      const SizedBox(height: 120),
      Center(
        child: Text(
          m,
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
      ),
    ],
  );
}

class _Schedule {
  final Map<String, _DayData> days = <String, _DayData>{};
}

class _DayData {
  final List<_Trip> toLU = [];
  final List<_Trip> fromLU = [];
}

class _Trip {
  final String time, note;
  _Trip(this.time, this.note);
}
