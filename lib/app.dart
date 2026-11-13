import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/i18n/lang.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/admin/admin_screens.dart';
import 'features/certificates/certificates_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/courses/course_detail_screen.dart';
import 'features/courses/explore_screen.dart';
import 'features/courses/flashcards_screen.dart';
import 'features/courses/lesson_screen.dart';
import 'features/courses/my_courses_screen.dart';
import 'features/courses/models.dart' show QuizRun;
import 'features/courses/progress_screen.dart';
import 'features/courses/quiz_screens.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/home/home_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/plan/plan_screen.dart';
import 'features/ranking/ppi_progress_screen.dart';
import 'features/ranking/ranking_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/study/study_screens.dart';
import 'features/study/study_service.dart';

GoRouter buildRouter(AuthController auth, StudyService study) => GoRouter(
      initialLocation: '/home',
      refreshListenable: Listenable.merge([auth, study]),
      redirect: (context, state) {
        if (auth.status == AuthStatus.unknown) return null;
        final loggedIn = auth.status == AuthStatus.authenticated;
        final path = state.uri.path;
        if (!loggedIn && path != '/login') return '/login'; // routes privées protégées
        if (loggedIn && path == '/login') return study.needsOnboarding ? '/onboarding' : '/home';
        // Premier lancement : choix du rythme d'étude obligatoire
        if (loggedIn && study.needsOnboarding && path != '/onboarding') return '/onboarding';
        if (loggedIn && !study.needsOnboarding && path == '/onboarding') return '/home';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/onboarding', builder: (_, __) => const PlanScreen(firstTime: true)),
        GoRoute(path: '/study/plan', builder: (_, __) => const PlanScreen(firstTime: false)),
        GoRoute(path: '/leaderboard', builder: (_, __) => const LeaderboardScreen()),
        ShellRoute(
          builder: (_, __, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
            GoRoute(path: '/explore', builder: (_, __) => const ExploreScreen()),
            GoRoute(path: '/courses', builder: (_, __) => const MyCoursesScreen()),
            GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          ],
        ),
        GoRoute(path: '/downloads', builder: (_, __) => const DownloadsScreen()),
        GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
        GoRoute(path: '/progress', builder: (_, __) => const ProgressScreen()),
        GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
        GoRoute(
          path: '/chat/:id',
          builder: (_, st) => ChatRoomScreen(int.parse(st.pathParameters['id']!),
              title: st.extra is String ? st.extra as String : null),
        ),
        GoRoute(path: '/certificates', builder: (_, __) => const CertificatesScreen()),
        GoRoute(path: '/ranking', builder: (_, __) => const RankingScreen()),
        GoRoute(path: '/badges', builder: (_, __) => const BadgesScreen()),
        GoRoute(path: '/ppi-progress', builder: (_, __) => const PpiProgressScreen()),
        GoRoute(path: '/plan', builder: (_, __) => const PlanScreen()),
        GoRoute(path: '/admin', builder: (_, __) => const AdminHomeScreen()),
        GoRoute(path: '/admin/course/new', builder: (_, __) => const AdminCourseFormScreen()),
        GoRoute(
          path: '/admin/course/:id',
          builder: (_, st) => AdminCourseTreeScreen(int.parse(st.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/admin/quiz/:id/question',
          builder: (_, st) => AdminQuestionScreen(int.parse(st.pathParameters['id']!),
              title: st.extra is String ? st.extra as String : null,
              questionId: int.tryParse(st.uri.queryParameters['edit'] ?? '')),
        ),
        GoRoute(
          path: '/course/:id',
          builder: (_, st) => CourseDetailScreen(int.parse(st.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/flashcards/:id',
          builder: (_, st) => FlashcardsScreen(courseId: int.parse(st.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/module-flashcards/:id',
          builder: (_, st) => FlashcardsScreen(
              moduleId: int.parse(st.pathParameters['id']!),
              title: st.extra is String ? st.extra as String : null),
        ),
        GoRoute(
          path: '/course/:id/quizzes',
          builder: (_, st) => QuizListScreen(int.parse(st.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/quiz/:id',
          builder: (_, st) => QuizIntroScreen(int.parse(st.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/quiz/:id/take',
          builder: (_, st) {
            final run = st.extra;
            return run is QuizRun
                ? QuizTakeScreen(run)
                : QuizIntroScreen(int.parse(st.pathParameters['id']!));
          },
        ),
        GoRoute(
          path: '/quiz-result/:id',
          builder: (_, st) => QuizResultScreen(int.parse(st.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/lesson/:id',
          builder: (_, st) => LessonScreen(int.parse(st.pathParameters['id']!)),
        ),
      ],
    );

class EducaDimApp extends StatefulWidget {
  const EducaDimApp({super.key});
  @override
  State<EducaDimApp> createState() => _EducaDimAppState();
}

class _EducaDimAppState extends State<EducaDimApp> {
  late final GoRouter _router = buildRouter(context.read<AuthController>(), context.read<StudyService>());

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeController>().mode;
    // Changer de langue reconstruit tout l'écran (textes + contenu rechargé dans la nouvelle langue).
    return ListenableBuilder(
      listenable: Lang.instance,
      builder: (context, _) => MaterialApp.router(
        title: 'EducaDim',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        themeAnimationDuration: Duration.zero, // aucune animation
        // Les composants du framework (boutons « OK », date…) utilisent le français ;
        // les textes de l'application suivent la langue choisie (Lang).
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: _router,
        builder: (context, child) =>
            KeyedSubtree(key: ValueKey(Lang.instance.code), child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
