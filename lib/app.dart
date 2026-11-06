import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/courses/course_detail_screen.dart';
import 'features/courses/explore_screen.dart';
import 'features/courses/lesson_screen.dart';
import 'features/courses/my_courses_screen.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/home/home_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/shell/app_shell.dart';

GoRouter buildRouter(AuthController auth) => GoRouter(
      initialLocation: '/home',
      refreshListenable: auth,
      redirect: (context, state) {
        if (auth.status == AuthStatus.unknown) return null;
        final loggedIn = auth.status == AuthStatus.authenticated;
        final onLogin = state.uri.path == '/login';
        if (!loggedIn && !onLogin) return '/login'; // routes privées protégées
        if (loggedIn && onLogin) return '/home';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        ShellRoute(
          builder: (_, __, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
            GoRoute(path: '/explore', builder: (_, __) => const ExploreScreen()),
            GoRoute(path: '/courses', builder: (_, __) => const MyCoursesScreen()),
            GoRoute(
                path: '/notifications',
                builder: (_, __) => const NotificationsScreen()),
            GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          ],
        ),
        GoRoute(path: '/downloads', builder: (_, __) => const DownloadsScreen()),
        GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
        GoRoute(
          path: '/course/:id',
          builder: (_, st) => CourseDetailScreen(int.parse(st.pathParameters['id']!)),
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
  late final GoRouter _router = buildRouter(context.read<AuthController>());

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeController>().mode;
    return MaterialApp.router(
      title: 'EducaDim',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      locale: const Locale('fr'),
      routerConfig: _router,
    );
  }
}
