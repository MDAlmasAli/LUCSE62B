import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../../core/constants.dart';
import '../../core/worker_api.dart';
import '../../data/session.dart';
import '../../data/update_service.dart';
import '../../shared/avatar_badge.dart';
import '../../shared/glass_card.dart';

/// Academic info pulled from the LU result payload (row_data.student), mirroring
/// the website's profile "Academic Information" card.
class _Academic {
  final String degree,
      bloodGroup,
      waiver,
      fatherName,
      motherName,
      address,
      phone;
  const _Academic({
    this.degree = '',
    this.bloodGroup = '',
    this.waiver = '',
    this.fatherName = '',
    this.motherName = '',
    this.address = '',
    this.phone = '',
  });

  bool get hasAny =>
      degree.isNotEmpty ||
      bloodGroup.isNotEmpty ||
      waiver.isNotEmpty ||
      fatherName.isNotEmpty ||
      motherName.isNotEmpty ||
      address.isNotEmpty;

  static String _s(Object? v) => (v ?? '').toString().trim();

  static _Academic parse(Map<String, dynamic> raw) {
    final s = (raw['student'] as Map?) ?? const {};
    final rs = ((raw['row_data'] as Map?)?['student'] as Map?) ?? const {};
    return _Academic(
      degree: _s(rs['Degree']).isNotEmpty ? _s(rs['Degree']) : _s(s['degree']),
      bloodGroup: _s(rs['Blood_group']),
      waiver: _s(rs['Waiver']),
      fatherName: _s(rs['Father_Name']),
      motherName: _s(rs['Mother_Name']),
      address: _s(rs['Present_Add']),
      phone: _s(rs['Student_Tel']),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _version = '';
  String _phone = '';
  String _dob = '';
  _Academic? _academic;
  bool _loadingAcademic = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadAcademic();
  }

  Future<void> _loadVersion() async {
    final code = await UpdateService.instance.currentVersionCode();
    if (mounted) setState(() => _version = 'build $code');
  }

  /// Best-effort: pull the student's phone + academic info from LU using the
  /// DOB verified at login. The result endpoint is sometimes CAPTCHA-blocked,
  /// so the lighter /my-phone is also queried for the phone independently.
  Future<void> _loadAcademic() async {
    final s = Session.instance.student;
    if (s == null || s.isDemo) return;
    var dob = await Session.instance.storedDob(s.id);
    dob ??= await WorkerApi.instance.dobGet(s.id);
    if (!mounted) return;
    if (dob != null && dob.isNotEmpty) {
      setState(() => _dob = _formatDob(dob!));
    }
    if (dob == null || dob.isEmpty) return;

    setState(() => _loadingAcademic = true);
    // Phone (independent, lighter) + full result (academic info) in parallel.
    final phoneF = WorkerApi.instance.myPhone(s.id, dob);
    Future<_Academic?> academicF() async {
      try {
        final raw = await WorkerApi.instance.result(s.id, dob!);
        if (raw['success'] != true) return null;
        return _Academic.parse(raw);
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([phoneF, academicF()]);
    if (!mounted) return;
    final phone = results[0] as String?;
    final academic = results[1] as _Academic?;
    setState(() {
      _loadingAcademic = false;
      if (academic != null) _academic = academic;
      _phone = (phone != null && phone.isNotEmpty)
          ? phone
          : (academic?.phone ?? '');
    });
  }

  String _formatDob(String raw) {
    final d = DateTime.tryParse(raw);
    if (d != null) return DateFormat('d MMMM yyyy').format(d);
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final s = Session.instance.student;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: s == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Center(
                  child: AvatarBadge(
                    name: s.name,
                    size: 84,
                    radius: 24,
                    fontSize: 34,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    s.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textBright,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      s.isDemo ? 'Demo session' : 'ID: ${s.id}',
                      style: const TextStyle(
                        color: AppColors.accentBright,
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Badges row (Phone · Section 62B · Leading University).
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_phone.isNotEmpty)
                      _badge(Icons.phone_rounded, _phone, AppColors.green),
                    _badge(
                      Icons.school_rounded,
                      'Section 62B',
                      AppColors.accentBright,
                    ),
                    _badge(
                      Icons.account_balance_rounded,
                      'Leading University',
                      const Color(0xFF38BDF8),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (_academic != null && _academic!.hasAny) ...[
                  _academicCard(_academic!),
                  const SizedBox(height: 14),
                ] else if (_loadingAcademic) ...[
                  _academicLoading(),
                  const SizedBox(height: 14),
                ],

                if (_dob.isNotEmpty) ...[
                  GlassCard(
                    child: _row(Icons.cake_rounded, 'Date of Birth', _dob),
                  ),
                  const SizedBox(height: 14),
                ],

                GlassCard(
                  child: Column(
                    children: [
                      _row(Icons.badge_outlined, 'Student ID', s.id),
                      const Divider(height: 18, color: AppColors.border),
                      _row(
                        Icons.verified_user_outlined,
                        'Status',
                        s.isDemo ? 'Guest demo' : 'Verified student',
                      ),
                      const Divider(height: 18, color: AppColors.border),
                      _row(Icons.info_outline, 'App version', _version),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  onTap: () => context.push('/results'),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.bar_chart_rounded,
                        size: 18,
                        color: AppColors.accentBright,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'My Results',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.muted,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (s.id == K.attendanceAdminId) ...[
                  GlassCard(
                    onTap: () => context.push('/attendance'),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.how_to_reg_rounded,
                          size: 18,
                          color: AppColors.accentBright,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Attendance (Admin)',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.chevron_right,
                          color: AppColors.muted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                GlassCard(
                  onTap: () => context.push('/notification-preferences'),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: AppColors.accentBright,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Notification Preferences',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.muted,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                GlassCard(
                  onTap: () => context.push('/calendar-widget'),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        size: 18,
                        color: AppColors.accentBright,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Calendar & Home Widget',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.muted,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                GlassCard(
                  onTap: () => context.push('/user-guide'),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.menu_book_rounded,
                        size: 18,
                        color: AppColors.accentBright,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'User Guide',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.muted,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Session.instance.signOut();
                    if (context.mounted) context.go('/login');
                  },
                  icon: const Icon(Icons.logout, color: AppColors.red),
                  label: const Text(
                    'Sign Out',
                    style: TextStyle(color: AppColors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: AppColors.red.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _badge(IconData icon, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _academicCard(_Academic a) {
    final rows = <Widget>[];
    void add(IconData icon, Color color, String label, String value) {
      if (value.isEmpty) return;
      if (rows.isNotEmpty) {
        rows.add(const Divider(height: 18, color: AppColors.border));
      }
      rows.add(_row(icon, label, value, color: color));
    }

    add(Icons.school_rounded, AppColors.accentBright, 'Programme', a.degree);
    add(
      Icons.bloodtype_rounded,
      const Color(0xFFF87171),
      'Blood Group',
      a.bloodGroup,
    );
    add(Icons.percent_rounded, AppColors.green, 'Waiver', a.waiver);
    add(
      Icons.man_rounded,
      const Color(0xFFA78BFA),
      "Father's Name",
      a.fatherName,
    );
    add(
      Icons.woman_rounded,
      const Color(0xFFF472B6),
      "Mother's Name",
      a.motherName,
    );
    add(
      Icons.location_on_rounded,
      const Color(0xFF38BDF8),
      'Address',
      a.address,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Academic Information'),
        const SizedBox(height: 8),
        GlassCard(child: Column(children: rows)),
      ],
    );
  }

  Widget _academicLoading() => Container(
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: const Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accent,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Loading academic information from LU…',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
        ),
      ],
    ),
  );

  Widget _sectionLabel(String s) => Text(
    s.toUpperCase(),
    style: const TextStyle(
      color: AppColors.accentBright,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    ),
  );

  Widget _row(IconData icon, String label, String value, {Color? color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color ?? AppColors.accentBright),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
