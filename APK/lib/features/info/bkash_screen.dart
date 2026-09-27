import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../shared/app_toast.dart';
import 'sheet_scaffold.dart';

/// bKash payment details — QR card (scan-to-pay) + the fee structure table from
/// the "bKash" sheet. Mirrors the website's bkash.js.
class BkashScreen extends StatelessWidget {
  const BkashScreen({super.key});

  static const _pink = Color(0xFFE879F9);
  static const _number = '01751-998866';
  static const _numberPlain = '01751998866';
  static const _qrUrl =
      'https://api.qrserver.com/v1/create-qr-code/?size=300x300&margin=0&data=https%3A%2F%2Fqr.bka.sh%2F28101405Xfi8xA00';

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'bKash Payment',
      icon: Icons.payments_rounded,
      load: () => SheetsApi.instance.sheet('bKash'),
      builder: (rows) {
        final fees = _parse(rows);
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            _qrCard(context),
            const SizedBox(height: 16),
            if (fees.isNotEmpty) _feeTable(context, fees),
          ],
        );
      },
    );
  }

  Widget _qrCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: const Border(top: BorderSide(color: _pink, width: 3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          const Text('BKASH OFFICIAL ACCOUNT',
              style: TextStyle(
                  color: _pink, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 18)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: _qrUrl,
                width: 160,
                height: 160,
                fit: BoxFit.cover,
                placeholder: (_, _) => const SizedBox(
                    width: 160,
                    height: 160,
                    child: Center(child: CircularProgressIndicator(color: _pink, strokeWidth: 2))),
                errorWidget: (_, _, _) =>
                    const SizedBox(width: 160, height: 160, child: Icon(Icons.qr_code_2_rounded, size: 90, color: Colors.black54)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Clipboard.setData(const ClipboardData(text: _numberPlain));
              AppToast.show(context, 'Number copied');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_number,
                      style: TextStyle(
                          color: AppColors.textBright,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                  const SizedBox(width: 8),
                  Icon(Icons.copy_rounded, size: 15, color: AppColors.muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text('Leading University',
              style: TextStyle(color: AppColors.accentBright, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _pink.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _pink.withValues(alpha: 0.14)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 14, color: _pink),
                    SizedBox(width: 6),
                    Text('Instructions',
                        style: TextStyle(color: _pink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                _step('1', 'Scan the QR code from the bKash app.'),
                _step('2', 'Or select Make Payment.'),
                _step('3', 'Number: $_numberPlain'),
                _step('4', 'Enter your Student ID & Fees Code.'),
                _step('5', 'Enter PIN to confirm.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$n.',
                style: const TextStyle(color: _pink, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
            ),
          ],
        ),
      );

  Widget _feeTable(BuildContext context, List<_Fee> fees) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fee Structure',
                    style: TextStyle(color: AppColors.textBright, fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Leading University fee codes & payment methods',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
              ],
            ),
          ),
          for (var i = 0; i < fees.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.border),
            _feeRow(context, fees[i]),
          ],
        ],
      ),
    );
  }

  Widget _feeRow(BuildContext context, _Fee f) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(f.head,
                    style: TextStyle(
                        color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35)),
              ),
              if (f.code.isNotEmpty) ...[
                const SizedBox(width: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: f.code));
                    AppToast.show(context, 'Fees code copied');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _pink.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(f.code,
                            style: const TextStyle(color: _pink, fontWeight: FontWeight.w800, fontSize: 13)),
                        const SizedBox(width: 5),
                        const Icon(Icons.copy_rounded, size: 12, color: _pink),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (f.method.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(f.method,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.45)),
          ],
        ],
      ),
    );
  }

  List<_Fee> _parse(List<List<String>> rows) {
    if (rows.isEmpty) return [];
    final first = rows[0].map((c) => c.toLowerCase()).toList();
    final hasHeader =
        first.any((h) => h.contains('fees') || h.contains('method') || h.contains('writing'));
    int find(List<String> keys, int fallback) {
      final i = first.indexWhere((h) => keys.any((k) => h.contains(k)));
      return i >= 0 ? i : fallback;
    }

    final hf = hasHeader ? find(['head of fees', 'head'], 0) : 0;
    final fc = hasHeader ? find(['fees code', 'code'], 1) : 1;
    final wt = hasHeader ? find(['writing', 'method'], 2) : 2;
    final start = hasHeader ? 1 : 0;

    final out = <_Fee>[];
    for (var i = start; i < rows.length; i++) {
      final r = rows[i];
      String at(int n) => n < r.length ? r[n].trim() : '';
      if (at(hf).isEmpty) continue;
      out.add(_Fee(head: at(hf), code: at(fc), method: at(wt)));
    }
    return out;
  }
}

class _Fee {
  final String head, code, method;
  _Fee({required this.head, required this.code, required this.method});
}
