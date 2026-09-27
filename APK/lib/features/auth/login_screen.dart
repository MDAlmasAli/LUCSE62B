import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../data/auth_repository.dart';
import '../../data/models/student.dart';
import '../../shared/avatar_badge.dart';
import '../../shared/gradient_button.dart';

enum _Step { id, password, otp, verify, setup, forgot, reset }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthRepository.instance;

  _Step _step = _Step.id;
  Student? _student;
  String _pst = '';
  bool _keep = true;
  bool _busy = false;
  String? _error;

  final _idCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  final _forgotIdCtrl = TextEditingController();
  final _resetOtpCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in [
      _idCtrl, _pwdCtrl, _otpCtrl, _newPwdCtrl,
      _confirmPwdCtrl, _forgotIdCtrl, _resetOtpCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(_Step s) => setState(() {
        _error = null;
        _step = s;
      });

  void _fail(String msg) => setState(() {
        _error = msg;
        _busy = false;
      });

  // ── Step 1: student id ──
  Future<void> _checkId() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await _auth.checkStudentId(_idCtrl.text);
    if (!mounted) return;
    switch (res.stage) {
      case LoginStage.password:
        _student = res.student;
        setState(() {
          _busy = false;
          _step = _Step.password;
        });
      case LoginStage.otp:
        _student = res.student;
        setState(() {
          _busy = false;
          _step = _Step.otp;
        });
      case LoginStage.notFound:
        _fail('🚫 Student ID not found. This portal is only for CSE Batch 62, Section B.');
      case LoginStage.rateLimited:
        _fail('⏳ Too many attempts. Please wait a few minutes.');
      case LoginStage.error:
        _fail('Connection error. Please try again.');
    }
  }

  // ── Step 2a: password ──
  Future<void> _loginPassword() async {
    if (_pwdCtrl.text.isEmpty) return _fail('Please enter your password.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await _auth.loginWithPassword(_student!, _pwdCtrl.text, keep: _keep);
      if (!mounted) return;
      if (ok) {
        context.go('/');
      } else {
        _fail('Incorrect password. Try again or reset it.');
      }
    } catch (_) {
      _fail('Login error. Please try again.');
    }
  }

  // ── Step 2b: OTP send ──
  Future<void> _sendOtp(String id, {required _Step next}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _auth.sendOtp(id);
      if (!mounted) return;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'failed');
      setState(() {
        _busy = false;
        _step = next;
      });
    } catch (e) {
      _fail(e.toString().contains('phone')
          ? 'No phone registered for this student. Contact admin.'
          : 'Failed to send OTP. Please try again.');
    }
  }

  // ── Step 3: verify OTP (new-account path) ──
  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.trim().isEmpty) return _fail('Please enter the OTP.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await _auth.verifyOtp(_student!, _otpCtrl.text.trim(), keep: true);
      if (!mounted) return;
      if (res['valid'] != true) return _fail('Invalid OTP. Please try again.');
      if (res['signedIn'] == true) {
        context.go('/');
      } else {
        _pst = (res['pst'] ?? '').toString();
        setState(() {
          _busy = false;
          _step = _Step.setup;
        });
      }
    } catch (_) {
      _fail('Connection error. Please try again.');
    }
  }

  // ── First-time password setup ──
  Future<void> _completeSetup() async {
    final p = _newPwdCtrl.text, c = _confirmPwdCtrl.text;
    if (p.length < 6) return _fail('Password must be at least 6 characters.');
    if (p != c) return _fail('Passwords do not match.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.setPasswordAndSignIn(_student!, _pst, p);
      if (!mounted) return;
      context.go('/');
    } catch (_) {
      _fail('Could not set password. Please try again.');
    }
  }

  // ── Forgot → request reset OTP ──
  Future<void> _requestReset() async {
    final sid = _auth.normalizeId(_forgotIdCtrl.text);
    if (sid.isEmpty) return _fail('Please enter your Student ID.');
    if (sid == 'DEMO') return _fail('Demo password reset is disabled.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await _auth.checkStudentId(sid);
    if (!mounted) return;
    if (res.stage == LoginStage.notFound) return _fail('Student not found.');
    if (res.student == null) return _fail('Connection error. Please try again.');
    _student = res.student;
    await _sendOtp(sid, next: _Step.reset);
  }

  // ── Reset password ──
  Future<void> _resetPassword() async {
    final otp = _resetOtpCtrl.text.trim();
    final p = _newPwdCtrl.text, c = _confirmPwdCtrl.text;
    if (otp.isEmpty || p.isEmpty || c.isEmpty) return _fail('Please fill all fields.');
    if (p.length < 6) return _fail('Password must be at least 6 characters.');
    if (p != c) return _fail('Passwords do not match.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await _auth.verifyOtp(_student!, otp, keep: true);
      if (!mounted) return;
      if (res['valid'] != true || (res['pst'] ?? '').toString().isEmpty) {
        // verifyOtp signs in if a password already exists; for reset we still
        // need the pst, so treat a direct sign-in as success too.
        if (res['signedIn'] == true) {
          context.go('/');
          return;
        }
        return _fail('Invalid OTP.');
      }
      await _auth.setPasswordAndSignIn(_student!, (res['pst']).toString(), p);
      if (!mounted) return;
      context.go('/');
    } catch (_) {
      _fail('Error resetting password. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        // Top-down brand wash behind everything.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF141A33), AppColors.bg],
            stops: [0.0, 0.5],
          ),
        ),
        child: Stack(
          children: [
            // Soft decorative background glows.
            Positioned(top: -140, right: -120, child: _glow(320, AppColors.accent, 0.22)),
            Positioned(bottom: -160, left: -130, child: _glow(330, AppColors.accentCyan, 0.14)),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 34, 22, 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _hero(),
                        const SizedBox(height: 26),
                        // Auth card holding the current step.
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(color: AppColors.borderAccent),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 40,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Accent grip bar at the top of the card.
                              Container(
                                margin: const EdgeInsets.only(top: 12),
                                width: 42,
                                height: 4,
                                decoration: BoxDecoration(
                                  gradient: AppColors.accentGradient,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 280),
                                  transitionBuilder: (child, anim) => FadeTransition(
                                    opacity: anim,
                                    child: SlideTransition(
                                      position: Tween(begin: const Offset(0.06, 0), end: Offset.zero)
                                          .animate(anim),
                                      child: child,
                                    ),
                                  ),
                                  child: _buildStep(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.verified_user_rounded, size: 12, color: AppColors.muted.withValues(alpha: 0.8)),
                            const SizedBox(width: 6),
                            Text('Secure portal · CSE 62B only',
                                style: TextStyle(
                                    color: AppColors.muted.withValues(alpha: 0.8),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Branded hero: the LU logo in a glowing ring + gradient wordmark.
  Widget _hero() => Column(
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.55), width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset('assets/images/hero.jpg', fit: BoxFit.cover),
            ),
          ).animate().fadeIn(duration: 350.ms).scale(begin: const Offset(0.85, 0.85)),
          const SizedBox(height: 18),
          ShaderMask(
            shaderCallback: (r) => AppColors.accentGradient.createShader(r),
            child: const Text('CSE 62B',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5)),
          ),
          const SizedBox(height: 4),
          Text('Class Portal · Leading University',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      );

  /// A soft radial glow used as a background accent on the login screen.
  Widget _glow(double size, Color color, double opacity) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withValues(alpha: opacity), Colors.transparent],
            ),
          ),
        ),
      );

  Widget _buildStep() {
    switch (_step) {
      case _Step.id:
        return _stepId();
      case _Step.password:
        return _stepPassword();
      case _Step.otp:
        return _stepOtp();
      case _Step.verify:
        return _stepOtp(); // unused separate verify; otp handles inline
      case _Step.setup:
        return _stepSetup();
      case _Step.forgot:
        return _stepForgot();
      case _Step.reset:
        return _stepReset();
    }
  }

  // ── Step widgets ──
  Widget _wrap(String key, List<Widget> children) => Column(
        key: ValueKey(key),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ).animate().fadeIn(duration: 250.ms);

  Widget _heading(String title, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: AppColors.accentBright,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(sub,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13.5, height: 1.5)),
          const SizedBox(height: 18),
        ],
      );

  Widget _errorBox() => _error == null
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.09),
            border: Border.all(color: AppColors.red.withValues(alpha: 0.22)),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(_error!,
              style: TextStyle(color: AppColors.red, fontSize: 12.5)),
        );

  Widget _field(TextEditingController c, String label, IconData icon,
      {bool obscure = false, TextInputType? type, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: AppColors.accentBright,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            obscureText: obscure,
            keyboardType: type,
            style: TextStyle(color: AppColors.text),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, size: 16, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcomeBadge(Student s, String sub) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.09),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            AvatarBadge(name: s.name, size: 40),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  Text(sub,
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _linkRow(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: children),
      );

  Widget _link(String text, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            foregroundColor: AppColors.accentBright),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      );

  Widget _stepId() => _wrap('id', [
        _heading('Welcome Back', 'Enter your Student ID to sign in to the portal.'),
        _errorBox(),
        _field(_idCtrl, 'Student ID', Icons.badge_outlined,
            hint: 'e.g. 0182320012101001 or DEMO'),
        GradientButton(
            label: 'Continue',
            icon: Icons.arrow_forward,
            busy: _busy,
            onPressed: _checkId),
      ]);

  Widget _stepPassword() => _wrap('pwd', [
        _welcomeBadge(_student!, _student!.isDemo ? 'Guest demo session' : 'Returning student'),
        _errorBox(),
        _field(_pwdCtrl, 'Password', Icons.lock_outline,
            obscure: true, hint: 'Enter your password'),
        if (!_student!.isDemo)
          Row(children: [
            Checkbox(
              value: _keep,
              onChanged: (v) => setState(() => _keep = v ?? true),
              activeColor: AppColors.accent,
            ),
            Text('Keep me logged in',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ]),
        GradientButton(
            label: 'Sign In',
            icon: Icons.login,
            busy: _busy,
            onPressed: _loginPassword),
        _linkRow([
          _link('Forgot password?', () {
            _forgotIdCtrl.text = _student?.id ?? '';
            _go(_Step.forgot);
          }),
          Text('·', style: TextStyle(color: AppColors.muted)),
          _link('Back', () => _go(_Step.id)),
        ]),
      ]);

  Widget _stepOtp() => _wrap('otp', [
        _welcomeBadge(_student!, 'New account setup'),
        Text(
          "We'll send an OTP to your registered number to verify and set up your account.",
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.6),
        ),
        const SizedBox(height: 18),
        _errorBox(),
        GradientButton(
            label: 'Send OTP',
            icon: Icons.send,
            busy: _busy,
            onPressed: () => _sendOtpThenVerify()),
        _linkRow([_link('Back', () => _go(_Step.id))]),
      ]);

  // After sending OTP for a new account, show the verify field inline.
  bool _otpSent = false;
  Future<void> _sendOtpThenVerify() async {
    if (!_otpSent) {
      await _sendOtp(_student!.id, next: _Step.otp);
      if (mounted && _error == null) setState(() => _otpSent = true);
      return;
    }
    await _verifyOtp();
  }

  Widget _stepSetup() => _wrap('setup', [
        _heading('Create Password', 'Set a password to finish your account setup.'),
        _errorBox(),
        _field(_newPwdCtrl, 'New Password', Icons.lock_outline,
            obscure: true, hint: 'At least 6 characters'),
        _field(_confirmPwdCtrl, 'Confirm Password', Icons.lock_outline,
            obscure: true, hint: 'Re-enter password'),
        GradientButton(
            label: 'Finish & Sign In',
            icon: Icons.check,
            busy: _busy,
            onPressed: _completeSetup),
      ]);

  Widget _stepForgot() => _wrap('forgot', [
        _heading('Reset Password', 'Enter your Student ID to receive a reset OTP.'),
        _errorBox(),
        _field(_forgotIdCtrl, 'Student ID', Icons.badge_outlined),
        GradientButton(
            label: 'Send Reset OTP',
            icon: Icons.send,
            busy: _busy,
            onPressed: _requestReset),
        _linkRow([_link('Back to Sign In', () => _go(_Step.password))]),
      ]);

  Widget _stepReset() => _wrap('reset', [
        _heading('New Password', 'Enter the OTP and choose a new password.'),
        _errorBox(),
        _field(_resetOtpCtrl, 'OTP', Icons.tag,
            type: TextInputType.number, hint: 'XXXXXX'),
        _field(_newPwdCtrl, 'New Password', Icons.lock_outline,
            obscure: true, hint: 'At least 6 characters'),
        _field(_confirmPwdCtrl, 'Confirm Password', Icons.lock_outline,
            obscure: true, hint: 'Re-enter password'),
        GradientButton(
            label: 'Reset Password',
            icon: Icons.check,
            busy: _busy,
            onPressed: _resetPassword),
        _linkRow([_link('Back to Sign In', () => _go(_Step.password))]),
      ]);
}
