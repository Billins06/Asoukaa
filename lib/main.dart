import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import './services/nest_auth_service.dart';
import './services/notification_service.dart';
import './widgets/custom_error_widget.dart';
import 'core/app_export.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize push notifications
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('Failed to initialize notifications: $e');
  }

  bool hasShownError = false;

  // 🚨 CRITICAL: Custom error handling - DO NOT REMOVE
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (!hasShownError) {
      hasShownError = true;

      // Reset flag after 3 seconds to allow error widget on new screens
      Future.delayed(Duration(seconds: 5), () {
        hasShownError = false;
      });

      return CustomErrorWidget(errorDetails: details);
    }
    return SizedBox.shrink();
  };

  // 🚨 CRITICAL: Device orientation lock - DO NOT REMOVE
  // Guard: SystemChrome.setPreferredOrientations is not supported on Flutter Web
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, screenType) {
        return MaterialApp(
          title: 'asoukaa',
          theme: AppTheme.lightTheme,
          themeMode: ThemeMode.light,
          // 🚨 CRITICAL: NEVER REMOVE OR MODIFY
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.0)),
              child: child!,
            );
          },
          // 🚨 END CRITICAL SECTION
          debugShowCheckedModeBanner: false,
          routes: AppRoutes.routes,
          onGenerateRoute: AppRoutes.onGenerateRoute,
          initialRoute: AppRoutes.initial,
        );
      },
    );
  }
}

// ── Auth Gate: redirects based on session state ───────────────────────────────

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    try {
      final isLoggedIn = await NestAuthService.instance.isLoggedIn()
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;

      if (isLoggedIn) {
        try {
          NotificationService.instance.subscribeToUserNotifications();
        } catch (_) {}

        final role = await NestAuthService.instance.getUserRole()
            .timeout(const Duration(seconds: 5));
        if (!mounted) return;
        switch (role) {
          case 'vendeur':
            Navigator.pushReplacementNamed(context, AppRoutes.sellerDashboard);
          case 'livreur':
            Navigator.pushReplacementNamed(context, AppRoutes.delivererDashboard);
          case 'admin':
            Navigator.pushReplacementNamed(context, AppRoutes.adminDashboard);
          default:
            Navigator.pushReplacementNamed(context, AppRoutes.home);
        }
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.signUpLogin);
      }
    } catch (e) {
      debugPrint('[AuthGate] Session check error: $e');
      if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.signUpLogin);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: CircularProgressIndicator(
          color: AppTheme.primary,
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}
