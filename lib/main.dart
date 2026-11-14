import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'dart:async';
import 'core/alerts/alert_service.dart';
import 'core/alerts/background.dart';
import 'core/db/app_database.dart';
import 'core/i18n/lang.dart';
import 'core/db/cache_store.dart';
import 'core/db/outbox_repository.dart';
import 'core/db/user_data_guard.dart';
import 'core/platform/desktop_init.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_store.dart';
import 'core/sync/pulse_service.dart';
import 'core/sync/sync_gateway.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/theme_controller.dart';
import 'features/admin/admin_repository.dart';
import 'features/auth/auth_controller.dart';
import 'features/certificates/certificates_screen.dart';
import 'features/comments/comments_service.dart';
import 'core/security/offline_access.dart';
import 'features/courses/course_repository.dart';
import 'features/courses/offline_course_service.dart';
import 'features/courses/progress_service.dart';
import 'features/downloads/download_service.dart';
import 'features/notifications/notification_service.dart';
import 'features/review/review_service.dart';
import 'features/study/study_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDesktop(); // Windows : SQLite via FFI (sans effet sur téléphone)
  final prefs = await SharedPreferences.getInstance();
  await Lang.instance.init(prefs);
  await AlertService.instance.init(prefs);
  final db = await AppDatabase.open();
  final cache = CacheStore(db);
  final tokens = TokenStore();

  final auth = AuthController(tokens, cache);
  final api = ApiClient(tokens, onSessionExpired: auth.expire);
  auth.api = api;

  final outbox = OutboxRepository(db)..ownerProvider = () => auth.identity;
  final sync = SyncService(outbox, ApiSyncGateway(api, cache))..currentOwner = () => auth.identity;

  final repo = CourseRepository(api, cache);
  final comments = CommentsService(api, prefs);
  final downloads = DownloadService(db)..load();
  final progress = ProgressService(db, outbox, sync, api);
  final offline = OfflineCourseService(db, repo, cache);
  final access = OfflineAccess(db, api, prefs);
  repo.cacheBlocked = access.blocks;
  offline.accessUntilFor = access.fetchUntil;
  access
    ..cacheKeysFor = offline.cacheKeysFor
    ..purgeCourse = (id) async {
      await offline.remove(id);
      await downloads.removeByCourse(id);
    };
  final notifications = NotificationService(api, cache, outbox, sync);
  final adminAccess = AdminAccess(api, cache);
  final review = ReviewService(api);
  final study = StudyService(api, prefs);
  final guard = UserDataGuard(db, prefs);

  sync.onItemRejected = (item) {
    final lesson = item.payload['lesson_id'];
    if (lesson is int) progress.handleRejected(lesson);
  };

  bool loggedIn() => auth.status == AuthStatus.authenticated;
  PulseService? pulse; // créé plus bas, une fois les notifications prêtes

  study.onAward = () => notifications.refresh(silent: true);
  sync.afterFlush = () async {
    if (!loggedIn()) return;
    await progress.pull();
    await notifications.refresh(silent: true);
  };

  // Téléphones partagés : un autre compte ne voit jamais les données locales du précédent.
  auth.onLoggedIn = (identity) async {
    final wiped = await guard.onLogin(identity);
    if (wiped) {
      await progress.load();
      await offline.load();
      notifications.reset();
      comments.reset();
      await downloads.purgeAll();
      access.reset();
      pulse?.reset();
    }
  };

  // Session déjà ouverte au lancement (l'identité vient du profil en cache).
  await auth.init();
  final startId = auth.identity;
  if (loggedIn() && startId != null) await auth.onLoggedIn?.call(startId);

  await progress.load();
  await offline.load();
  await notifications.loadCached();
  notifications.startPolling(loggedIn);

  auth.addListener(() {
    if (loggedIn()) {
      BackgroundAlerts.start();
      AlertService.instance.requestPermission();
      pulse?.tick();
      adminAccess.load();
      review.load();
      study.ping();
      sync.flush();
    } else {
      BackgroundAlerts.stop();
      adminAccess.clear();
      review.reset();
      study.reset();
    }
  });
  study.start(loggedIn);
  // Marque « application ouverte » pour que le worker d'arrière-plan n'alerte pas en double.
  BackgroundAlerts.markForeground(prefs);
  Timer.periodic(const Duration(seconds: 30), (_) => BackgroundAlerts.markForeground(prefs));
  if (loggedIn()) {
    BackgroundAlerts.start();
    AlertService.instance.requestPermission();
  }
  // Notifications lues « au passage » : voir core/sync/pulse_service.dart (aucun sondage répété).
  pulse = PulseService(
    api,
    loggedIn,
    onNotifications: () => notifications.refresh(silent: true),
  )..start();
  api.dio.interceptors.add(InterceptorsWrapper(onResponse: (res, handler) {
    pulse?.onHeader(res.headers.value('x-notif'));
    handler.next(res);
  }));
  if (loggedIn()) comments.maybeFetch();
  await access.sweep();
  if (loggedIn()) access.refreshIfDue();
  AppLifecycleListener(onResume: () {
    access.sweep();
    if (loggedIn()) access.refreshIfDue();
  });
  if (loggedIn()) {
    adminAccess.load();
    review.load();
    study.ping();
  }
  await sync.start();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeController(prefs)),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: sync),
      ChangeNotifierProvider.value(value: comments),
      ChangeNotifierProvider.value(value: access),
      ChangeNotifierProvider.value(value: downloads),
      ChangeNotifierProvider.value(value: progress),
      ChangeNotifierProvider.value(value: offline),
      ChangeNotifierProvider.value(value: notifications),
      ChangeNotifierProvider.value(value: adminAccess),
      ChangeNotifierProvider.value(value: review),
      ChangeNotifierProvider.value(value: study),
      Provider<ApiClient>.value(value: api),
      Provider<OutboxRepository>.value(value: outbox),
      Provider<CourseRepository>.value(value: repo),
      Provider<CertificateRepository>.value(value: CertificateRepository(api, cache)),
      Provider<AdminRepository>.value(value: AdminRepository(api)),
    ],
    child: const EducaDimApp(),
  ));
}
