import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'cover_data.dart';

/// Builds the cover-page PDF natively with the `pdf` package's widget tree and
/// the built-in Times font. This renders instantly (no headless WebView like
/// the old convertHtml path) while matching the website's two templates.
///
/// The site's live preview is a 794×1123px A4 box (96 dpi). PDF points are
/// 72 dpi, so every px maps to px × 0.75 pt:
///   • 96px page padding → 72pt margin
///   • 26pt/16pt/14pt headings (= 35/21/19px) stay as-is in points
///   • 140px logo → 105pt · 70px content indent → 52.5pt
class CoverPdf {
  static pw.MemoryImage? _logo;
  static pw.Font? _reg;
  static pw.Font? _bold;

  static const double _fUniv = 26;
  static const double _fDept = 16;
  static const double _fBody = 14;
  static const double _indent = 52.5; // 70px content left margin (t1)
  static const double _rowH = 26; // group-table row height (for merged cells)
  static const double _contentW = 595.28 - 144; // A4 width minus 72pt margins
  static const double _idColW = 132; // fits a 16-digit ID at 14pt + padding
  static const double _bsColW = 64; // Batch / Section columns

  static final _grid = PdfColor.fromInt(0xFF444444);
  static final _headBg = PdfColor.fromInt(0xFFF0F0F0);

  static Future<Uint8List> build(CoverData d) async {
    _logo ??= pw.MemoryImage(
        (await rootBundle.load('assets/icon/lu-logo.png')).buffer.asUint8List());
    _reg ??= pw.Font.times();
    _bold ??= pw.Font.timesBold();

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(72),
      build: (ctx) => d.template == 't2' ? _t2(d) : _t1(d),
    ));
    return doc.save();
  }

  static pw.TextStyle _s(double size, {bool bold = false}) => pw.TextStyle(
        font: bold ? _bold : _reg,
        fontSize: size,
        color: PdfColors.black,
      );

  // ── Template 1 (modern, table-based, cp2-*) ──
  static pw.Widget _t1(CoverData d) {
    final isLab = d.docType == 'Lab Report';
    final heading = isLab ? 'Lab Report On' : 'Assignment On';
    final noLabel = isLab ? 'Lab Report No' : 'Assignment No';

    final body = <pw.Widget>[
      pw.SizedBox(height: 10),
      pw.Text(heading, style: _s(_fBody, bold: true)),
      pw.SizedBox(height: 5),
    ];
    if (d.courseTitle.isNotEmpty) body.add(_courseLine('Course Title', d.courseTitle));
    if (d.courseCode.isNotEmpty) body.add(_courseLine('Course Code', d.courseCode));
    body.add(pw.SizedBox(height: 14));

    final noTopic = <List<String>>[];
    if (d.no.isNotEmpty) noTopic.add([noLabel, d.no]);
    if (d.topic.isNotEmpty) noTopic.add(['Assignment Topic', d.topic]);
    if (noTopic.isNotEmpty) {
      body.add(_kv(noTopic));
      body.add(pw.SizedBox(height: 14));
    }

    body.add(pw.Text('Submitted To', style: _s(_fBody, bold: true)));
    body.add(pw.SizedBox(height: 3));
    final toRows = <List<String>>[];
    if (d.teacherName.isNotEmpty) toRows.add(['Name', d.teacherName]);
    if (d.designation.isNotEmpty) toRows.add(['Designation', d.designation]);
    if (d.department.isNotEmpty) toRows.add(['Department', d.department]);
    if (toRows.isNotEmpty) body.add(_kv(toRows));
    body.add(pw.SizedBox(height: 14));

    body.add(pw.Text('Submitted From', style: _s(_fBody, bold: true)));
    body.add(pw.SizedBox(height: 4));
    if (d.isGroup) {
      body.add(_groupTable(d, _contentW - _indent));
    } else {
      final fromRows = <List<String>>[];
      if (d.studentName.isNotEmpty) fromRows.add(['Name', d.studentName]);
      if (d.studentId.isNotEmpty) fromRows.add(['ID', d.studentId]);
      if (d.batch.isNotEmpty) fromRows.add(['Batch', d.batch]);
      if (d.section.isNotEmpty) fromRows.add(['Section', d.section]);
      if (fromRows.isNotEmpty) body.add(_kv(fromRows));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(child: pw.Text('LEADING UNIVERSITY', style: _s(_fUniv, bold: true))),
        pw.SizedBox(height: 5),
        pw.Center(
          child: pw.Text('Department of Computer Science & Engineering',
              style: _s(_fDept, bold: true), textAlign: pw.TextAlign.center),
        ),
        pw.SizedBox(height: 12),
        pw.Center(child: pw.Image(_logo!, width: 105)),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(left: _indent),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: body),
          ),
        ),
        pw.Center(
          child: pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(text: 'Date of Submission : ', style: _s(_fBody, bold: true)),
              pw.TextSpan(text: d.date, style: _s(_fBody)),
            ]),
          ),
        ),
      ],
    );
  }

  // ── Template 2 (classic, centred, cp-*) ──
  static pw.Widget _t2(CoverData d) {
    final isLab = d.docType == 'Lab Report';
    final heading = isLab ? 'Lab Report On' : 'Assignment on';
    final noLabel = isLab ? 'Lab Report No' : 'Assignment No';

    final w = <pw.Widget>[
      pw.Text('LEADING UNIVERSITY', style: _s(_fUniv, bold: true)),
      pw.SizedBox(height: 5),
      pw.Text('Department of Computer Science & Engineering',
          style: _s(_fDept, bold: true), textAlign: pw.TextAlign.center),
      pw.SizedBox(height: 12),
      pw.Image(_logo!, width: 105),
      pw.SizedBox(height: 28),
      pw.Text(heading, style: _s(_fBody, bold: true)),
    ];

    void line(String s) => w.add(pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Text(s, style: _s(_fBody), textAlign: pw.TextAlign.center),
        ));

    if (d.courseTitle.isNotEmpty) line('Course Title: ${d.courseTitle}');
    if (d.courseCode.isNotEmpty) line('Course Code: ${d.courseCode}');
    if (d.no.isNotEmpty) line('$noLabel: ${d.no}');
    if (d.topic.isNotEmpty) line('Topic: ${d.topic}');

    w.add(pw.SizedBox(height: 21));
    w.add(pw.Text('Submitted To', style: _s(_fBody, bold: true)));
    if (d.teacherName.isNotEmpty) line(d.teacherName);
    if (d.designation.isNotEmpty) line(d.designation);
    if (d.department.isNotEmpty) line(d.department);

    w.add(pw.SizedBox(height: 21));
    w.add(pw.Text('Submitted From', style: _s(_fBody, bold: true)));
    if (d.isGroup) {
      w.add(pw.SizedBox(height: 4));
      w.add(_groupTable(d, _contentW));
    } else {
      if (d.studentName.isNotEmpty) line(d.studentName);
      if (d.studentId.isNotEmpty) line(d.studentId);
      final bs = [d.batch, d.section.isEmpty ? '' : '(${d.section})']
          .where((x) => x.isNotEmpty)
          .join(' ');
      if (bs.isNotEmpty) line(bs);
    }

    w.add(pw.SizedBox(height: 21));
    w.add(pw.Text('Date of Submission', style: _s(_fBody, bold: true)));
    if (d.date.isNotEmpty) line(d.date);

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: w);
  }

  /// Bold "Label : value" line (t1 course rows).
  static pw.Widget _courseLine(String label, String val) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(text: label, style: _s(_fBody, bold: true)),
            pw.TextSpan(text: ' : $val', style: _s(_fBody)),
          ]),
        ),
      );

  /// Bold-label · colon · value info table (t1 cp2-info-tbl).
  static pw.Widget _kv(List<List<String>> pairs) => pw.Table(
        columnWidths: const {
          0: pw.FixedColumnWidth(123.75),
          1: pw.FixedColumnWidth(20),
          2: pw.FlexColumnWidth(),
        },
        children: [
          for (final p in pairs)
            pw.TableRow(children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text(p[0], style: _s(_fBody, bold: true)),
              ),
              pw.Text(':', style: _s(_fBody)),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text(p[1], style: _s(_fBody)),
              ),
            ]),
        ],
      );

  /// Bordered group table with merged Batch/Section cells (rowspan), built as
  /// a Name+ID table beside a single tall Batch+Section table so the merge is
  /// exact without needing real rowspan support.
  static pw.Widget _groupTable(CoverData d, double width) {
    final rows = d.members.where((m) => m.name.isNotEmpty || m.id.isNotEmpty).toList();
    if (rows.isEmpty) return pw.SizedBox();
    final n = rows.length;
    final nameColW = width - 2 * _bsColW - _idColW;

    // Rows have a fixed height (the merged Batch/Section cells depend on it),
    // so a value that is too wide is shrunk to fit instead of being cut off;
    // a clipped Student ID loses its last digits. With [wrapW] set the text
    // first wraps onto two lines at that width, so a long name shrinks only a
    // little instead of being squeezed onto one line. Names wrap at 115% of
    // the cell width, so a name only slightly too wide stays on one line.
    pw.Widget cell(String s, {bool bold = false, bool header = false, double? wrapW}) {
      final text = pw.Text(s,
          style: _s(_fBody, bold: bold),
          textAlign: pw.TextAlign.center,
          maxLines: wrapW == null ? 1 : 2);
      return pw.Container(
        height: _rowH,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8),
        color: header ? _headBg : null,
        child: pw.FittedBox(
          fit: pw.BoxFit.scaleDown,
          child: wrapW == null
              ? text
              : pw.ConstrainedBox(constraints: pw.BoxConstraints(maxWidth: wrapW), child: text),
        ),
      );
    }

    final nameTbl = pw.Table(
      border: pw.TableBorder.all(color: _grid, width: 1),
      columnWidths: {0: pw.FixedColumnWidth(nameColW), 1: const pw.FixedColumnWidth(_idColW)},
      children: [
        pw.TableRow(children: [
          cell('Name', bold: true, header: true),
          cell('Student ID', bold: true, header: true),
        ]),
        for (final m in rows)
          pw.TableRow(children: [cell(m.name, wrapW: (nameColW - 16) * 1.15), cell(m.id)]),
      ],
    );

    final bsTbl = pw.Table(
      border: pw.TableBorder.all(color: _grid, width: 1),
      columnWidths: const {0: pw.FixedColumnWidth(_bsColW), 1: pw.FixedColumnWidth(_bsColW)},
      children: [
        pw.TableRow(children: [
          cell('Batch', bold: true, header: true),
          cell('Section', bold: true, header: true),
        ]),
        pw.TableRow(children: [
          pw.Container(height: _rowH * n, alignment: pw.Alignment.center, child: pw.Text(d.batch, style: _s(_fBody))),
          pw.Container(height: _rowH * n, alignment: pw.Alignment.center, child: pw.Text(d.section, style: _s(_fBody))),
        ]),
      ],
    );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [pw.Expanded(child: nameTbl), bsTbl],
    );
  }
}
