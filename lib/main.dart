import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/db/app_database.dart';
import 'core/db/cache_store.dart';
import 'core/db/outbox_repository.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_store.dart';
import 'core/sync/sync_gateway.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_controller.dart';
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
  final api = ApiClient(tokens, onSessionExpired: auth.expire);
  auth.api = api;
  await auth.init();

  final outbox = OutboxRepository(db);
  // Progression -> endpoint réel ; chat -> pas d'endpoint (reste en attente).
  final sync = SyncService(outbox, ApiSyncGateway(api, cache));

  final repo = CourseRepository(api, cache);
  final chat = ChatController(db, outbox, sync)..load();
  final downloads = DownloadService(db)..load();
  final progress = ProgressService(db, outbox, sync, api)..load();
  sync.onItemRejected = (item) {
    final id = item.payload['lesson_id'];
    if (id is int) progress.handleRejected(id);
  };
  final notifications = NotificationService(api, cache, outbox, sync);
  bool loggedIn() => auth.status == AuthStatus.authenticated;
  sync.afterFlush = () async {
    if (!loggedIn()) return;
    await progress.pull();
    await notifications.refresh(silent: true);
  };
  await notifications.loadCached();
  notifications.startPolling(loggedIn);
  // À chaque connexion réussie : envoyer la file puis récupérer progression/notifications.
  auth.addListener(() {
    if (loggedIn()) sync.flush();
  });
  await sync.start();
  final offline = OfflineCourseService(db, repo, cache)..load();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeController(prefs)),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: sync),
      ChangeNotifierProvider.value(value: chat),
      ChangeNotifierProvider.value(value: downloads),
      ChangeNotifierProvider.value(value: progress),
      ChangeNotifierProvider.value(value: offline),
      ChangeNotifierProvider.value(value: notifications),
      Provider<ApiClient>.value(value: api),
      Provider<OutboxRepository>.value(value: outbox),
      Provider<CourseRepository>.value(value: repo),
    ],
    child: const EducaDimApp(),
  ));
}
