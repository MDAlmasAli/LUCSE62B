import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import 'sheet_scaffold.dart';

/// Semester info — academic-calendar timeline grouped by semester, each event
/// carrying a live status (Upcoming / Active Now / Completed). Mirrors the
/// website's semester.js.
class SemesterScreen extends StatelessWidget {
  const SemesterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'Semester Info',
      icon: Icons.school_rounded,
      load: () => SheetsApi.instance.sheet('Semester'),
      builder: (rows) {
        final groups = _parse(rows);
        if (groups.isEmpty) return const SheetEmpty(message: 'No semester data found.');
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            for (final g in groups) _semesterBlock(g),
            Padding(
              padding: EdgeInsets.only(top: 4, left: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 12, color: AppColors.muted),
                  SizedBox(width: 5),
                  Expanded(
                    child: Text('Dates are subject to change · Ref: Official LU Notice',
                        style: TextStyle(color: AppColors.muted, fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<_Sem> _parse(List<List<String>> rows) {
    if (rows.isEmpty) return [];
    final start =
        (rows[0].isNotEmpty && rows[0][0].toLowerCase().trim() == 'semester') ? 1 : 0;
    final map = <String, List<_Event>>{};
    final order = <String>[];
    for (var i = start; i < rows.length; i++) {
      final r = rows[i];
      String at(int n) => n < r.length ? r[n].trim() : '';
      final sem = at(0), event = at(1);
      if (sem.isEmpty || event.isEmpty) continue;
      map.putIfAbsent(sem, () {
        order.add(sem);
        return [];
      }).add(_Event(event: event, start: at(2), end: at(3)));
    }
    return order.map((s) => _Sem(s, map[s]!)).toList();
  }

  Widget _semesterBlock(_Sem sem) {
    final total = sem.events.length;
    final pastCount = sem.events.where((e) => e.status == _Status.past).length;
    final hasActive = sem.events.any((e) => e.status == _Status.active);
    final progress = total == 0 ? 0.0 : pastCount / total;

    final (semStatus, semColor) = hasActive
        ? ('Ongoing', AppColors.accentBright)
        : pastCount == total
            ? ('Completed', AppColors.greenBright)
            : pastCount == 0
                ? ('Upcoming', AppColors.amberBright)
                : ('In Progress', AppColors.accentBright);

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Semester header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.accent.withValues(alpha: 0.12), AppColors.accent.withValues(alpha: 0.04)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ACADEMIC CALENDAR',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                      const SizedBox(height: 3),
                      Text(sem.name,
                          style: TextStyle(
                              color: AppColors.textBright, fontSize: 17, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: semColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: semColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(semStatus,
                          style: TextStyle(color: semColor, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 110,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              backgroundColor: AppColors.surface,
                              valueColor: AlwaysStoppedAnimation(AppColors.accent),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('$pastCount / $total completed',
                              style: TextStyle(color: AppColors.muted, fontSize: 9.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Timeline
          for (var i = 0; i < sem.events.length; i++)
            _eventRow(sem.events[i], i == sem.events.length - 1),
        ],
      ),
    );
  }

  Widget _eventRow(_Event e, bool isLast) {
    final meta = e.meta;
    final st = e.status;
    final (label, color) = switch (st) {
      _Status.active => ('Active Now', AppColors.accentBright),
      _Status.past => ('Completed', AppColors.greenBright),
      _Status.upcoming => ('Upcoming', AppColors.textSecondary),
    };
    final dateStr = (e.start == e.end || e.end.isEmpty)
        ? e.start
        : '${e.start} – ${e.end}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline spine
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: st == _Status.upcoming
                      ? AppColors.surface
                      : meta.color.withValues(alpha: 0.18),
                  border: Border.all(
                      color: st == _Status.upcoming
                          ? AppColors.border
                          : meta.color.withValues(alpha: st == _Status.active ? 1 : 0.5),
                      width: 2),
                ),
                child: Icon(meta.icon,
                    size: 14,
                    color: st == _Status.upcoming ? AppColors.muted : meta.color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AppColors.border, margin: const EdgeInsets.symmetric(vertical: 3)),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // Event card
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
                decoration: BoxDecoration(
                  color: st == _Status.active
                      ? meta.color.withValues(alpha: 0.05)
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: st == _Status.active
                          ? meta.color.withValues(alpha: 0.4)
                          : AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.event,
                              style: TextStyle(
                                  color: st == _Status.past
                                      ? AppColors.textSecondary
                                      : AppColors.textBright,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  height: 1.3)),
                          if (dateStr.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, size: 11, color: AppColors.muted),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(dateStr,
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.25)),
                      ),
                      child: Text(label,
                          style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Status { upcoming, active, past }

class _EventMeta {
  final IconData icon;
  final Color color;
  const _EventMeta(this.icon, this.color);
}

class _Event {
  final String event, start, end;
  _Event({required this.event, required this.start, required this.end});

  static DateTime? _parse(String s) {
    if (s.trim().isEmpty) return null;
    for (final f in ['d MMM yyyy', 'dd MMM yyyy', 'd MMMM yyyy', 'd/M/yyyy', 'yyyy-M-d', 'd-M-yyyy']) {
      try {
        return DateFormat(f).parseLoose(s.trim());
      } catch (_) {}
    }
    return DateTime.tryParse(s.trim());
  }

  _Status get status {
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final s = _parse(start);
    var e = _parse(end.isEmpty ? start : end);
    if (s == null) return _Status.upcoming;
    final sd = DateTime(s.year, s.month, s.day);
    if (e != null) e = DateTime(e.year, e.month, e.day);
    if (t.isBefore(sd)) return _Status.upcoming;
    if (e != null && t.isAfter(e)) return _Status.past;
    return _Status.active;
  }

  _EventMeta get meta {
    final n = event.toLowerCase();
    if (n.contains('final')) return _EventMeta(Icons.school_rounded, AppColors.redBright);
    if (n.contains('mid') || n.contains('exam')) return _EventMeta(Icons.edit_note_rounded, AppColors.orangeBright);
    if (n.contains('class')) return _EventMeta(Icons.co_present_rounded, AppColors.blueBright);
    if (n.contains('late') || n.contains('fine')) return _EventMeta(Icons.warning_amber_rounded, AppColors.amberBright);
    if (n.contains('registr') || n.contains('advising')) return _EventMeta(Icons.edit_calendar_rounded, AppColors.accentBright);
    if (n.contains('withdraw') || n.contains('refund')) return _EventMeta(Icons.history_rounded, AppColors.greenBright);
    if (n.contains('grade') || n.contains('submission')) return const _EventMeta(Icons.check_circle_rounded, Color(0xFF4ADE80));
    return _EventMeta(Icons.calendar_month_rounded, AppColors.indigoBright);
  }
}

class _Sem {
  final String name;
  final List<_Event> events;
  _Sem(this.name, this.events);
}
