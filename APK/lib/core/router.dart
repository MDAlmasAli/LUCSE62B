import 'package:go_router/go_router.dart';

import '../data/models/app_version.dart';
import '../data/session.dart';
import '../features/auth/dob_gate_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/classwork/classwork_screen.dart';
import '../features/calendar/calendar_widget_screen.dart';
import '../features/cover_page/cover_page_screen.dart';
import '../features/gallery/gallery_screen.dart';
import '../features/home/home_screen.dart';
import '../features/info/bkash_screen.dart';
import '../features/info/bus_screen.dart';
import '../features/info/exam_screen.dart';
import '../features/info/group_links_screen.dart';
import '../features/info/info_hub_screen.dart';
import '../features/info/course_teachers_screen.dart';
import '../features/info/course_list_screen.dart';
import '../features/info/routine_screen.dart';
import '../features/info/teacher_routine_screen.dart';
import '../features/info/semester_screen.dart';
import '../features/info/teachers_screen.dart';
import '../features/notice/notice_screen.dart';
import '../features/notifications/notification_preferences_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/resources/resources_screen.dart';
import '../features/resources/category_screen.dart';
import '../features/resources/downloads_screen.dart';
import '../features/guide/user_guide_screen.dart';
import '../features/attendance/attendance_screen.dart';
import '../features/results/results_screen.dart';
import '../features/retake/retake_screen.dart';
import '../features/students/students_screen.dart';
import '../features/games/games_hub_screen.dart';
import '../features/games/imposter/imposter_screen.dart';
import '../features/games/draw/draw_screen.dart';
import '../features/update/update_gate.dart';

/// Optional (non-forced) update surfaced after startup; the `/update` route
/// reads this. Forced updates bypass the router entirely (see main.dart).
UpdateStatus? pendingOptionalUpdate;

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: Session.instance,
    redirect: (context, state) {
      final s = Session.instance;
      final loc = state.matchedLocation;

      if (loc == '/update') return null; // always reachable
      if (!s.isLoggedIn) return loc == '/login' ? null : '/login';
      if (!s.dobOk) return loc == '/dob' ? null : '/dob';
      if (loc == '/login' || loc == '/dob') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/dob', builder: (_, _) => const DobGateScreen()),
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/info', builder: (_, _) => const InfoHubScreen()),
      GoRoute(path: '/info/bus', builder: (_, _) => const BusScreen()),
      GoRoute(
        path: '/info/semester',
        builder: (_, _) => const SemesterScreen(),
      ),
      GoRoute(path: '/info/bkash', builder: (_, _) => const BkashScreen()),
      GoRoute(path: '/info/routine', builder: (_, _) => const RoutineScreen()),
      GoRoute(
        path: '/info/teacher-routine',
        builder: (_, _) => const TeacherRoutineScreen(),
      ),
      GoRoute(path: '/info/exam', builder: (_, _) => const ExamScreen()),
      GoRoute(
        path: '/info/teachers',
        builder: (_, _) => const TeachersScreen(),
      ),
      GoRoute(
        path: '/info/course-teachers',
        builder: (_, _) => const CourseTeachersScreen(),
      ),
      GoRoute(
        path: '/info/courses',
        builder: (_, _) => const CourseListScreen(),
      ),
      GoRoute(path: '/info/retake', builder: (_, _) => const RetakeScreen()),
      GoRoute(path: '/info/links', builder: (_, _) => const GroupLinksScreen()),
      GoRoute(path: '/students', builder: (_, _) => const StudentsScreen()),
      GoRoute(path: '/gallery', builder: (_, _) => const GalleryScreen()),
      GoRoute(path: '/games', builder: (_, _) => const GamesHubScreen()),
      GoRoute(
        path: '/games/imposter',
        builder: (_, _) => const ImposterScreen(),
      ),
      GoRoute(path: '/games/draw', builder: (_, _) => const DrawScreen()),
      GoRoute(path: '/classwork', builder: (_, _) => const ClassworkScreen()),
      GoRoute(path: '/resources', builder: (_, _) => const ResourcesScreen()),
      GoRoute(path: '/downloads', builder: (_, _) => const DownloadsScreen()),
      GoRoute(
        path: '/category/:cat',
        builder: (_, state) => CategoryScreen(
          cat: (state.pathParameters['cat'] ?? '').replaceAll('-', ' '),
        ),
      ),
      GoRoute(path: '/cover-page', builder: (_, _) => const CoverPageScreen()),
      GoRoute(path: '/notice', builder: (_, _) => const NoticeScreen()),
      GoRoute(path: '/user-guide', builder: (_, _) => const UserGuideScreen()),
      GoRoute(path: '/attendance', builder: (_, _) => const AttendanceScreen()),
      GoRoute(
        path: '/notification-preferences',
        builder: (_, _) => const NotificationPreferencesScreen(),
      ),
      GoRoute(
        path: '/calendar-widget',
        builder: (_, _) => const CalendarWidgetScreen(),
      ),
      GoRoute(path: '/results', builder: (_, _) => const ResultsScreen()),
      GoRoute(
        path: '/update',
        builder: (context, _) => UpdateGate(
          status: pendingOptionalUpdate!,
          onSkip: () => context.go('/'),
        ),
      ),
    ],
  );
}
