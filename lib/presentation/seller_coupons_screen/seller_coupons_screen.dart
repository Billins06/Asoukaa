import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../services/coupon_service.dart';
import '../../utils/lecture_json.dart';

// Écran « Mes coupons » de l'espace vendeur.
//
// Le vendeur y voit la liste de ses coupons, en crée de nouveaux et peut
// désactiver ceux dont il ne veut plus. Règles appliquées par le SERVEUR (cet
// écran ne fait que les refléter) :
//  - un coupon créé ici ne vaut QUE sur les produits de la boutique du
//    vendeur (le serveur impose la boutique : l'appli n'envoie pas de
//    vendorId) ;
//  - la boutique doit être approuvée pour créer ou désactiver un coupon ;
//  - le code est mis en majuscules par le serveur et doit être unique ;
//  - un client ne peut utiliser un même coupon qu'une seule fois ;
//  - un coupon désactivé ne peut pas être réactivé par le vendeur.

// ─── Aides d'affichage ───────────────────────────────────────────────────

/// 2000 -> « 2 000 » ; 12.5 -> « 12,50 ».
String _formatNombre(double v) {
  if (!v.isFinite) return '0';
  final entier = v == v.roundToDouble();
  final texte = entier ? v.round().toString() : v.toStringAsFixed(2);
  final parts = texte.split('.');
  final s = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  if (parts.length > 1) buf.write(',${parts[1]}');
  return buf.toString();
}

String _formatDate(DateTime d) {
  final jj = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$jj/$mm/${d.year}';
}

String _libelleRemise(VendorCoupon c) => c.estPourcentage
    ? '${_formatNombre(c.value)} % de réduction'
    : '${_formatNombre(c.value)} FCFA de réduction';

String _libelleStatut(CouponStatut s) => switch (s) {
  CouponStatut.actif => 'Actif',
  CouponStatut.desactive => 'Désactivé',
  CouponStatut.expire => 'Expiré',
  CouponStatut.epuise => 'Épuisé',
};

Color _couleurStatut(CouponStatut s) => switch (s) {
  CouponStatut.actif => AppTheme.success,
  CouponStatut.desactive => AppTheme.muted,
  CouponStatut.expire => AppTheme.error,
  CouponStatut.epuise => AppTheme.warning,
};

String? _explicationStatut(CouponStatut s) => switch (s) {
  CouponStatut.actif => null,
  CouponStatut.desactive => 'Ce coupon ne peut plus être utilisé.',
  CouponStatut.expire => "La date d'expiration est dépassée.",
  CouponStatut.epuise => 'Toutes les utilisations ont été consommées.',
};

InputDecoration _champDeco(
  String label, {
  String? hint,
  String? suffixText,
  Widget? suffixIcon,
  String? helper,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 2,
    suffixText: suffixText,
    suffixIcon: suffixIcon,
    labelStyle: GoogleFonts.outfit(fontSize: 13),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );
}

// ─── Écran ───────────────────────────────────────────────────────────────

class SellerCouponsScreen extends StatefulWidget {
  const SellerCouponsScreen({super.key});

  @override
  State<SellerCouponsScreen> createState() => _SellerCouponsScreenState();
}

class _SellerCouponsScreenState extends State<SellerCouponsScreen> {
  static const int _taillePage = 20;

  final List<VendorCoupon> _coupons = [];
  bool _isLoading = true;
  String? _loadError;
  bool _isLoadingMore = false;
  int _page = 1;
  int _pages = 1;
  int _total = 0;

  // Numéro de la dernière demande de liste : une réponse plus ancienne
  // (arrivée en retard) est ignorée.
  int _requete = 0;

  // Coupons dont la désactivation est en cours (évite le double clic).
  final Set<String> _desactivationEnCours = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Recharge la liste depuis la première page. [silencieux] : on garde la
  /// liste à l'écran pendant le rechargement (tirer pour actualiser, ou
  /// après une création).
  Future<void> _load({bool silencieux = false}) async {
    final numero = ++_requete;
    if (!silencieux) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    final res = await CouponService.instance.getMesCoupons(
      page: 1,
      limit: _taillePage,
    );
    if (!mounted || numero != _requete) return;

    final donnees = res.data;
    if (res.ok && donnees != null) {
      setState(() {
        _coupons
          ..clear()
          ..addAll(donnees.items);
        _page = donnees.page;
        _pages = donnees.pages;
        _total = donnees.total;
        _isLoading = false;
        _isLoadingMore = false;
        _loadError = null;
      });
      return;
    }

    final message = res.error ?? 'Impossible de charger vos coupons.';
    if (silencieux && _coupons.isNotEmpty) {
      setState(() => _isLoading = false);
      AppToast.show(context, message: message, type: ToastType.error);
    } else {
      setState(() {
        _isLoading = false;
        _loadError = message;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _isLoading || _page >= _pages) return;
    final numero = _requete;
    setState(() => _isLoadingMore = true);
    final res = await CouponService.instance.getMesCoupons(
      page: _page + 1,
      limit: _taillePage,
    );
    if (!mounted) return;
    if (numero != _requete) {
      // Une actualisation a eu lieu entre-temps : cette page est périmée.
      setState(() => _isLoadingMore = false);
      return;
    }

    final donnees = res.data;
    if (res.ok && donnees != null) {
      final connus = _coupons.map((c) => c.id).toSet();
      setState(() {
        _coupons.addAll(donnees.items.where((c) => !connus.contains(c.id)));
        _page = donnees.page;
        _pages = donnees.pages;
        _total = donnees.total;
        _isLoadingMore = false;
      });
    } else {
      setState(() => _isLoadingMore = false);
      AppToast.show(
        context,
        message: res.error ?? 'Impossible de charger la suite.',
        type: ToastType.error,
      );
    }
  }

  // ─── Création ──────────────────────────────────────────────────────────

  Future<void> _ouvrirCreation() async {
    final cree = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => const _CreationCouponSheet(),
    );
    if (cree == true && mounted) {
      AppToast.show(
        context,
        message: 'Coupon créé. Vos clients peuvent déjà l\'utiliser.',
        type: ToastType.success,
        duration: const Duration(seconds: 4),
      );
      _load(silencieux: true);
    }
  }

  // ─── Désactivation ─────────────────────────────────────────────────────

  Future<void> _confirmerDesactivation(VendorCoupon c) async {
    if (_desactivationEnCours.contains(c.id)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Désactiver ce coupon ?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        content: Text(
          'Le code ${c.code} ne pourra plus être utilisé par vos clients. '
          'Vous ne pourrez pas le réactiver vous-même : il faudra créer un '
          'nouveau coupon.',
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              'Annuler',
              style: GoogleFonts.outfit(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              'Désactiver',
              style: GoogleFonts.outfit(
                color: AppTheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _desactiver(c);
  }

  Future<void> _desactiver(VendorCoupon c) async {
    if (_desactivationEnCours.contains(c.id)) return;
    setState(() => _desactivationEnCours.add(c.id));
    final res = await CouponService.instance.desactiver(c.id);
    if (!mounted) return;
    setState(() {
      _desactivationEnCours.remove(c.id);
      if (res.ok) {
        final i = _coupons.indexWhere((x) => x.id == c.id);
        if (i != -1) _coupons[i] = _coupons[i].copyWith(isActive: false);
      }
    });
    AppToast.show(
      context,
      message: res.ok
          ? (res.data ?? 'Coupon désactivé avec succès')
          : (res.error ?? 'Impossible de désactiver le coupon.'),
      type: res.ok ? ToastType.success : ToastType.error,
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _copierCode(VendorCoupon c) async {
    await Clipboard.setData(ClipboardData(text: c.code));
    if (!mounted) return;
    AppToast.show(
      context,
      message: 'Code ${c.code} copié',
      type: ToastType.info,
      duration: const Duration(seconds: 2),
    );
  }

  // ─── Interface ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Mes coupons',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ouvrirCreation,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Nouveau coupon',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (_loadError != null) return _buildError();
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () => _load(silencieux: true),
      child: _coupons.isEmpty ? _buildVide() : _buildListe(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 52, color: AppTheme.muted),
            const SizedBox(height: 12),
            Text(
              _loadError ?? '',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
              ),
              child: Text(
                'Réessayer',
                style: GoogleFonts.outfit(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVide() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 96),
      children: [
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryMuted,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.local_offer_outlined,
              size: 40,
              color: AppTheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Aucun coupon pour le moment',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Créez un code promo pour offrir une réduction sur vos produits '
          'et attirer plus d\'acheteurs.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton.icon(
            onPressed: _ouvrirCreation,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(
              'Créer mon premier coupon',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListe() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _coupons.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) return _buildEntete();
        if (index == _coupons.length + 1) return _buildPiedListe();
        return _buildCouponCard(_coupons[index - 1]);
      },
    );
  }

  Widget _buildEntete() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primaryMuted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: AppTheme.primary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$_total coupon${_total > 1 ? 's' : ''} · Vos coupons ne '
                's\'appliquent qu\'aux produits de votre boutique, et chaque '
                'client ne peut les utiliser qu\'une fois.',
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPiedListe() {
    if (_page >= _pages) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Center(
        child: OutlinedButton(
          onPressed: _isLoadingMore ? null : _loadMore,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primary,
            side: const BorderSide(color: AppTheme.primary),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: _isLoadingMore
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                )
              : Text(
                  'Charger plus',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }

  Widget _ligneInfo(IconData icone, String texte) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 15, color: AppTheme.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texte,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCouponCard(VendorCoupon c) {
    final statut = c.statut;
    final actif = statut == CouponStatut.actif;
    final couleur = _couleurStatut(statut);
    final explication = _explicationStatut(statut);
    final enCours = _desactivationEnCours.contains(c.id);
    final max = c.maxUses;
    final minimum = c.minOrderAmount;
    final exp = c.expiresAt;

    final String texteUtilisation = max != null
        ? 'Utilisé ${c.usedCount} / $max fois'
        : 'Utilisé ${c.usedCount} fois (sans limite)';
    final String texteExpiration = exp == null
        ? 'Sans date d\'expiration'
        : (DateTime.now().isAfter(exp)
              ? 'Expiré le ${_formatDate(exp)}'
              : 'Expire le ${_formatDate(exp)}');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: actif ? AppTheme.surface : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: actif ? AppTheme.outlineVariant : couleur.withAlpha(110),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: actif ? AppTheme.textPrimary : AppTheme.muted,
                    decoration: actif ? null : TextDecoration.lineThrough,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Copier le code',
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: AppTheme.muted,
                  ),
                  onPressed: () => _copierCode(c),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: couleur.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _libelleStatut(statut),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: couleur,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _libelleRemise(c),
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: actif ? AppTheme.primary : AppTheme.muted,
            ),
          ),
          if (explication != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: couleur.withAlpha(22),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                explication,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: couleur,
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          _ligneInfo(
            Icons.shopping_bag_outlined,
            minimum != null
                ? 'Achat minimum : ${_formatNombre(minimum)} FCFA'
                : 'Aucun achat minimum',
          ),
          _ligneInfo(Icons.people_outline_rounded, texteUtilisation),
          _ligneInfo(Icons.event_outlined, texteExpiration),
          if (c.isActive) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: enCours ? null : () => _confirmerDesactivation(c),
                icon: enCours
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.error,
                        ),
                      )
                    : const Icon(Icons.block_rounded, size: 16),
                label: Text(
                  'Désactiver',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: BorderSide(color: AppTheme.error.withAlpha(120)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Formulaire de création (feuille du bas) ─────────────────────────────

class _CreationCouponSheet extends StatefulWidget {
  const _CreationCouponSheet();

  @override
  State<_CreationCouponSheet> createState() => _CreationCouponSheetState();
}

class _CreationCouponSheetState extends State<_CreationCouponSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _valeurCtrl = TextEditingController();
  final TextEditingController _minCtrl = TextEditingController();
  final TextEditingController _maxUsesCtrl = TextEditingController();

  String _type = kCouponTypePourcentage;

  // Jour d'expiration choisi (le coupon vaut jusqu'à 23 h 59 de ce jour).
  DateTime? _expiration;

  bool _envoi = false;
  String? _erreurServeur;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valeurCtrl.dispose();
    _minCtrl.dispose();
    _maxUsesCtrl.dispose();
    super.dispose();
  }

  bool get _estPourcentage => _type == kCouponTypePourcentage;

  String? _validerCode(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Saisissez un code (ex. PROMO10).';
    if (t.length > 50) return '50 caractères maximum.';
    return null;
  }

  // Vrai si le texte ne contient que des chiffres (montant entier en FCFA).
  bool _estEntier(String t) => RegExp(r'^[0-9]+$').hasMatch(t.trim());

  String? _validerValeur(String? v) {
    // Montant fixe : entier obligatoire (« 1.000 » serait lu comme 1 FCFA).
    if (!_estPourcentage &&
        (v ?? '').trim().isNotEmpty &&
        !_estEntier(v ?? '')) {
      return 'Montant en FCFA, sans point ni virgule (ex. 1000).';
    }
    final n = lireDoubleOuNull(v);
    if (n == null || !n.isFinite || n <= 0) {
      return 'Saisissez une valeur supérieure à 0.';
    }
    if (_estPourcentage && n > 100) {
      return 'Un pourcentage ne peut pas dépasser 100.';
    }
    return null;
  }

  String? _validerMinimum(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    if (!_estEntier(t)) {
      return 'Montant en FCFA, sans point ni virgule (ex. 5000).';
    }
    final n = lireDoubleOuNull(t);
    if (n == null || !n.isFinite || n <= 0) {
      return 'Saisissez un montant supérieur à 0, ou laissez vide.';
    }
    return null;
  }

  String? _validerMaxUses(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    if (n == null || n < 1) {
      return 'Saisissez un nombre entier d\'au moins 1, ou laissez vide.';
    }
    return null;
  }

  Future<void> _choisirDate() async {
    FocusScope.of(context).unfocus();
    final maintenant = DateTime.now();
    final aujourdhui = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
    );
    final actuelle = _expiration;
    final initiale = (actuelle != null && !actuelle.isBefore(aujourdhui))
        ? actuelle
        : aujourdhui.add(const Duration(days: 30));
    final choisi = await showDatePicker(
      context: context,
      initialDate: initiale,
      firstDate: aujourdhui,
      lastDate: aujourdhui.add(const Duration(days: 365 * 5)),
      helpText: 'Dernier jour de validité',
    );
    if (choisi != null && mounted) {
      setState(() {
        _expiration = DateTime(choisi.year, choisi.month, choisi.day);
        _erreurServeur = null;
      });
    }
  }

  Future<void> _envoyer() async {
    if (_envoi) return;
    FocusScope.of(context).unfocus();
    setState(() => _erreurServeur = null);

    final formulaireValide = _formKey.currentState?.validate() ?? false;
    if (!formulaireValide) return;

    // Date d'expiration : fin du jour choisi, obligatoirement dans le futur.
    final jour = _expiration;
    final DateTime? fin = jour == null
        ? null
        : DateTime(jour.year, jour.month, jour.day, 23, 59, 59);
    if (fin != null && !fin.isAfter(DateTime.now())) {
      setState(() {
        _erreurServeur = 'La date d\'expiration doit être dans le futur.';
      });
      return;
    }

    final valeur = lireDouble(_valeurCtrl.text);
    final minTexte = _minCtrl.text.trim();
    final maxTexte = _maxUsesCtrl.text.trim();

    setState(() => _envoi = true);
    final res = await CouponService.instance.creer(
      code: _codeCtrl.text.trim(),
      type: _type,
      value: valeur,
      minOrderAmount: minTexte.isEmpty ? null : lireDoubleOuNull(minTexte),
      maxUses: maxTexte.isEmpty ? null : int.tryParse(maxTexte),
      expiresAt: fin,
    );
    if (!mounted) return;
    if (res.ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _envoi = false;
        _erreurServeur = res.error ?? 'Impossible de créer le coupon.';
      });
    }
  }

  // Changement de type en cours de saisie : si on passe à « montant fixe »
  // avec une valeur décimale déjà saisie (ex. « 10,5 » en pourcentage), on
  // vide le champ plutôt que de la réinterpréter (« 1.000 » = 1 FCFA).
  void _changerType(String valeur) {
    setState(() {
      _type = valeur;
      if (valeur == kCouponTypePrixFixe &&
          RegExp(r'[.,]').hasMatch(_valeurCtrl.text)) {
        _valeurCtrl.clear();
      }
    });
  }

  Widget _chipType(String valeur, String libelle) {
    final selectionne = _type == valeur;
    return ChoiceChip(
      label: Text(
        libelle,
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selectionne ? AppTheme.primary : AppTheme.textSecondary,
        ),
      ),
      selected: selectionne,
      showCheckmark: false,
      selectedColor: AppTheme.primaryMuted,
      backgroundColor: AppTheme.surfaceVariant,
      side: BorderSide(
        color: selectionne ? AppTheme.primary : AppTheme.outline,
      ),
      onSelected: _envoi ? null : (_) => _changerType(valeur),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jour = _expiration;
    return PopScope(
      canPop: !_envoi,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Nouveau coupon',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fermer',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _envoi ? null : () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ce coupon ne s\'appliquera qu\'aux produits de votre '
                    'boutique.',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _codeCtrl,
                    enabled: !_envoi,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9_-]'),
                      ),
                      LengthLimitingTextInputFormatter(50),
                    ],
                    validator: _validerCode,
                    style: GoogleFonts.outfit(fontSize: 15),
                    decoration: _champDeco(
                      'Code du coupon',
                      hint: 'PROMO10',
                      helper:
                          'Lettres, chiffres, - et _ (enregistré en MAJUSCULES).',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Type de réduction',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _chipType(kCouponTypePourcentage, 'Pourcentage (%)'),
                      _chipType(kCouponTypePrixFixe, 'Montant fixe (FCFA)'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _valeurCtrl,
                    enabled: !_envoi,
                    keyboardType: _estPourcentage
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
                    inputFormatters: [
                      // Pourcentage : décimale permise. Montant fixe : chiffres seuls.
                      if (_estPourcentage)
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                      else
                        FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(12),
                    ],
                    validator: _validerValeur,
                    style: GoogleFonts.outfit(fontSize: 15),
                    decoration: _champDeco(
                      _estPourcentage
                          ? 'Pourcentage de réduction'
                          : 'Montant de la réduction',
                      hint: _estPourcentage ? 'ex. 10' : 'ex. 1000',
                      helper: _estPourcentage
                          ? null
                          : 'Montant en FCFA, sans point ni virgule',
                      suffixText: _estPourcentage ? '%' : 'FCFA',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _minCtrl,
                    enabled: !_envoi,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(12),
                    ],
                    validator: _validerMinimum,
                    style: GoogleFonts.outfit(fontSize: 15),
                    decoration: _champDeco(
                      'Achat minimum (facultatif)',
                      hint: 'Aucun minimum',
                      helper: 'Montant en FCFA, sans point ni virgule',
                      suffixText: 'FCFA',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _maxUsesCtrl,
                    enabled: !_envoi,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(9),
                    ],
                    validator: _validerMaxUses,
                    style: GoogleFonts.outfit(fontSize: 15),
                    decoration: _champDeco(
                      'Nombre d\'utilisations maximum (facultatif)',
                      hint: 'Illimité',
                    ),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _envoi ? null : _choisirDate,
                    child: InputDecorator(
                      decoration: _champDeco(
                        'Date d\'expiration (facultatif)',
                        suffixIcon: jour == null
                            ? const Icon(Icons.event_rounded)
                            : IconButton(
                                tooltip: 'Retirer la date',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: _envoi
                                    ? null
                                    : () => setState(() => _expiration = null),
                              ),
                      ),
                      child: Text(
                        jour == null
                            ? 'Sans date d\'expiration'
                            : 'Valable jusqu\'au ${_formatDate(jour)} (23 h 59)',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          color: jour == null
                              ? AppTheme.muted
                              : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (_erreurServeur != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppTheme.error,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _erreurServeur ?? '',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: AppTheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _envoi ? null : _envoyer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppTheme.primary.withAlpha(140),
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _envoi
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Créer le coupon',
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
