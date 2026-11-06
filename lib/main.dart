import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/db/app_database.dart';
import 'core/db/outbox_repository.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_store.dart';
import 'core/sync/sync_gateway.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_controller.dart';
import 'features/chat/chat_controller.dart';
import 'features/courses/course_repository.dart';
import 'features/downloads/download_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final db = await AppDatabase.open();
  final tokens = TokenStore();

  final auth = AuthController(tokens);
  final api = ApiClient(tokens, onSessionExpired: auth.expire);
  auth.api = api;
  await auth.init();

  final outbox = OutboxRepository(db);
  // Remplacer UnconfiguredGateway par l'implémentation réelle une fois les
  // endpoints confirmés (docs/API_CONTRACT.md).
  final sync = SyncService(outbox, UnconfiguredGateway());
  await sync.start();

  final chat = ChatController(db, outbox, sync)..load();
  final downloads = DownloadService(db)..load();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeController(prefs)),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: sync),
      ChangeNotifierProvider.value(value: chat),
      ChangeNotifierProvider.value(value: downloads),
      Provider<ApiClient>.value(value: api),
      Provider<CourseRepository>.value(value: UnconfiguredCourseRepository()),
    ],
    child: const EducaDimApp(),
  ));
}
