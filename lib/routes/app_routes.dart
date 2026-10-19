import 'package:flutter/material.dart';

import '../main.dart';
import '../presentation/home_screen/home_screen.dart';
import '../presentation/product_detail_screen/product_detail_screen.dart';
import '../presentation/sign_up_login_screen/sign_up_login_screen.dart';
import '../presentation/buyer_dashboard_screen/buyer_dashboard_screen.dart';
import '../presentation/seller_dashboard_screen/seller_dashboard_screen.dart';
import '../presentation/deliverer_dashboard_screen/deliverer_dashboard_screen.dart';
import '../presentation/admin_dashboard_screen/admin_dashboard_screen.dart';
import '../presentation/chat_screen/chat_screen.dart';
import '../presentation/cart_screen/cart_screen.dart';
import '../presentation/checkout_screen/checkout_screen.dart';
import '../presentation/order_confirmation_screen/order_confirmation_screen.dart';
import '../presentation/order_tracking_screen/order_tracking_screen.dart';
import '../presentation/publier_produit_screen/publier_produit_screen.dart';
import '../presentation/boutique_vendeur_screen/boutique_vendeur_screen.dart';
import '../presentation/search_results_screen/search_results_screen.dart';
import '../presentation/delivery_proof_screen/delivery_proof_screen.dart';
import '../presentation/buyer_profile_screen/buyer_profile_screen.dart';
import '../presentation/seller_profile_screen/seller_profile_screen.dart';
import '../presentation/deliverer_profile_screen/deliverer_profile_screen.dart';
import '../presentation/onboarding_screen/onboarding_screen.dart';
import '../presentation/notifications_screen/notifications_screen.dart';
import '../presentation/import_assiste_screen/import_assiste_screen.dart';
import '../presentation/feexpay_result_screen/feexpay_result_screen.dart';
import '../presentation/categories_screen/categories_screen.dart';
import '../presentation/wishlist_screen/wishlist_screen.dart';
import '../presentation/followed_shops_screen/followed_shops_screen.dart';
import '../presentation/delivery_request_screen/delivery_request_screen.dart';
import '../presentation/become_agent_screen/become_agent_screen.dart';
import '../presentation/delivery_request_screen/my_express_deliveries_screen.dart';
import '../presentation/support_help_screen/support_help_screen.dart';
import '../presentation/support_help_screen/ticket_detail_screen.dart';
import '../presentation/legal_page_screen/legal_page_screen.dart';
import '../presentation/refund_request_screen/refund_request_screen.dart';
import '../presentation/chat_screen/conversations_inbox_screen.dart';
import 'package:image_picker/image_picker.dart';

import '../presentation/otp_verification_screen/otp_verification_screen.dart';
import '../presentation/reset_password_screen/reset_password_screen.dart';
import '../presentation/vendor_reapply_screen/vendor_reapply_screen.dart';
import '../presentation/agent_reapply_screen/agent_reapply_screen.dart';
import '../presentation/vendor_complete_documents_screen/vendor_complete_documents_screen.dart';
import '../presentation/vendor_withdrawals_screen/vendor_withdrawals_screen.dart';
import '../presentation/seller_coupons_screen/seller_coupons_screen.dart';
import '../presentation/category_products_screen/category_products_screen.dart';
import '../presentation/shops_list_screen/shops_list_screen.dart';
import '../presentation/agent_complete_documents_screen/agent_complete_documents_screen.dart';
import '../presentation/change_email_screen/change_email_screen.dart';
import '../presentation/become_vendor_screen/become_vendor_screen.dart';
import '../presentation/all_products_screen/all_products_screen.dart';
import '../presentation/library_screen/library_screen.dart';

class AppRoutes {
  static const String initial = '/';
  static const String signUpLogin = '/sign-up-login-screen';
  static const String home = '/home-screen';
  static const String productDetail = '/product-detail-screen';
  static const String buyerDashboard = '/buyer-dashboard-screen';
  static const String sellerDashboard = '/seller-dashboard-screen';
  static const String delivererDashboard = '/deliverer-dashboard-screen';
  static const String adminDashboard = '/admin-dashboard-screen';
  static const String chat = '/chat-screen';
  static const String cart = '/cart-screen';
  static const String checkout = '/checkout-screen';
  static const String orderConfirmation = '/order-confirmation-screen';
  static const String orderTracking = '/order-tracking-screen';
  static const String publierProduit = '/publier-produit-screen';
  static const String boutiqueVendeur = '/boutique-vendeur-screen';
  static const String searchResults = '/search-results-screen';
  static const String deliveryProof = '/delivery-proof-screen';
  static const String buyerProfile = '/buyer-profile-screen';
  static const String sellerProfile = '/seller-profile-screen';
  static const String delivererProfile = '/deliverer-profile-screen';
  static const String onboarding = '/onboarding-screen';
  static const String notifications = '/notifications-screen';
  static const String importAssiste = '/import-assiste-screen';
  static const String feexpaySuccess = '/feexpay-success';
  static const String feexpayError = '/feexpay-error';
  static const String categories = '/categories-screen';
  static const String wishlist = '/wishlist-screen';
  static const String followedShops = '/followed-shops-screen';
  static const String deliveryRequest = '/delivery-request-screen';
  static const String myExpressDeliveries = '/my-express-deliveries-screen';
  static const String supportHelp = '/support-help-screen';
  // Detail d'un ticket de support. Argument : id du ticket (String) ou Map
  // { 'ticketId': String, 'fromSupport': bool }.
  static const String ticketDetail = '/ticket-detail-screen';
  static const String legalSecurity = '/legal-security-screen';
  static const String legalRefund = '/legal-refund-screen';
  static const String legalTerms = '/legal-terms-screen';
  static const String refundRequest = '/refund-request-screen';
  static const String conversationsInbox = '/conversations-inbox';
  static const String otpVerification = '/otp-verification-screen';
  static const String resetPassword = '/reset-password-screen';
  static const String vendorReapply = '/vendor-reapply-screen';
  static const String agentReapply = '/agent-reapply-screen';
  static const String vendorCompleteDocuments = '/vendor-complete-documents-screen';
  static const String vendorWithdrawals = '/vendor-withdrawals-screen';
  // « Mes coupons » : le vendeur crée, liste et désactive ses codes promo.
  static const String sellerCoupons = '/seller-coupons-screen';
  // Page G : produits d'une sous-catégorie, d'un rayon de la Vitrine ou
  // d'une catégorie sans sous-catégorie. Arguments : Map (voir
  // CategoryProductsScreen).
  static const String categoryProducts = '/category-products-screen';
  // Page H : annuaire de toutes les boutiques.
  static const String shopsList = '/shops-list-screen';
  static const String agentCompleteDocuments = '/agent-complete-documents-screen';
  // Changement d'e-mail (client, vendeur, livreur). Argument : String (e-mail actuel).
  // Résultat : String (nouvelle adresse) si le changement a réussi.
  static const String changeEmail = '/change-email-screen';
  // Première demande vendeur d'un compte déjà connecté. Résultat : true si envoyée.
  static const String becomeVendor = '/become-vendor-screen';
  static const String becomeAgent = '/become-agent-screen';
  // Liste complète des produits actifs (par pages).
  static const String allProducts = '/all-products-screen';
  // « Ma Bibliothèque » : livres numériques achetés (téléchargement PDF).
  static const String library = '/library-screen';

  static Map<String, WidgetBuilder> routes = {
    initial: (context) => const AuthGate(),
    signUpLogin: (context) => const SignUpLoginScreen(),
    home: (context) => const HomeScreen(),
    buyerDashboard: (context) => const BuyerDashboardScreen(),
    sellerDashboard: (context) => const SellerDashboardScreen(),
    delivererDashboard: (context) => const DelivererDashboardScreen(),
    adminDashboard: (context) => const AdminDashboardScreen(),
    cart: (context) => const CartScreen(),
    checkout: (context) => const CheckoutScreen(),
    orderConfirmation: (context) => const OrderConfirmationScreen(),
    orderTracking: (context) => const OrderTrackingScreen(),
    publierProduit: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      return PublierProduitScreen(
        editProduct: args is Map<String, dynamic> ? args : null,
      );
    },
    buyerProfile: (context) => const BuyerProfileScreen(),
    sellerProfile: (context) => const SellerProfileScreen(),
    delivererProfile: (context) => const DelivererProfileScreen(),
    vendorReapply: (context) => const VendorReapplyScreen(),
    agentReapply: (context) => const AgentReapplyScreen(),
    vendorCompleteDocuments: (context) => const VendorCompleteDocumentsScreen(),
    vendorWithdrawals: (context) => const VendorWithdrawalsScreen(),
    sellerCoupons: (context) => const SellerCouponsScreen(),
    agentCompleteDocuments: (context) => const AgentCompleteDocumentsScreen(),
    changeEmail: (context) {
      final a = ModalRoute.of(context)?.settings.arguments;
      return ChangeEmailScreen(currentEmail: a is String ? a : '');
    },
    becomeVendor: (context) => const BecomeVendorScreen(),
    becomeAgent: (context) => const BecomeAgentScreen(),
    allProducts: (context) => const AllProductsScreen(),
    onboarding: (context) => const OnboardingScreen(),
    notifications: (context) => const NotificationsScreen(),
    importAssiste: (context) => const ImportAssisteScreen(),
    feexpaySuccess: (context) => const FeexpayResultScreen(success: true),
    feexpayError: (context) => const FeexpayResultScreen(success: false),
    // L'argument (nom/slug/id de catégorie) doit être lu ici : une route
    // présente dans cette table ne passe jamais par onGenerateRoute.
    categories: (context) {
      final a = ModalRoute.of(context)?.settings.arguments;
      return CategoriesScreen(initialCategory: a is String ? a : null);
    },
    wishlist: (context) => const WishlistScreen(),
    library: (context) => const LibraryScreen(),
    followedShops: (context) => const FollowedShopsScreen(),
    deliveryRequest: (context) => const DeliveryRequestScreen(),
    myExpressDeliveries: (context) => const MyExpressDeliveriesScreen(),
    supportHelp: (context) => const SupportHelpScreen(),
    ticketDetail: (context) {
      final a = ModalRoute.of(context)?.settings.arguments;
      return TicketDetailScreen(
        ticketId: TicketDetailScreen.idFromArguments(a),
        fromSupport: TicketDetailScreen.fromSupportArguments(a),
      );
    },
    legalSecurity: (context) =>
        const LegalPageScreen(pageType: LegalPageType.security),
    legalRefund: (context) =>
        const LegalPageScreen(pageType: LegalPageType.refund),
    legalTerms: (context) =>
        const LegalPageScreen(pageType: LegalPageType.terms),
    conversationsInbox: (context) => const ConversationsInboxScreen(),
    refundRequest: (context) => const RefundRequestScreen(),
  };

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case productDetail:
        final args = settings.arguments as Map<String, dynamic>?;
        return _buildPageRoute(ProductDetailScreen(productData: args));
      case boutiqueVendeur:
        final args = settings.arguments as Map<String, dynamic>?;
        return _buildPageRoute(BoutiqueVendeurScreen(shopData: args));
      case searchResults:
        final args = settings.arguments as String?;
        return _buildPageRoute(SearchResultsScreen(initialQuery: args));
      case deliveryProof:
        final args = settings.arguments as Map<String, dynamic>?;
        return _buildPageRoute(DeliveryProofScreen(deliveryData: args));
      case chat:
        final args = settings.arguments as Map<String, dynamic>?;
        return _buildPageRoute(ChatScreen(chatArgs: args));
      case categoryProducts:
        final args = settings.arguments as Map<String, dynamic>?;
        return _buildPageRoute(CategoryProductsScreen(args: args ?? const {}));
      case shopsList:
        return _buildPageRoute(const ShopsListScreen());
      case categories:
        final args = settings.arguments as String?;
        return _buildPageRoute(CategoriesScreen(initialCategory: args));
      case otpVerification:
        final args = settings.arguments as Map<String, dynamic>?;
        return _buildPageRoute(
          OtpVerificationScreen(
            email: args?['email'] as String? ?? '',
            password: args?['password'] as String? ?? '',
            accountType: args?['accountType'] as String? ?? 'acheteur',
            shopName: args?['shopName'] as String?,
            shopAddress: args?['shopAddress'] as String?,
            categoryIds: (args?['categoryIds'] as List?)?.map((e) => e.toString()).toList(),
            shopDescription: args?['shopDescription'] as String?,
            ville: args?['ville'] as String?,
            quartier: args?['quartier'] as String?,
            preciseAddress: args?['preciseAddress'] as String?,
            vehicleType: args?['vehicleType'] as String?,
            availability: args?['availability'] as String?,
            licensePlate: args?['licensePlate'] as String?,
            idDocumentFile: args?['idDocumentFile'] as XFile?,
            selfieFile: args?['selfieFile'] as XFile?,
            sampleProductFiles: args?['sampleProductFiles'] as List<XFile>?,
            vehiclePhotoFile: args?['vehiclePhotoFile'] as XFile?,
          ),
        );
      case resetPassword:
        final email = settings.arguments as String? ?? '';
        return _buildPageRoute(ResetPasswordScreen(email: email));
      default:
        return _buildPageRoute(const AuthGate());
    }
  }

  static PageRouteBuilder _buildPageRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }
}
