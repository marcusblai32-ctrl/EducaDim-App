
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/db/app_database.dart';
import 'core/db/cache_store.dart';
import 'core/db/outbox_repository.dart';
import 'core/db/user_data_guard.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_store.dart';
import 'core/sync/sync_gateway.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/theme_controller.dart';
import 'features/admin/admin_repository.dart';
import 'features/auth/auth_controller.dart';
import 'features/certificates/certificates_screen.dart';
import 'features/chat/chat_controller.dart';
import 'features/courses/course_repository.dart';
import 'features/courses/offline_course_service.dart';
import 'features/courses/progress_service.dart';
import 'features/downloads/download_service.dart';
import 'features/notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final db = await AppDatabase.open();
  final cache = CacheStore(db);
  final tokens = TokenStore();

  final auth = AuthController(tokens, cache);

  final api = ApiClient(
    tokens,
    onSessionExpired: auth.expire,
  );

  auth.api = api;

  final outbox = OutboxRepository(db)
    ..ownerProvider = () => auth.identity;

  final sync = SyncService(
    outbox,
    ApiSyncGateway(api, cache),
  )..currentOwner = () => auth.identity;

  final repo = CourseRepository(api, cache);

  final chat = ChatController(
    api,
    db,
    cache,
    outbox,
    sync,
  );

  final downloads = DownloadService(db)..load();

  final progress = ProgressService(
    db,
    outbox,
    sync,
    api,
  );

  final offline = OfflineCourseService(
    db,
    repo,
    cache,
  );

  final notifications = NotificationService(
    api,
    cache,
    outbox,
    sync,
  );

  final adminAccess = AdminAccess(api, cache);
  final guard = UserDataGuard(db, prefs);

  sync.onItemRejected = (item) {
    final lesson = item.payload['lesson_id'];

    if (lesson is int) {
      progress.handleRejected(lesson);
    }

    if (item.kind == 'chat_message') {
      chat.handleRejected(item.id);
    }
  };

  bool loggedIn() {
    return auth.status == AuthStatus.authenticated;
  }

  sync.afterFlush = () async {
    if (!loggedIn()) return;

    await progress.pull();
    await notifications.refresh(silent: true);
  };

  // Téléphones partagés :
  // les données locales d'un compte ne doivent pas être
  // accessibles au compte suivant.
  auth.onLoggedIn = (identity) async {
    final wiped = await guard.onLogin(identity);

    if (wiped) {
      notifications.reset();
      chat.reset();

      await progress.load();
      await offline.load();
    }
  };

  // Initialisation de la session.
  await auth.init();

  final startId = auth.identity;

  if (loggedIn() && startId != null) {
    await auth.onLoggedIn?.call(startId);
  }

  // Chargement des données locales.
  await progress.load();
  await offline.load();
  await notifications.loadCached();

  // Actualisation périodique des notifications.
  notifications.startPolling(loggedIn);

  // Surveillance des changements de session.
  auth.addListener(() {
    if (loggedIn()) {
      adminAccess.load();
      sync.flush();
    } else {
      adminAccess.clear();
    }
  });

  if (loggedIn()) {
    adminAccess.load();
  }

  await sync.start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ThemeController(prefs),
        ),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: sync),
        ChangeNotifierProvider.value(value: chat),
        ChangeNotifierProvider.value(value: downloads),
        ChangeNotifierProvider.value(value: progress),
        ChangeNotifierProvider.value(value: offline),
        ChangeNotifierProvider.value(value: notifications),
        ChangeNotifierProvider.value(value: adminAccess),
        Provider<ApiClient>.value(value: api),
        Provider<OutboxRepository>.value(value: outbox),
        Provider<CourseRepository>.value(value: repo),
        Provider<CertificateRepository>.value(
          value: CertificateRepository(api, cache),
        ),
        Provider<AdminRepository>.value(
          value: AdminRepository(api),
        ),
      ],
      child: const EducaDimApp(),
    ),
  );
}
