import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';

class _Section {
  final IconData icon;
  final Color color;
  final String title;
  final List<String> points; // "**Term** — detail" or plain
  final String? tip;
  const _Section(this.icon, this.color, this.title, this.points, {this.tip});
}

/// In-app user guide — a scannable, mobile-adapted version of the site's User
/// Guide covering every feature of the portal app.
class UserGuideScreen extends StatelessWidget {
  const UserGuideScreen({super.key});

  static List<_Section> get _sections => <_Section>[
    _Section(Icons.door_front_door_rounded, AppColors.indigoBright, 'Getting Started', [
      '**Log in** — Open the app and enter your 16-digit Student ID and password.',
      '**First time?** — Tap "Set Password" on the login screen, enter your Student ID and verify with an OTP to create a password.',
      '**Forgot password?** — Use "Forgot Password" on the login screen and verify your identity to reset it.',
      '**Date of birth** — After your first login you confirm your date of birth once to unlock the portal.',
    ], tip: 'Your session stays signed in for 7 days, so you do not have to log in every time you open the app.'),
    _Section(Icons.home_rounded, AppColors.accentBright, 'Home', [
      '**Navigation grid** — Tap any tile to open a section: Class Material, Classwork, categories, Gallery, Info, Students, Notices, Cover Page and more.',
      '**Notification bell** — The bell at the top shows your latest notifications.',
      '**Profile** — Tap your avatar (top-right) to open your profile.',
    ]),
    _Section(Icons.groups_rounded, Color(0xFF67E8F9), 'Students Directory', [
      '**Search** — Find a classmate by name or Student ID; results filter as you type.',
      '**Profiles** — Tap a student card to view their full details.',
    ]),
    _Section(Icons.assignment_rounded, Color(0xFFFDBA74), 'Classwork & Deadlines', [
      '**Upcoming tasks** — See assignments, lab reports and quizzes sorted by the soonest deadline.',
      '**Urgency** — Items due within 3 days are highlighted so you never miss one.',
    ]),
    _Section(Icons.category_rounded, AppColors.orangeBright, 'Categories', [
      '**Presentation, Tutorial, Lab Report, Viva, Lab Final, Project** — Each tile opens that category.',
      '**Answers** — Browse quick answers and resources shared for that category.',
      '**Deadlines** — A live countdown shows that category\'s upcoming deadlines.',
      '**Search** — Use the search bar to filter entries inside a category.',
    ]),
    _Section(Icons.event_note_rounded, AppColors.cyanBright, 'Class Info', [
      '**Class Routine** — Your weekly class schedule for Batch 62, Section B.',
      '**Exam Schedule** — Mid-term and final exam dates and times.',
      '**Bus Schedule** — University bus routes and timings.',
      '**Semester Fees** — Fee breakdown and payment info.',
      '**bKash** — Payment numbers and instructions.',
      '**Teachers** — Course teachers with contact details.',
      '**Group Links** — Class WhatsApp / Messenger / Drive links.',
    ]),
    _Section(Icons.menu_book_rounded, Color(0xFF7C3AED), 'Resources', [
      '**Course materials** — Browse study materials grouped by course.',
      '**Mid / Final folders** — Open each course\'s Mid-term and Final Drive folders directly.',
    ]),
    _Section(Icons.description_rounded, Color(0xFF7C3AED), 'Cover Page Generator', [
      '**Pick a template** — Two templates (Modern / Classic), matching the website exactly.',
      '**Choose type** — Assignment or Lab Report, single or group submission.',
      '**Autofill** — Start typing a course and it fills the code, teacher, designation and department for you. Teacher and student names autocomplete too.',
      '**Generate PDF** — Tap Generate to open a print / share / save preview.',
    ], tip: 'Topics you have used before are suggested for the same course and number.'),
    _Section(Icons.photo_library_rounded, Color(0xFFEC4899), 'Gallery', [
      '**Class photos** — Browse photos and memorable moments from the batch.',
      '**Full screen** — Tap any photo to view it larger.',
    ]),
    _Section(Icons.notifications_rounded, Color(0xFFF59E0B), 'Notifications', [
      '**Bell** — Tap the bell on Home to see recent notifications.',
      '**Push** — Allow notifications so you are alerted about new notices and updates even when the app is closed.',
    ]),
    _Section(Icons.campaign_rounded, AppColors.red, 'Notice & What\'s New', [
      '**Notice** — The latest official Leading University notices.',
      '**What\'s New** — A log of new features and fixes added to the portal.',
    ]),
    _Section(Icons.account_circle_rounded, Color(0xFF6366F1), 'Your Profile', [
      '**Your details** — View your name, Student ID and info.',
      '**My Courses** — See the courses you are enrolled in.',
      '**Log out** — Sign out from the profile screen.',
    ]),
    _Section(Icons.system_update_rounded, AppColors.green, 'App Updates', [
      '**Automatic** — The app updates itself; you never need a new file from anyone.',
      '**Changelog** — Each update shows what is new and which bugs were fixed.',
      '**Required** — Important updates must be installed before you continue, so everyone stays on the latest version.',
    ], tip: 'When an update appears, tap Update — it downloads and installs inside the app.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('User Guide'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Text(
              'Everything you can do in the CSE 62B portal app. Tap a section to expand.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.5),
            ),
          ),
          ..._sections.asMap().entries.map((e) => _tile(e.value, e.key == 0)),
        ],
      ),
    );
  }

  Widget _tile(_Section s, bool open) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: ThemeData.dark().copyWith(
          dividerColor: Colors.transparent,
          colorScheme: ColorScheme.dark(primary: AppColors.accent),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: open,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            iconColor: AppColors.accentBright,
            collapsedIconColor: AppColors.muted,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: s.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: s.color.withValues(alpha: 0.3)),
              ),
              child: Icon(s.icon, color: s.color, size: 20),
            ),
            title: Text(s.title,
                style: TextStyle(
                    color: AppColors.textBright,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5)),
            children: [
              ...s.points.map((p) => _point(p, s.color)),
              if (s.tip != null) _tipBox(s.tip!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _point(String raw, Color color) {
    // Split a leading "**Term** — rest" into bold + normal.
    final m = RegExp(r'^\*\*(.+?)\*\*\s*(.*)$').firstMatch(raw);
    final spans = <TextSpan>[];
    if (m != null) {
      spans.add(TextSpan(
          text: m.group(1),
          style: TextStyle(color: AppColors.textBright, fontWeight: FontWeight.w700)));
      spans.add(TextSpan(text: ' ${m.group(2)}'));
    } else {
      spans.add(TextSpan(text: raw));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 9),
            child: Icon(Icons.circle, size: 6, color: color),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.5),
                children: spans,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipBox(String tip) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_rounded, color: AppColors.accentBright, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tip,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5, height: 1.45)),
            ),
          ],
        ),
      );
}
