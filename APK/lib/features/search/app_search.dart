import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';

/// A searchable destination in the app (every feature the global search can
/// jump to). [keywords] broaden matching so "cgpa", "marks" etc. all find
/// Results, mirroring how the website's search works.
class SearchDest {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
  final List<String> keywords;
  final bool popular;
  const SearchDest({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
    this.keywords = const [],
    this.popular = false,
  });

  bool matches(String q) {
    if (q.isEmpty) return true;
    final hay = '$label $subtitle ${keywords.join(' ')}'.toLowerCase();
    return hay.contains(q);
  }

  int rank(String q) {
    final l = label.toLowerCase();
    if (l == q) return 0;
    if (l.startsWith(q)) return 1;
    if (l.contains(q)) return 2;
    if (keywords.any((k) => k.toLowerCase().startsWith(q))) return 3;
    return 4;
  }
}

/// The full catalog of destinations the global search covers.
const List<SearchDest> appDestinations = [
  // ── Core ──
  SearchDest(
    label: 'Cover Page',
    subtitle: 'Generate assignment / lab cover PDF',
    icon: Icons.description_rounded,
    color: Color(0xFFA78BFA),
    route: '/cover-page',
    keywords: [
      'cover',
      'assignment cover',
      'lab report cover',
      'pdf',
      'front page',
      'title page',
    ],
    popular: true,
  ),
  SearchDest(
    label: 'Results',
    subtitle: 'CGPA, grades & analytics',
    icon: Icons.bar_chart_rounded,
    color: Color(0xFF34D399),
    route: '/results',
    keywords: [
      'cgpa',
      'gpa',
      'result',
      'grade',
      'marks',
      'transcript',
      'semester result',
    ],
    popular: true,
  ),
  SearchDest(
    label: 'Class Routine',
    subtitle: 'Weekly class schedule',
    icon: Icons.calendar_month_rounded,
    color: Color(0xFF7C3AED),
    route: '/info/routine',
    keywords: [
      'routine',
      'schedule',
      'timetable',
      'class times',
      'today class',
    ],
    popular: true,
  ),
  SearchDest(
    label: 'Teacher Routine',
    subtitle: "Any teacher's weekly schedule",
    icon: Icons.co_present_rounded,
    color: Color(0xFF0EA5E9),
    route: '/info/teacher-routine',
    keywords: [
      'teacher',
      'faculty',
      'instructor',
      'teacher schedule',
      'teacher routine',
    ],
  ),
  SearchDest(
    label: 'Classwork',
    subtitle: 'Tasks, categories & deadlines',
    icon: Icons.assignment_rounded,
    color: Color(0xFF059669),
    route: '/classwork',
    keywords: ['deadline', 'homework', 'tasks', 'submission'],
    popular: true,
  ),
  SearchDest(
    label: 'Games',
    subtitle: 'Imposter & Draw — multiplayer',
    icon: Icons.sports_esports_rounded,
    color: Color(0xFFFB923C),
    route: '/games',
    keywords: [
      'game',
      'games',
      'imposter',
      'draw',
      'skribbl',
      'play',
      'multiplayer',
    ],
  ),
  // Classwork categories — searchable on their own so typing "presentation",
  // "viva", "lab test" etc. jumps straight to that category browser.
  SearchDest(
    label: 'Presentation',
    subtitle: 'Classwork · slides & presentations',
    icon: Icons.slideshow_rounded,
    color: Color(0xFF818CF8),
    route: '/category/presentation',
    keywords: ['presentation', 'slides', 'classwork'],
  ),
  SearchDest(
    label: 'Tutorial',
    subtitle: 'Classwork · tutorials & quizzes',
    icon: Icons.school_rounded,
    color: Color(0xFF38BDF8),
    route: '/category/tutorial',
    keywords: ['tutorial', 'quiz', 'classwork'],
  ),
  SearchDest(
    label: 'Lab Report',
    subtitle: 'Classwork · lab experiments & reports',
    icon: Icons.science_rounded,
    color: Color(0xFF34D399),
    route: '/category/lab-report',
    keywords: ['lab report', 'lab', 'report', 'classwork'],
  ),
  SearchDest(
    label: 'Lab Test',
    subtitle: 'Classwork · lab tests',
    icon: Icons.biotech_rounded,
    color: Color(0xFF2DD4BF),
    route: '/category/lab-test',
    keywords: ['lab test', 'lab', 'test', 'classwork'],
  ),
  SearchDest(
    label: 'Viva',
    subtitle: 'Classwork · viva',
    icon: Icons.mic_rounded,
    color: Color(0xFFFBBF24),
    route: '/category/viva',
    keywords: ['viva', 'oral', 'classwork'],
  ),
  SearchDest(
    label: 'Lab Final',
    subtitle: 'Classwork · lab final',
    icon: Icons.local_fire_department_rounded,
    color: Color(0xFFF87171),
    route: '/category/lab-final',
    keywords: ['lab final', 'lab exam', 'final', 'classwork'],
  ),
  SearchDest(
    label: 'Project',
    subtitle: 'Classwork · projects',
    icon: Icons.account_tree_rounded,
    color: Color(0xFFF472B6),
    route: '/category/project',
    keywords: ['project', 'classwork'],
  ),
  SearchDest(
    label: 'Assignment',
    subtitle: 'Classwork · assignments',
    icon: Icons.edit_rounded,
    color: Color(0xFFA78BFA),
    route: '/category/assignment',
    keywords: ['assignment', 'homework', 'classwork'],
  ),
  SearchDest(
    label: 'Notice',
    subtitle: 'Latest announcements',
    icon: Icons.campaign_rounded,
    color: Color(0xFFFBBF24),
    route: '/notice',
    keywords: ['announcement', 'lu notice', 'news'],
    popular: true,
  ),
  SearchDest(
    label: 'Students',
    subtitle: 'Class directory & WhatsApp',
    icon: Icons.groups_rounded,
    color: Color(0xFF6366F1),
    route: '/students',
    keywords: [
      'directory',
      'classmates',
      'contacts',
      'whatsapp',
      'phone number',
    ],
    popular: true,
  ),

  // ── Info sections ──
  SearchDest(
    label: 'Exam Schedule',
    subtitle: 'Mid & final term routine',
    icon: Icons.event_note_rounded,
    color: Color(0xFFDC2626),
    route: '/info/exam',
    keywords: ['exam', 'midterm', 'final', 'exam routine'],
  ),
  SearchDest(
    label: 'Teachers',
    subtitle: 'Course teachers & contacts',
    icon: Icons.person_rounded,
    color: Color(0xFF059669),
    route: '/info/teachers',
    keywords: ['faculty', 'teacher', 'course teacher', 'contact'],
  ),
  SearchDest(
    label: 'Course Teachers',
    subtitle: 'Who teaches what (by teacher / course)',
    icon: Icons.co_present_rounded,
    color: Color(0xFF14B8A6),
    route: '/info/course-teachers',
    keywords: ['course teacher', 'who teaches', 'teacher course', 'initials'],
  ),
  SearchDest(
    label: 'Course Offer',
    subtitle: 'All-batch course offer',
    icon: Icons.format_list_bulleted_rounded,
    color: Color(0xFF6366F1),
    route: '/info/courses',
    keywords: [
      'course list',
      'course offer',
      'all courses',
      'credits',
      'prerequisite',
    ],
  ),
  SearchDest(
    label: 'Retake & Improve',
    subtitle: 'Retake / improve enrollment',
    icon: Icons.replay_rounded,
    color: Color(0xFFD97706),
    route: '/info/retake',
    keywords: ['retake', 'improvement', 'fail', 'backlog', 'improve'],
  ),
  SearchDest(
    label: 'Bus Schedule',
    subtitle: 'University transport times',
    icon: Icons.directions_bus_rounded,
    color: Color(0xFF0891B2),
    route: '/info/bus',
    keywords: ['bus', 'transport', 'university bus'],
  ),
  SearchDest(
    label: 'Group Links & Codes',
    subtitle: 'Class group join links',
    icon: Icons.link_rounded,
    color: Color(0xFF2563EB),
    route: '/info/links',
    keywords: ['group', 'classroom code', 'whatsapp group', 'join link'],
  ),
  SearchDest(
    label: 'bKash Payment',
    subtitle: 'Fees codes & methods',
    icon: Icons.payments_rounded,
    color: Color(0xFFEC4899),
    route: '/info/bkash',
    keywords: ['bkash', 'fees', 'payment', 'tuition'],
  ),
  SearchDest(
    label: 'Semester Info',
    subtitle: 'Key academic dates',
    icon: Icons.school_rounded,
    color: Color(0xFF8B5CF6),
    route: '/info/semester',
    keywords: ['semester', 'academic calendar', 'dates'],
  ),
  SearchDest(
    label: 'Info',
    subtitle: 'All class info sections',
    icon: Icons.info_rounded,
    color: Color(0xFF8B5CF6),
    route: '/info',
    keywords: ['class info', 'information'],
  ),

  // ── Resources / content ──
  SearchDest(
    label: 'Resources',
    subtitle: 'Books, slides & materials',
    icon: Icons.menu_book_rounded,
    color: Color(0xFF0EA5E9),
    route: '/resources',
    keywords: ['books', 'slides', 'drive', 'materials', 'notes'],
  ),
  SearchDest(
    label: 'Gallery',
    subtitle: 'Class photos & events',
    icon: Icons.photo_library_rounded,
    color: Color(0xFFEC4899),
    route: '/gallery',
    keywords: ['photos', 'pictures', 'events', 'memories'],
  ),
  SearchDest(
    label: 'Profile',
    subtitle: 'Your account & academic info',
    icon: Icons.account_circle_rounded,
    color: Color(0xFFA78BFA),
    route: '/profile',
    keywords: ['account', 'my profile', 'dob', 'blood group', 'phone'],
  ),
  SearchDest(
    label: 'User Guide',
    subtitle: 'How to use the portal',
    icon: Icons.help_outline_rounded,
    color: Color(0xFF38BDF8),
    route: '/user-guide',
    keywords: ['help', 'guide', 'how to'],
  ),

  // ── Classwork categories ──
  SearchDest(
    label: 'Presentation',
    subtitle: 'Classwork · Presentation',
    icon: Icons.slideshow_rounded,
    color: Color(0xFFD97706),
    route: '/category/presentation',
    keywords: ['presentation', 'slide', 'ppt'],
  ),
  SearchDest(
    label: 'Tutorial',
    subtitle: 'Classwork · Tutorial',
    icon: Icons.school_rounded,
    color: Color(0xFF2563EB),
    route: '/category/tutorial',
    keywords: ['tutorial', 'ct', 'class test'],
  ),
  SearchDest(
    label: 'Lab Report',
    subtitle: 'Classwork · Lab Report',
    icon: Icons.science_rounded,
    color: Color(0xFFDB2777),
    route: '/category/lab-report',
    keywords: ['lab report', 'lab'],
  ),
  SearchDest(
    label: 'Viva',
    subtitle: 'Classwork · Viva',
    icon: Icons.mic_rounded,
    color: Color(0xFFDC2626),
    route: '/category/viva',
    keywords: ['viva', 'oral'],
  ),
  SearchDest(
    label: 'Lab Final',
    subtitle: 'Classwork · Lab Final',
    icon: Icons.fact_check_rounded,
    color: Color(0xFF0891B2),
    route: '/category/lab-final',
    keywords: ['lab final', 'lab exam'],
  ),
  SearchDest(
    label: 'Project',
    subtitle: 'Classwork · Project',
    icon: Icons.rocket_launch_rounded,
    color: Color(0xFF8B5CF6),
    route: '/category/project',
    keywords: ['project', 'final project'],
  ),
];

/// Opens the global search as a draggable modal sheet from the bottom.
Future<void> showAppSearch(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => const _SearchSheet(),
  );
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet();

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<SearchDest> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      return appDestinations.where((d) => d.popular).toList();
    }
    final list = appDestinations.where((d) => d.matches(q)).toList();
    list.sort((a, b) {
      final r = a.rank(q).compareTo(b.rank(q));
      return r != 0 ? r : a.label.compareTo(b.label);
    });
    return list;
  }

  void _go(SearchDest d) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(d.route);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final results = _results;
    final empty = _query.trim().isEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: AppColors.borderAccent)),
          ),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.muted,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  style: const TextStyle(color: AppColors.text, fontSize: 15),
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search anything — cover page, results, routine…',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.accentBright,
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppColors.muted,
                              size: 20,
                            ),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          ),
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                child: Row(
                  children: [
                    Icon(
                      empty ? Icons.star_rounded : Icons.manage_search_rounded,
                      size: 14,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      empty
                          ? 'MOST USED'
                          : '${results.length} RESULT${results.length == 1 ? '' : 'S'}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: results.isEmpty
                    ? _noResults()
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _resultTile(results[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _resultTile(SearchDest d) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _go(d),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: d.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: d.color.withValues(alpha: 0.28)),
                ),
                child: Icon(d.icon, color: d.color, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.label,
                      style: const TextStyle(
                        color: AppColors.textBright,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.north_east_rounded,
                color: AppColors.muted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noResults() => const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, color: AppColors.muted, size: 40),
          SizedBox(height: 12),
          Text(
            'Nothing matched your search.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'Try “results”, “routine”, “cover” or “bus”.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
