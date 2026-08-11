import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'services/auth_controller.dart';

class CollegeProjectApp extends StatelessWidget {
  const CollegeProjectApp({super.key, required this.authController});

  final AuthController authController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: ListenableBuilder(
        listenable: authController,
        builder: (context, _) {
          switch (authController.status) {
            case AuthStatus.restoring:
              return const _SplashScreen();
            case AuthStatus.signedIn:
              return HomeShell(controller: authController);
            case AuthStatus.signingIn:
            case AuthStatus.signedOut:
              return LoginScreen(controller: authController);
          }
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school_outlined, size: 64, color: scheme.primary),
            const SizedBox(height: 16),
            const CircularProgressIndicator(strokeWidth: 2.5),
          ],
        ),
      ),
    );
  }
}
