import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import './core/session_navigator.dart';
import './services/api_service.dart';
import './services/nest_auth_service.dart';
import './services/mode_service.dart';
import './services/notification_service.dart';
import './services/presence_service.dart';
import './widgets/custom_error_widget.dart';
import './services/deep_link_service.dart';
import 'core/app_export.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Adresse du serveur éventuellement modifiée dans l'appli (tunnel, nouvelle IP)
  await ApiService.instance.chargerAdresseEnregistree();

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

  // Liens profonds (partage de fiche produit) — initialisé après runApp
  // pour que le Navigator existe déjà si un lien est reçu tout de suite.
  DeepLinkService.instance.init();

  // Présence « En ligne / Vu à … » : ping toutes les 45 s tant que l'app est
  // au premier plan et qu'un utilisateur est connecté.
  PresenceService.instance.start();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, screenType) {
        return MaterialApp(
          title: 'asoukaa',
          navigatorKey: rootNavigatorKey,
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

        // Rôle effectif : un vendeur dont le dernier mode est « client »
        // retrouve l'accueil client (voir ModeService).
        final role = await ModeService.instance.getEffectiveRole()
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
