import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../data/dob_service.dart';
import '../../data/session.dart';
import '../../shared/gradient_button.dart';

/// One-time DOB verification screen (mirrors auth.js `_showDobGate`). Tries a
/// silent pass first; otherwise asks the student for their date of birth and
/// verifies it against the LU portal.
class DobGateScreen extends StatefulWidget {
  const DobGateScreen({super.key});

  @override
  State<DobGateScreen> createState() => _DobGateScreenState();
}

class _DobGateScreenState extends State<DobGateScreen> {
  final _dob = DobService.instance;

  bool _checking = true; // initial silent check
  bool _busy = false;
  String? _error;

  int? _day, _month, _year;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _silent();
  }

  Future<void> _silent() async {
    final id = Session.instance.student?.id;
    if (id == null) return;
    final ok = await _dob.trySilent(id);
    if (!mounted) return;
    if (ok) {
      context.go('/');
    } else {
      setState(() => _checking = false);
    }
  }

  Future<void> _submit() async {
    if (_day == null || _month == null || _year == null) {
      setState(() => _error = 'Please select your complete date of birth.');
      return;
    }
    final id = Session.instance.student!.id;
    final dob =
        '$_year-${_month!.toString().padLeft(2, '0')}-${_day!.toString().padLeft(2, '0')}';
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _dob.submit(id, dob);
    if (!mounted) return;
    switch (r) {
      case DobResult.ok:
        context.go('/');
      case DobResult.wrong:
        setState(() {
          _busy = false;
          _error = 'Date of Birth is incorrect. Check your certificate and try again.';
        });
      case DobResult.error:
        setState(() {
          _busy = false;
          _error = 'LU portal is temporarily unavailable. Please try again shortly.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: _checking
                ? const _Checking()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                gradient: AppColors.accentGradient,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Center(
                                  child: Text('🎂',
                                      style: TextStyle(fontSize: 30))),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Center(
                            child: Text('One Quick Step',
                                style: TextStyle(
                                    color: AppColors.textBright,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Enter your Date of Birth exactly as written on your certificate. This verifies your identity with the LU portal.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13.5,
                                height: 1.6),
                          ),
                          const SizedBox(height: 22),
                          Row(
                            children: [
                              Expanded(child: _dropdown<int>(
                                hint: 'Day',
                                value: _day,
                                items: List.generate(31, (i) => i + 1),
                                label: (d) => '$d',
                                onChanged: (v) => setState(() => _day = v),
                              )),
                              const SizedBox(width: 9),
                              Expanded(flex: 2, child: _dropdown<int>(
                                hint: 'Month',
                                value: _month,
                                items: List.generate(12, (i) => i + 1),
                                label: (m) => _months[m - 1],
                                onChanged: (v) => setState(() => _month = v),
                              )),
                              const SizedBox(width: 9),
                              Expanded(child: _dropdown<int>(
                                hint: 'Year',
                                value: _year,
                                items: [
                                  for (var y = DateTime.now().year; y >= 1960; y--) y
                                ],
                                label: (y) => '$y',
                                onChanged: (v) => setState(() => _year = v),
                              )),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: AppColors.red, fontSize: 12.5)),
                            ),
                          GradientButton(
                            label: 'Verify & Continue',
                            icon: Icons.login,
                            busy: _busy,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: 14),
                          Center(
                            child: TextButton(
                              onPressed: () async {
                                await Session.instance.signOut();
                                if (context.mounted) context.go('/login');
                              },
                              style: TextButton.styleFrom(
                                  foregroundColor: AppColors.muted),
                              child: const Text('Sign out'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: AppColors.card,
      hint: Text(hint, style: TextStyle(color: AppColors.muted, fontSize: 13)),
      style: TextStyle(color: AppColors.text, fontSize: 14),
      items: items
          .map((e) => DropdownMenuItem<T>(value: e, child: Text(label(e))))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: AppColors.accent),
        SizedBox(height: 18),
        Text('Checking profile…',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      ],
    );
  }
}
