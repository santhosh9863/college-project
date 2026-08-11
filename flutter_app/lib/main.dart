import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/security/secure_local_storage.dart';
import 'data/repositories/auth_repository.dart';
import 'services/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sessions are persisted in the platform keychain (SecureLocalStorage),
  // never in plaintext storage. No Linways secrets are handled at startup.
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureLocalStorage(),
      persistSession: true,
      detectSessionInUri: false,
    ),
  );

  final authController = AuthController(repository: AuthRepository());

  runApp(CollegeProjectApp(authController: authController));
}
