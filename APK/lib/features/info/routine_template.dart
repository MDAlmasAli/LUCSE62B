import 'package:flutter/material.dart';

/// Pixel-faithful recreation of the website's printable routine template
/// (info.html `buildPrintTemplate`, dark theme) so the app's downloaded
/// PDF/image looks exactly like the site's. Rendered at a fixed 1280px width
/// and captured off-screen to a PNG.

// ── Dark print theme (matches getPrintTheme) ──
const _bg = Color(0xFF0D0D1B);
const _text = Color(0xFFE2E8F0);
const _textMuted = Color(0xFF94A3B8);
final _borderSub = Colors.white.withValues(alpha: 0.06);
final _headerBg = const Color(0xFF7C3AED).withValues(alpha: 0.14);
const _headerText = Color(0xFFA78BFA);
final _rowEven = Colors.white.withValues(alpha: 0.015);
const _rowOdd = Colors.transparent;
final _dayCell = const Color(0xFF0F0F1A).withValues(alpha: 0.8);
const _dayCellText = Color(0xFFC4B5FD);
const _line2Color = Color(0xFFCBD5E1);
const _roomColor = Color(0xFF64748B);
const _freeColor = Color(0xFF1F2937);
const _footer = Color(0xFF374151);
const _univText = Color(0xFF94A3B8);
const _univFaint = Color(0xFF4B5563);
const _breakColor = Color(0xFFFBBF24);
final _divider = const Color(0xFF7C3AED).withValues(alpha: 0.4);
final _timeHeadBg = const Color(0xFF7C3AED).withValues(alpha: 0.03);
final _timeBreakBg = const Color(0xFFFBBF24).withValues(alpha: 0.09);
final _breakCellBg = const Color(0xFFFBBF24).withValues(alpha: 0.07);

const _printColors = [
  Color(0xFFA78BFA),
  Color(0xFF38BDF8),
  Color(0xFF34D399),
  Color(0xFFFB923C),
  Color(0xFFF472B6),
  Color(0xFF818CF8),
  Color(0xFF4ADE80),
  Color(0xFFF87171),
  Color(0xFFFBBF24),
  Color(0xFF22D3EE),
];

/// Same hash + palette as the website's courseColor (32-bit wrap to match JS).
Color printCourseColor(String code) {
  if (code.isEmpty) return const Color(0xFF6B7280);
  var h = 0;
  for (final c in code.codeUnits) {
    h = (((h << 5) - h) + c).toSigned(32);
  }
  return _printColors[h.abs() % _printColors.length];
}

class PrintCell {
  final String title2; // course name, or code if no name
  final String code; // shown under the name (only when a name exists)
  final String
  line2; // teacher (class routine) / batch-section (teacher routine)
  final String room;
  final Color color;
  const PrintCell({
    required this.title2,
    required this.code,
    required this.line2,
    required this.room,
    required this.color,
  });
}

class PrintRow {
  final String dayLabel;
  final bool even;
  final Map<String, List<PrintCell>> courses; // time → cells
  final Set<String> breaks; // times where this day has a break
  const PrintRow({
    required this.dayLabel,
    required this.even,
    required this.courses,
    required this.breaks,
  });
}

class PrintGroup {
  final List<String> times;
  final Set<String> breakTimes;
  final List<PrintRow> rows;
  const PrintGroup({
    required this.times,
    required this.breakTimes,
    required this.rows,
  });
}

class RoutinePrintTemplate extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<PrintGroup> groups;
  const RoutinePrintTemplate({
    super.key,
    required this.title,
    required this.subtitle,
    required this.groups,
  });

  static const double _totalW = 1280;
  static const double _padding = 36;
  static const double _dayW = 130;

  @override
  Widget build(BuildContext context) {
    final dateStr = _dateStr();
    return Container(
      width: _totalW,
      color: _bg,
      padding: const EdgeInsets.all(_padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.only(bottom: 20),
            margin: const EdgeInsets.only(bottom: 26),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _divider, width: 1.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFA78BFA),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Leading University, Sylhet',
                      style: TextStyle(
                        color: _univText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Department of Computer Science & Engineering',
                      style: TextStyle(color: _univFaint, fontSize: 11.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          for (var gi = 0; gi < groups.length; gi++) ...[
            if (gi > 0) const SizedBox(height: 14),
            _groupTable(groups[gi]),
          ],
          // Footer
          Container(
            margin: const EdgeInsets.only(top: 18),
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _borderSub)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CSE 62B Portal  ·  lucse62b.xyz',
                  style: TextStyle(
                    color: _footer,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Generated: $dateStr',
                  style: const TextStyle(color: _footer, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupTable(PrintGroup g) {
    if (g.times.isEmpty) return const SizedBox.shrink();
    final colW = (_totalW - _padding * 2 - _dayW) / g.times.length;
    return Table(
      border: TableBorder.all(color: _borderSub, width: 1),
      columnWidths: {
        0: const FixedColumnWidth(_dayW),
        for (var i = 0; i < g.times.length; i++) i + 1: FixedColumnWidth(colW),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        // Header row
        TableRow(
          children: [
            Container(
              color: _headerBg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: const Text(
                'DAY / TIME',
                style: TextStyle(
                  color: _headerText,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            for (final time in g.times)
              Container(
                color: g.breakTimes.contains(time) ? _timeBreakBg : _timeHeadBg,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                alignment: Alignment.center,
                child: Text(
                  time,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: g.breakTimes.contains(time)
                        ? _breakColor
                        : _textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        // Body rows
        for (final row in g.rows)
          TableRow(
            children: [
              Container(
                color: _dayCell,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Text(
                  row.dayLabel,
                  style: const TextStyle(
                    color: _dayCellText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final time in g.times)
                _bodyCell(row, time, g.breakTimes.contains(time)),
            ],
          ),
      ],
    );
  }

  Widget _bodyCell(PrintRow row, String time, bool isBreakCol) {
    final rowBg = row.even ? _rowEven : _rowOdd;
    if (isBreakCol) {
      final hasBreak = row.breaks.contains(time);
      return Container(
        color: _breakCellBg,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        alignment: Alignment.center,
        child: Text(
          hasBreak ? '☕ BREAK' : '',
          style: const TextStyle(
            color: _breakColor,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    final cells = row.courses[time] ?? const [];
    if (cells.isEmpty) {
      return Container(
        color: rowBg,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        alignment: Alignment.center,
        child: const Text(
          '—',
          style: TextStyle(color: _freeColor, fontSize: 14),
        ),
      );
    }
    return Container(
      color: rowBg,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: cells.map(_courseBox).toList(),
      ),
    );
  }

  Widget _courseBox(PrintCell c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
      decoration: BoxDecoration(
        color: c.color.withValues(alpha: 0.10),
        border: Border.all(color: c.color.withValues(alpha: 0.33), width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            c.title2,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          if (c.code.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                c.code,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.color.withValues(alpha: 0.6),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          if (c.line2.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                c.line2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _line2Color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (c.room.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                c.room,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _roomColor, fontSize: 9.5),
              ),
            ),
        ],
      ),
    );
  }

  static String _dateStr() {
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final n = DateTime.now();
    return '${n.day.toString().padLeft(2, '0')} ${mo[n.month - 1]} ${n.year}';
  }
}

/// Branded printable table for routines that are not weekly class grids
/// (currently Exam Routine). It keeps the same LU header, dark theme and footer
/// as [RoutinePrintTemplate], while allowing arbitrary columns.
class InfoTablePrintTemplate extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> headers;
  final List<List<String>> rows;
  final List<double>? columnFlex;
  final int? accentColumn;

  const InfoTablePrintTemplate({
    super.key,
    required this.title,
    required this.subtitle,
    required this.headers,
    required this.rows,
    this.columnFlex,
    this.accentColumn,
  });

  static const double _width = 1280;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _width,
      color: _bg,
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _printHeader(),
          Table(
            border: TableBorder.all(color: _borderSub, width: 1),
            columnWidths: {
              for (var i = 0; i < headers.length; i++)
                i: FlexColumnWidth(
                  columnFlex != null && i < columnFlex!.length
                      ? columnFlex![i]
                      : 1,
                ),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  for (final header in headers)
                    Container(
                      color: _headerBg,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      child: Text(
                        header,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _headerText,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
              for (var ri = 0; ri < rows.length; ri++)
                TableRow(
                  children: [
                    for (var ci = 0; ci < headers.length; ci++)
                      _tableCell(
                        ci < rows[ri].length ? rows[ri][ci] : '',
                        ci,
                        ri,
                      ),
                  ],
                ),
            ],
          ),
          _printFooter(),
        ],
      ),
    );
  }

  Widget _printHeader() => Container(
    padding: const EdgeInsets.only(bottom: 20),
    margin: const EdgeInsets.only(bottom: 26),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: _divider, width: 1.5)),
    ),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.event_note_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: _headerText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const Spacer(),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Leading University, Sylhet',
              style: TextStyle(
                color: _univText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Department of Computer Science & Engineering',
              style: TextStyle(color: _univFaint, fontSize: 11.5),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _tableCell(String text, int column, int row) {
    final accent = accentColumn == column && text.isNotEmpty;
    final color = accent ? printCourseColor(text) : _line2Color;
    return Container(
      color: row.isEven ? _rowEven : _rowOdd,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
      child: Text(
        text.isEmpty ? '—' : text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: accent ? 11 : 10.5,
          fontWeight: accent ? FontWeight.w800 : FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _printFooter() => Container(
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.only(top: 14),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: _borderSub)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'CSE 62B Portal  ·  lucse62b.xyz',
          style: TextStyle(
            color: _footer,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          'Generated: ${RoutinePrintTemplate._dateStr()}',
          style: const TextStyle(color: _footer, fontSize: 10.5),
        ),
      ],
    ),
  );
}
