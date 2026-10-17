import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/session_navigator.dart';
import '../routes/app_routes.dart';
import '../widgets/app_toast.dart';
import 'deliverer_availability.dart';
import 'notification_service.dart';
import 'token_storage_service.dart';
import 'wishlist_service.dart';

/// Issue d'une tentative de renouvellement du jeton d'accès.
enum ResultatRafraichissement {
  /// Nouveaux jetons reçus et enregistrés.
  reussi,

  /// Le serveur a refusé le jeton de rafraîchissement (expiré / invalide) :
  /// la session est définitivement perdue, il faut se reconnecter.
  refuse,

  /// Pas de réponse exploitable (réseau coupé, serveur en panne...) : on ne
  /// sait pas si la session est encore bonne, on ne déconnecte pas.
  injoignable,

  /// Aucun jeton de rafraîchissement stocké (ex. compte admin de test).
  aucunJeton,
}

/// Interrupteur du réglage « adresse du serveur » (appui long sur le logo).
///
/// Pourquoi : n'importe qui pouvait coller une adresse de tunnel et récupérer
/// les identifiants / codes OTP / numéros Mobile Money saisis. Le réglage
/// n'existe donc QUE :
///  - en debug (`flutter run`), ou
///  - dans un APK de test compilé exprès avec
///    `--dart-define=ALLOW_SERVER_OVERRIDE=true`.
/// Dans un APK de production normal, les deux valeurs sont fausses : l'écran
/// est inaccessible et toute adresse déjà enregistrée est ignorée.
const bool kAllowServerOverride =
    bool.fromEnvironment('ALLOW_SERVER_OVERRIDE', defaultValue: false);

/// Vrai seulement en debug ou en version de test (voir [kAllowServerOverride]).
const bool kReglageServeurActif = kDebugMode || kAllowServerOverride;

class ApiService {
  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._();
  ApiService._();

  // NestJS backend écoute sur le port 3001.
  // Pour tester sur appareil réel (USB) : adb reverse tcp:3001 tcp:3001
  // Pour IP personnalisée : flutter run --dart-define=API_BASE_URL=http://TON_IP:3001
  static String get _baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;
    // 127.0.0.1 plutôt que 'localhost' : sur certains appareils Android réels,
    // la résolution DNS du nom 'localhost' échoue de façon intermittente
    // (SocketException: Failed host lookup). L'IP littérale ne nécessite
    // aucune résolution et fonctionne de manière fiable avec adb reverse.
    return 'http://127.0.0.1:3001';
  }

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  )..interceptors.add(_AuthInterceptor());

  Dio get client => _dio;

  // ── Renouvellement du jeton d'accès (refresh token) ───────────────────────
  // Une seule tentative à la fois : si dix requêtes reçoivent un 401 en même
  // temps, elles attendent toutes le MÊME renouvellement.
  static Completer<ResultatRafraichissement>? _rafraichissementEnCours;

  /// Issue du dernier renouvellement tenté (null si aucun depuis le démarrage).
  static ResultatRafraichissement? derniereIssueRafraichissement;
  static DateTime? _dernierEchecA;

  /// À appeler après une connexion réussie : repart de zéro.
  static void reinitialiserRafraichissement() {
    derniereIssueRafraichissement = null;
    _dernierEchecA = null;
  }

  /// Déconnexion « session expirée » : purge la session, renvoie vers l'écran
  /// de connexion avec le message « Session expirée, reconnectez-vous ».
  static void sessionExpiree() => _AuthInterceptor()._terminerSessionExpiree();

  static Future<ResultatRafraichissement> rafraichirSession() {
    final enCours = _rafraichissementEnCours;
    if (enCours != null) return enCours.future;
    // Anti-martèlement : après un échec récent, on ne rappelle pas le serveur
    // (plusieurs services vérifient la session toutes les 10 à 30 s).
    final dernier = derniereIssueRafraichissement;
    final echecA = _dernierEchecA;
    if (dernier != null && echecA != null) {
      final fenetre = dernier == ResultatRafraichissement.refuse
          ? const Duration(seconds: 60)
          : const Duration(seconds: 5);
      if (DateTime.now().difference(echecA) < fenetre) {
        return Future<ResultatRafraichissement>.value(dernier);
      }
    }
    final completer = Completer<ResultatRafraichissement>();
    _rafraichissementEnCours = completer;
    () async {
      try {
        final issue = await _executerRafraichissement();
        derniereIssueRafraichissement = issue;
        _dernierEchecA =
            issue == ResultatRafraichissement.reussi ? null : DateTime.now();
        completer.complete(issue);
      } catch (_) {
        derniereIssueRafraichissement = ResultatRafraichissement.injoignable;
        _dernierEchecA = DateTime.now();
        completer.complete(ResultatRafraichissement.injoignable);
      } finally {
        _rafraichissementEnCours = null;
      }
    }();
    return completer.future;
  }

  static Future<ResultatRafraichissement> _executerRafraichissement() async {
    final refresh = await TokenStorageService.instance.getRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      return ResultatRafraichissement.aucunJeton;
    }
    // Client à part, SANS intercepteur : un 401 ici ne doit pas relancer un
    // renouvellement (pas de boucle).
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiService.instance.adresseActuelle,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        validateStatus: (_) => true,
      ),
    );
    try {
      final r = await dio.post(
        '/api/v1/auth/refresh',
        data: {'refreshToken': refresh},
      );
      final code = r.statusCode ?? 0;
      if (code >= 200 && code < 300) {
        final d = r.data;
        if (d is Map) {
          final acces = d['accessToken'];
          final nouveau = d['refreshToken'];
          if (acces is String && acces.isNotEmpty) {
            await TokenStorageService.instance.saveTokens(
              accessToken: acces,
              refreshToken:
                  (nouveau is String && nouveau.isNotEmpty) ? nouveau : refresh,
            );
            return ResultatRafraichissement.reussi;
          }
        }
        return ResultatRafraichissement.refuse;
      }
      // 400/401/403 : jeton refusé. 404 : serveur sans cette route (ancien
      // serveur) -> on ne peut pas renouveler, même conséquence.
      if (code == 400 || code == 401 || code == 403 || code == 404) {
        return ResultatRafraichissement.refuse;
      }
      return ResultatRafraichissement.injoignable; // 429, 5xx...
    } on DioException {
      return ResultatRafraichissement.injoignable;
    } finally {
      dio.close();
    }
  }

  // ── Adresse du serveur modifiable depuis l'appli ──────────────────────────
  // Utile quand l'adresse change (tunnel Cloudflare, nouvelle IP Wi-Fi...) :
  // on la colle dans l'appli au lieu de refaire un APK.
  static const String _cleAdresseServeur = 'server_url_override';

  /// Adresse « d'usine » : celle compilée dans l'appli (dart-define) ou le défaut.
  String get adresseParDefaut => _baseUrl;

  /// Adresse réellement utilisée en ce moment.
  String get adresseActuelle => _dio.options.baseUrl;

  /// True si une adresse personnalisée a été enregistrée.
  bool get adressePersonnalisee => _dio.options.baseUrl != _baseUrl;

  /// À appeler au démarrage, avant la première requête.
  Future<void> chargerAdresseEnregistree() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_cleAdresseServeur);
      if (!kReglageServeurActif) {
        // Version de production : une adresse personnalisée laissée par une
        // ancienne version est oubliée, on reste sur l'adresse officielle.
        if (saved != null) await prefs.remove(_cleAdresseServeur);
        _dio.options.baseUrl = _baseUrl;
        return;
      }
      if (saved != null && saved.isNotEmpty) {
        // Une adresse enregistrée par une ancienne version (sans liste
        // blanche) est revérifiée : si elle n'est plus admise, on l'oublie
        // et on revient à l'adresse d'usine.
        if (normaliserAdresse(saved) != null) {
          _dio.options.baseUrl = saved;
        } else {
          await prefs.remove(_cleAdresseServeur);
        }
      }
    } catch (e) {
      debugPrint('[API] Lecture adresse serveur impossible: $e');
    }
  }

  /// Nettoie ce que l'utilisateur a collé (sans vérifier le domaine).
  /// Retourne null si la structure est invalide.
  static String? _nettoyerAdresse(String brut) {
    // Si on a collé tout le message WhatsApp, on isole l'adresse https://...
    final trouve = RegExp(r'https?://[^\s]+', caseSensitive: false)
        .firstMatch(brut);
    var t = (trouve?.group(0) ?? brut).trim();
    if (t.isEmpty) return null;
    if (!t.contains('://')) {
      final hote = t.split('/').first.split(':').first.toLowerCase();
      final https = hote.endsWith('.trycloudflare.com') ||
          hote.endsWith('.ngrok-free.app') ||
          hote.endsWith('.ngrok.io') ||
          hote.endsWith('.ngrok.app') ||
          hote == 'asoukaa.com' ||
          hote.endsWith('.asoukaa.com');
      t = (https ? 'https://' : 'http://') + t;
    }
    while (t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    // Les appels ajoutent déjà /api/v1 : on le retire si l'utilisateur l'a collé.
    if (t.endsWith('/api/v1')) {
      t = t.substring(0, t.length - '/api/v1'.length);
    }
    final uri = Uri.tryParse(t);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return t;
  }

  // Anti-hameçonnage : une adresse de serveur malveillante recevrait les
  // identifiants saisis dans l'appli. Seules ces destinations sont admises :
  //  - https://*.trycloudflare.com, https://*.ngrok-free.app / *.ngrok.io /
  //    *.ngrok.app
  //  - https://asoukaa.com et https://*.asoukaa.com
  //  - http(s) vers localhost, 127.0.0.1, 10.0.2.2 ou une IP privée
  //    (192.168.x.x, 10.x.x.x, 172.16-31.x.x), AVEC un port explicite.
  // On compare le NOM D'HÔTE analysé (jamais le texte brut), pour qu'une
  // adresse comme https://asoukaa.com.pirate.net ou
  // https://asoukaa.com@pirate.net ne passe pas.
  static bool _estIpPriveeOuLocale(String hote) {
    if (hote == 'localhost' || hote == '127.0.0.1') return true;
    final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
        .firstMatch(hote);
    if (m == null) return false;
    final o = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
    if (o.any((v) => v > 255)) return false;
    if (o[0] == 10) return true;
    if (o[0] == 192 && o[1] == 168) return true;
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true;
    return false;
  }

  static bool _estAdresseAutorisee(Uri uri) {
    if (!kReglageServeurActif) return false;
    if (uri.userInfo.isNotEmpty) return false;
    // L'adresse d'usine du projet est toujours admise (elle vient du build,
    // pas d'un message collé par un tiers).
    if (uri.toString().replaceAll(RegExp(r'/+$'), '') ==
        _baseUrl.replaceAll(RegExp(r'/+$'), '')) {
      return true;
    }
    final hote = uri.host.toLowerCase();
    if (!RegExp(r'^[a-z0-9.\-]+$').hasMatch(hote)) return false;
    final https = uri.scheme == 'https';

    if (https) {
      const suffixes = [
        '.trycloudflare.com',
        '.ngrok-free.app',
        '.ngrok.io',
        '.ngrok.app',
        '.asoukaa.com',
      ];
      if (hote == 'asoukaa.com') return true;
      for (final suf in suffixes) {
        if (hote.endsWith(suf) && hote.length > suf.length) return true;
      }
    }
    // Réseau local / machine de développement : port obligatoire, et
    // uniquement en debug. Une version de test n'accepte que du https.
    if (kDebugMode && _estIpPriveeOuLocale(hote) && uri.hasPort) return true;
    return false;
  }

  /// Retourne null si [brut] est une adresse acceptable, sinon un message
  /// d'erreur lisible en français.
  static String? erreurAdresse(String brut) {
    if (!kReglageServeurActif) {
      return 'Le changement d\'adresse du serveur n\'est pas disponible '
          'dans cette version de l\'application.';
    }
    final propre = _nettoyerAdresse(brut);
    if (propre == null) {
      return 'Adresse invalide. Exemple : https://xxxx.trycloudflare.com';
    }
    final uri = Uri.parse(propre);
    if (_estAdresseAutorisee(uri)) return null;
    return kDebugMode
        ? 'Adresse refusée (${uri.host}) : seules les adresses de l\'équipe '
            'Asoukaa (asoukaa.com, trycloudflare.com, ngrok) ou du réseau '
            'local avec un port (ex. http://192.168.1.10:3001) sont acceptées.'
        : 'Adresse refusée (${uri.host}) : seules les adresses https de '
            'l\'équipe Asoukaa (asoukaa.com, trycloudflare.com, ngrok) sont '
            'acceptées.';
  }

  /// Nettoie et VALIDE l'adresse. Retourne null si invalide ou refusée.
  static String? normaliserAdresse(String brut) {
    final propre = _nettoyerAdresse(brut);
    if (propre == null) return null;
    return _estAdresseAutorisee(Uri.parse(propre)) ? propre : null;
  }

  /// Enregistre l'adresse (ou revient à celle d'usine si [brut] est null/vide).
  /// Retourne l'adresse appliquée, ou null si [brut] est invalide.
  Future<String?> definirAdresse(String? brut) async {
    final prefs = await SharedPreferences.getInstance();
    if (brut == null || brut.trim().isEmpty || !kReglageServeurActif) {
      await prefs.remove(_cleAdresseServeur);
      _dio.options.baseUrl = _baseUrl;
      return (brut == null || brut.trim().isEmpty) ? _baseUrl : null;
    }
    final propre = normaliserAdresse(brut);
    if (propre == null) return null;
    await prefs.setString(_cleAdresseServeur, propre);
    _dio.options.baseUrl = propre;
    return propre;
  }

  /// Teste si le serveur répond à [adresse] (toute réponse HTTP < 500 compte).
  /// Retourne null si OK, sinon un message d'erreur lisible.
  static Future<String?> testerAdresse(String adresse) async {
    final erreur = erreurAdresse(adresse);
    if (erreur != null) return erreur;
    final propre = normaliserAdresse(adresse);
    if (propre == null) return 'Adresse invalide';
    final testeur = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (_) => true,
      ),
    );
    try {
      final r = await testeur.get('$propre/api/v1/products',
          queryParameters: {'limit': 1});
      final code = r.statusCode ?? 0;
      if (code == 530 || code == 502) {
        return 'Tunnel fermé ou serveur arrêté sur le PC ($code)';
      }
      if (code >= 500) return 'Le serveur répond mais en erreur ($code)';
      return null;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Pas de réponse (délai dépassé)';
      }
      return 'Serveur injoignable';
    } catch (_) {
      return 'Serveur injoignable';
    } finally {
      testeur.close();
    }
  }
}

class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await TokenStorageService.instance.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    // Jamais de fragment de token dans les logs : debugPrint n'est pas retiré
    // des builds release et logcat est lisible par adb.
    if (kDebugMode) {
      final marque = (token != null && token.isNotEmpty) ? 'token' : 'PAS DE TOKEN';
      debugPrint('[API] ${options.method} ${options.path} — $marque');
    }
    handler.next(options);
  }

  /// Le serveur fabrique des URLs d'images absolues du genre
  /// http://localhost:3001/uploads/... (APP_URL du .env). Sur le téléphone d'un
  /// collègue, « localhost » désigne son propre téléphone : les photos seraient
  /// cassées. On remplace donc cet hôte par l'adresse réellement utilisée.
  static const List<String> _hotesLocaux = [
    'http://localhost:3001',
    'http://127.0.0.1:3001',
    'http://10.0.2.2:3001',
  ];

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      final base = ApiService.instance.adresseActuelle;
      if (!_hotesLocaux.contains(base)) {
        response.data = _reecrireHotes(response.data, base);
      }
    } catch (_) {
      // Au pire on laisse la réponse telle quelle.
    }
    handler.next(response);
  }

  static dynamic _reecrireHotes(dynamic v, String base) {
    if (v is String) {
      for (final h in _hotesLocaux) {
        if (v.startsWith(h)) return base + v.substring(h.length);
      }
      return v;
    }
    if (v is List) {
      for (var i = 0; i < v.length; i++) {
        v[i] = _reecrireHotes(v[i], base);
      }
      return v;
    }
    if (v is Map) {
      for (final k in v.keys.toList()) {
        v[k] = _reecrireHotes(v[k], base);
      }
      return v;
    }
    return v;
  }

  /// Marque une requête déjà rejouée après renouvellement du jeton : si elle
  /// reçoit encore un 401, on s'arrête (pas de boucle).
  static const String _cleDejaRejouee = 'asoukaa_deja_rejouee';

  /// Rejoue la requête d'origine avec le jeton qui vient d'être renouvelé
  /// (l'en-tête Authorization est recalculé par onRequest).
  static Future<Response<dynamic>> _rejouer(RequestOptions o) {
    dynamic data = o.data;
    final headers = Map<String, dynamic>.from(o.headers);
    headers.remove('Authorization');
    headers.remove('authorization');
    if (data is FormData) {
      // Un FormData déjà envoyé ne peut pas être renvoyé tel quel : on en
      // fabrique une copie neuve (nouvelle frontière multipart).
      data = data.clone();
      headers.removeWhere((k, _) {
        final kk = k.toLowerCase();
        return kk == 'content-type' || kk == 'content-length';
      });
    }
    return ApiService.instance.client.request<dynamic>(
      o.path,
      data: data,
      queryParameters: o.queryParameters,
      cancelToken: o.cancelToken,
      onSendProgress: o.onSendProgress,
      onReceiveProgress: o.onReceiveProgress,
      options: Options(
        method: o.method,
        headers: headers,
        responseType: o.responseType,
        followRedirects: o.followRedirects,
        validateStatus: o.validateStatus,
        sendTimeout: o.sendTimeout,
        receiveTimeout: o.receiveTimeout,
        extra: {...o.extra, _cleDejaRejouee: true},
      ),
    );
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (kDebugMode) {
      debugPrint(
        '[API] Erreur type=${err.type.name} '
        'status=${err.response?.statusCode} '
        'path=${err.requestOptions.path} '
        'msg=${err.message} '
        'error=${err.error}',
      );
    }

    if (err.response?.statusCode == 401 &&
        !_estRouteAuthPublique(err.requestOptions.path)) {
      final opts = err.requestOptions;

      // Déjà rejouée une fois et toujours 401 : la session est perdue.
      if (opts.extra[_cleDejaRejouee] == true) {
        _terminerSessionExpiree();
        handler.next(err);
        return;
      }

      // Pas de jeton de rafraîchissement (compte admin de test, session
      // très ancienne...) : comportement d'origine, retour à la connexion.
      String? refresh;
      try {
        refresh = await TokenStorageService.instance.getRefreshToken();
      } catch (_) {}
      if (refresh == null || refresh.isEmpty) {
        _terminerSessionExpiree();
        handler.next(err);
        return;
      }

      // Une requête partie avant un renouvellement déjà réussi porte encore
      // l'ancien jeton : inutile de renouveler à nouveau, on la rejoue.
      final utilise = opts.headers['Authorization']?.toString();
      String? actuel;
      try {
        actuel = await TokenStorageService.instance.getAccessToken();
      } catch (_) {}
      final dejaRenouvele =
          actuel != null && actuel.isNotEmpty && utilise != 'Bearer $actuel';

      if (!dejaRenouvele) {
        final r = await ApiService.rafraichirSession();
        if (r == ResultatRafraichissement.refuse ||
            r == ResultatRafraichissement.aucunJeton) {
          _terminerSessionExpiree();
          handler.next(err);
          return;
        }
        if (r == ResultatRafraichissement.injoignable) {
          // Réseau / serveur indisponible : on laisse l'erreur remonter à
          // l'écran (« Réessayer ») sans déconnecter l'utilisateur.
          handler.next(err);
          return;
        }
      }

      try {
        final rejouee = await _rejouer(opts);
        handler.resolve(rejouee);
      } on DioException catch (e) {
        handler.next(e);
      } catch (_) {
        handler.next(err);
      }
      return;
    }

    handler.next(err);
  }

  /// Sur ces routes, un 401 signifie « identifiants incorrects » et non
  /// « session expirée » : il ne faut ni purger le stockage ni rediriger.
  static bool _estRouteAuthPublique(String path) {
    const publiques = [
      '/api/v1/auth/login',
      '/api/v1/auth/register',
      '/api/v1/auth/verify-otp',
      '/api/v1/auth/resend-otp',
      '/api/v1/auth/forgot-password',
      '/api/v1/auth/reset-password',
      '/api/v1/auth/admin/login',
      '/api/v1/auth/refresh',
    ];
    return publiques.any(path.contains);
  }

  /// Le serveur a rejeté le token : on purge la session et on renvoie vers la
  /// connexion. Sans cela l'utilisateur reste sur un écran qui échoue en
  /// silence à chaque action.
  void _terminerSessionExpiree() {
    TokenStorageService.instance.clearAll();
    // Ne pas montrer à l'utilisateur suivant l'état du compte précédent.
    DelivererAvailability.instance.reset();
    WishlistService.instance.reset();
    // Plus de sondage de notifications pour un compte déconnecté.
    NotificationService.instance.unsubscribe();

    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    // Un 401 peut arriver sur plusieurs requêtes simultanées : ne pas empiler
    // autant de redirections que de réponses en erreur.
    if (_redirectionEnCours) return;
    _redirectionEnCours = true;
    navigator
        .pushNamedAndRemoveUntil(AppRoutes.signUpLogin, (route) => false)
        .whenComplete(() => _redirectionEnCours = false);

    // Message sur l'écran de connexion (laisse le temps à la page de s'afficher).
    Future.delayed(const Duration(milliseconds: 500), () {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      try {
        AppToast.show(
          ctx,
          message: 'Session expirée, reconnectez-vous',
          type: ToastType.info,
        );
      } catch (_) {}
    });
  }

  static bool _redirectionEnCours = false;
}
