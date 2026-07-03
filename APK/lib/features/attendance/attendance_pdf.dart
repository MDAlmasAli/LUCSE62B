import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the formal attendance report PDF, mirroring the website's jsPDF
/// layout: letterhead → meta block → one ruled, zebra-striped roster table with
/// a coloured Status column → Total/Present/Absent summary boxes → footer with
/// page numbers. Rendered natively with the `pdf` package's Helvetica.
class AttendancePdf {
  static pw.MemoryImage? _logo;

  static final _ink = PdfColor.fromInt(0xFF19213A);
  static final _ink2 = PdfColor.fromInt(0xFF5F6880);
  static final _green = PdfColor.fromInt(0xFF156E3A);
  static final _red = PdfColor.fromInt(0xFFA82E2E);
  static final _line = PdfColor.fromInt(0xFF7882A0);
  static final _zebra = PdfColor.fromInt(0xFFF8F9FB);
  static final _sumBg = PdfColor.fromInt(0xFFFCFDFE);

  /// [students] is the full roster in sheet order, each tagged present/absent.
  static Future<Uint8List> build({
    required String course,
    required String teacher,
    required String batchSection,
    required List<({String name, String id, bool present})> students,
  }) async {
    _logo ??= pw.MemoryImage(
      (await rootBundle.load('assets/icon/lu-logo.png')).buffer.asUint8List(),
    );

    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final dateStr =
        '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
    final h12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final timeStr =
        '$h12:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';

    final presentCount = students.where((s) => s.present).length;
    final total = students.length;
    final absentCount = total - presentCount;

    pw.TextStyle s(double size, {bool bold = false, PdfColor? color}) =>
        pw.TextStyle(
          font: bold ? pw.Font.helveticaBold() : pw.Font.helvetica(),
          fontSize: size,
          color: color ?? _ink,
        );

    // Choose a column count so the whole roster always fits on ONE page,
    // regardless of class size (roster flows into 1, 2 or 3 side-by-side
    // sub-tables). Font shrinks a touch for the densest 3-column layout.
    final cols = total <= 30 ? 1 : (total <= 64 ? 2 : 3);
    final fontSize = cols >= 3 ? 7.0 : 8.2;
    final perCol = (total / cols).ceil();

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 28, 40, 26),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // ── Letterhead ──
            pw.Center(child: pw.Image(_logo!, width: 50)),
            pw.SizedBox(height: 7),
            pw.Center(
              child: pw.Text('LEADING UNIVERSITY', style: s(20, bold: true)),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'Department of Computer Science & Engineering',
                style: s(9.5, color: _ink2),
              ),
            ),
            pw.Center(
              child: pw.Text('Sylhet, Bangladesh', style: s(8.5, color: _ink2)),
            ),
            pw.SizedBox(height: 7),
            pw.Container(height: 0.6, color: _ink),
            pw.SizedBox(height: 1.2),
            pw.Container(height: 0.25, color: _ink),
            pw.SizedBox(height: 8),

            // ── Title with green underline accent ──
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text('ATTENDANCE REPORT', style: s(12.5, bold: true)),
                  pw.SizedBox(height: 1.6),
                  pw.Container(width: 76, height: 0.6, color: _green),
                ],
              ),
            ),
            pw.SizedBox(height: 9),

            // ── Meta block ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: _meta(s, 'Date:', dateStr)),
                pw.Expanded(child: _meta(s, 'Time:', timeStr)),
              ],
            ),
            pw.SizedBox(height: 3),
            _meta(s, 'Batch & Section:', batchSection),
            if (course.isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(text: 'Course: ', style: s(9, bold: true)),
                    pw.TextSpan(
                      text: course,
                      style: s(9, color: _green),
                    ),
                  ],
                ),
              ),
            ],
            if (teacher.isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(text: 'Teacher: ', style: s(9, bold: true)),
                    pw.TextSpan(
                      text: teacher,
                      style: s(9, color: _green),
                    ),
                  ],
                ),
              ),
            ],
            pw.SizedBox(height: 10),

            // ── Roster: 1–3 side-by-side columns so it stays single-page ──
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < cols; c++) ...[
                  if (c > 0) pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: _table(
                      s,
                      students.sublist(
                        c * perCol,
                        ((c + 1) * perCol).clamp(0, total),
                      ),
                      c * perCol,
                      fontSize,
                    ),
                  ),
                ],
              ],
            ),
            pw.SizedBox(height: 10),

            // ── Summary boxes ──
            pw.Row(
              children: [
                pw.Expanded(child: _summary(s, 'TOTAL STUDENTS', total, _ink)),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: _summary(s, 'PRESENT', presentCount, _green),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(child: _summary(s, 'ABSENT', absentCount, _red)),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: _line, thickness: 0.25, height: 4),
            pw.Text(
              'Generated via CSE 62B Portal  ·  lucse62b.xyz',
              style: s(7, color: _ink2),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static pw.Widget _meta(
    pw.TextStyle Function(double, {bool bold, PdfColor? color}) s,
    String label,
    String value,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: s(9, bold: true)),
        pw.SizedBox(width: 3),
        pw.Expanded(
          child: pw.Text(value, style: s(9, color: _ink2)),
        ),
      ],
    );
  }

  static pw.Widget _table(
    pw.TextStyle Function(double, {bool bold, PdfColor? color}) s,
    List<({String name, String id, bool present})> rows,
    int startIndex,
    double font,
  ) {
    final compact = font < 8; // 3-column dense layout
    pw.Widget cell(
      String t, {
      bool bold = false,
      pw.TextAlign align = pw.TextAlign.left,
      PdfColor? color,
      double? size,
    }) => pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        horizontal: compact ? 3 : 5,
        vertical: 2.8,
      ),
      child: pw.Text(
        t,
        style: s(size ?? font, bold: bold, color: color),
        textAlign: align,
        maxLines: 1,
      ),
    );

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.4),
      columnWidths: compact
          ? const {
              0: pw.FixedColumnWidth(15),
              1: pw.FlexColumnWidth(),
              2: pw.FixedColumnWidth(22),
            }
          : const {
              0: pw.FixedColumnWidth(22),
              1: pw.FlexColumnWidth(),
              2: pw.FixedColumnWidth(86),
              3: pw.FixedColumnWidth(46),
            },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _ink),
          children: [
            cell(
              '#',
              bold: true,
              align: pw.TextAlign.center,
              color: PdfColors.white,
              size: font - 0.5,
            ),
            cell('Name', bold: true, color: PdfColors.white, size: font - 0.5),
            if (!compact)
              cell(
                'Student ID',
                bold: true,
                align: pw.TextAlign.center,
                color: PdfColors.white,
                size: font - 0.5,
              ),
            cell(
              compact ? 'St.' : 'Status',
              bold: true,
              align: pw.TextAlign.center,
              color: PdfColors.white,
              size: font - 0.5,
            ),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: (startIndex + i).isOdd
                ? pw.BoxDecoration(color: _zebra)
                : null,
            children: [
              cell(
                '${startIndex + i + 1}',
                align: pw.TextAlign.center,
                color: _ink2,
                size: font - 0.7,
              ),
              cell(rows[i].name),
              if (!compact)
                cell(
                  rows[i].id,
                  align: pw.TextAlign.center,
                  color: _ink2,
                  size: font - 0.4,
                ),
              cell(
                compact
                    ? (rows[i].present ? 'P' : 'A')
                    : (rows[i].present ? 'Present' : 'Absent'),
                bold: true,
                align: pw.TextAlign.center,
                color: rows[i].present ? _green : _red,
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _summary(
    pw.TextStyle Function(double, {bool bold, PdfColor? color}) s,
    String label,
    int value,
    PdfColor accent,
  ) {
    return pw.Container(
      height: 30,
      decoration: pw.BoxDecoration(
        color: _sumBg,
        border: pw.Border.all(color: accent, width: 0.4),
        borderRadius: pw.BorderRadius.circular(2),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 2.2,
            height: 28,
            color: accent,
            margin: const pw.EdgeInsets.symmetric(vertical: 1),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('$value', style: s(16, bold: true, color: accent)),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(right: 6, top: 5),
            child: pw.Text(label, style: s(7, bold: true, color: _ink2)),
          ),
        ],
      ),
    );
  }
}
