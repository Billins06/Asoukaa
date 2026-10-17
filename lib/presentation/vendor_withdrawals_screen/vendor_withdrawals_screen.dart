import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../services/api_service.dart';
import '../../utils/telephone.dart';

// Écran "Mes gains / Demander un retrait" du vendeur.
//
// Règles métier (fixées par le propriétaire, appliquées côté serveur —
// cet écran ne fait que les refléter) :
//  - le solde retirable ne compte QUE les commandes livrées, commission
//    déduite ;
//  - une seule demande en attente à la fois ;
//  - pas de minimum global, mais l'admin peut fixer un minimum pour CE
//    vendeur (minWithdrawalAmount, 0 = aucun minimum) ;
//  - aucun virement automatique : l'admin paie à la main puis marque la
//    demande comme payée.
class VendorWithdrawalsScreen extends StatefulWidget {
  const VendorWithdrawalsScreen({super.key});

  @override
  State<VendorWithdrawalsScreen> createState() =>
      _VendorWithdrawalsScreenState();
}

class _VendorWithdrawalsScreenState extends State<VendorWithdrawalsScreen> {
  bool _isLoading = true;
  String? _loadError;

  // Soldes renvoyés par GET /vendor-withdrawals/me/balance
  double _soldeDisponible = 0;
  double _gainsBruts = 0;
  double _totalPaye = 0;
  double _totalEnAttente = 0;
  double _minWithdrawal = 0;
  bool _aUneDemandeEnAttente = false;
  int _nbCommandesLivrees = 0;

  List<Map<String, dynamic>> _historique = [];

  // Opérateurs Mobile Money du Bénin. Chaîne libre côté serveur : l'admin
  // paie à la main, la liste peut évoluer sans migration.
  static const List<String> _operateurs = ['MTN', 'Moov', 'Celtiis', 'Wave'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ⚠️ Les colonnes `decimal` de Postgres arrivent en CHAÎNE de caractères
  // (TypeORM les sérialise ainsi) : jamais de cast direct `as num`.
  double _toDouble(dynamic v) => double.tryParse('${v ?? ''}') ?? 0;

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.client.get('/api/v1/vendor-withdrawals/me/balance'),
        ApiService.instance.client.get('/api/v1/vendor-withdrawals/me'),
      ]);

      final balance = results[0].data as Map? ?? {};
      final listData = results[1].data as Map? ?? {};
      final rows = (listData['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (!mounted) return;
      setState(() {
        _soldeDisponible = _toDouble(balance['soldeDisponible']);
        _gainsBruts = _toDouble(balance['gainsBruts']);
        _totalPaye = _toDouble(balance['totalPaye']);
        _totalEnAttente = _toDouble(balance['totalEnAttente']);
        _minWithdrawal = _toDouble(balance['minWithdrawalAmount']);
        _aUneDemandeEnAttente = balance['aUneDemandeEnAttente'] == true;
        _nbCommandesLivrees =
            int.tryParse('${balance['nbCommandesLivrees'] ?? 0}') ?? 0;
        _historique = rows;
        _isLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = _messageFromError(e);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = "Impossible de charger vos gains pour le moment.";
        _isLoading = false;
      });
    }
  }

  // Le serveur renvoie des messages déjà rédigés en français (solde
  // insuffisant, montant sous le minimum, demande déjà en attente...) :
  // on les affiche tels quels plutôt qu'un message générique.
  String _messageFromError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) return msg.join('\n');
    }
    return "Une erreur est survenue. Vérifiez votre connexion.";
  }

  String _formatMontant(double montant) {
    final s = montant.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _formatDate(dynamic raw) {
    final d = DateTime.tryParse('${raw ?? ''}');
    if (d == null) return '';
    final local = d.toLocal();
    final jj = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    return '$jj/$mm/${local.year}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'payé':
        return const Color(0xFF10B981);
      case 'rejeté':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  // ─── Demande de retrait ────────────────────────────────────────────────

  bool get _peutDemander => _soldeDisponible > 0 && !_aUneDemandeEnAttente;

  String? _raisonBlocage() {
    if (_aUneDemandeEnAttente) {
      return "Vous avez déjà une demande en attente. Attendez son traitement avant d'en faire une nouvelle.";
    }
    if (_soldeDisponible <= 0) {
      return "Aucun gain retirable pour le moment. Seules les commandes livrées sont comptées.";
    }
    return null;
  }

  Future<void> _ouvrirFormulaire() async {
    final montantCtrl = TextEditingController();
    final numeroCtrl = TextEditingController();
    String operateur = _operateurs.first;
    bool envoiEnCours = false;

    final envoye = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            Future<void> envoyer() async {
              final montant = double.tryParse(
                montantCtrl.text.trim().replaceAll(',', '.'),
              );
              if (montant == null || montant <= 0) {
                AppToast.show(
                  sheetCtx,
                  message: 'Saisissez un montant valide.',
                  type: ToastType.error,
                );
                return;
              }
              if (montant > _soldeDisponible) {
                AppToast.show(
                  sheetCtx,
                  message:
                      'Montant supérieur à votre solde disponible (${_formatMontant(_soldeDisponible)} FCFA).',
                  type: ToastType.error,
                );
                return;
              }
              if (_minWithdrawal > 0 && montant < _minWithdrawal) {
                AppToast.show(
                  sheetCtx,
                  message:
                      'Le minimum fixé pour votre boutique est de ${_formatMontant(_minWithdrawal)} FCFA.',
                  type: ToastType.error,
                );
                return;
              }
              if (numeroCtrl.text.trim().length < 8) {
                AppToast.show(
                  sheetCtx,
                  message: 'Saisissez un numéro Mobile Money valide.',
                  type: ToastType.error,
                );
                return;
              }

              setSheetState(() => envoiEnCours = true);
              try {
                await ApiService.instance.client.post(
                  '/api/v1/vendor-withdrawals/me',
                  data: {
                    'montant': montant,
                    'paymentMethod': operateur,
                    'mobileNumber': normaliserTelephone(numeroCtrl.text),
                  },
                );
                if (sheetCtx.mounted) Navigator.pop(sheetCtx, true);
              } on DioException catch (e) {
                setSheetState(() => envoiEnCours = false);
                if (sheetCtx.mounted) {
                  AppToast.show(
                    sheetCtx,
                    message: _messageFromError(e),
                    type: ToastType.error,
                    duration: const Duration(seconds: 5),
                  );
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0E0E0),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Demander un retrait',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Solde disponible : ${_formatMontant(_soldeDisponible)} FCFA',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (_minWithdrawal > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Minimum pour votre boutique : ${_formatMontant(_minWithdrawal)} FCFA',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0xFFF59E0B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: montantCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: GoogleFonts.outfit(fontSize: 15),
                      decoration: InputDecoration(
                        labelText: 'Montant à retirer (FCFA)',
                        labelStyle: GoogleFonts.outfit(fontSize: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: operateur,
                      decoration: InputDecoration(
                        labelText: 'Opérateur Mobile Money',
                        labelStyle: GoogleFonts.outfit(fontSize: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: _operateurs
                          .map(
                            (o) => DropdownMenuItem<String>(
                              value: o,
                              child: Text(o, style: GoogleFonts.outfit()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setSheetState(() => operateur = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: numeroCtrl,
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.outfit(fontSize: 15),
                      decoration: InputDecoration(
                        labelText: 'Numéro Mobile Money',
                        hintText: 'Ex : 97000000',
                        labelStyle: GoogleFonts.outfit(fontSize: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Votre demande est traitée manuellement par l'administration. Le virement est effectué sur le numéro indiqué, puis la demande passe en « payé ».",
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: const Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: envoiEnCours ? null : envoyer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: envoiEnCours
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Envoyer la demande',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    montantCtrl.dispose();
    numeroCtrl.dispose();

    if (envoye == true && mounted) {
      AppToast.show(
        context,
        message: 'Demande envoyée. Elle sera traitée par l\'administration.',
        type: ToastType.success,
        duration: const Duration(seconds: 4),
      );
      _loadData();
    }
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
          'Mes gains',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _loadError != null
          ? _buildError()
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildSoldeCard(),
                  const SizedBox(height: 16),
                  _buildDetailsCard(),
                  const SizedBox(height: 24),
                  Text(
                    'Historique des demandes',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_historique.isEmpty)
                    _buildHistoriqueVide()
                  else
                    ..._historique.map(_buildHistoriqueItem),
                ],
              ),
            ),
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
              onPressed: _loadData,
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

  Widget _buildSoldeCard() {
    final blocage = _raisonBlocage();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6210), Color(0xFFFF8A4C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Solde disponible',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Colors.white.withAlpha(220),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_formatMontant(_soldeDisponible)} FCFA',
            style: GoogleFonts.outfit(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sur $_nbCommandesLivrees commande${_nbCommandesLivrees > 1 ? 's' : ''} livrée${_nbCommandesLivrees > 1 ? 's' : ''}',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: Colors.white.withAlpha(200),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _peutDemander ? _ouvrirFormulaire : null,
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: Text(
                'Demander un retrait',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primary,
                disabledBackgroundColor: Colors.white.withAlpha(120),
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          if (blocage != null) ...[
            const SizedBox(height: 10),
            Text(
              blocage,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: Colors.white.withAlpha(230),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          _ligneDetail(
            'Gains cumulés (commandes livrées)',
            _gainsBruts,
            const Color(0xFF1A1A1A),
          ),
          const Divider(height: 20),
          _ligneDetail('Déjà retiré', _totalPaye, const Color(0xFF10B981)),
          const Divider(height: 20),
          _ligneDetail(
            'Demande en attente',
            _totalEnAttente,
            const Color(0xFFF59E0B),
          ),
          if (_minWithdrawal > 0) ...[
            const Divider(height: 20),
            _ligneDetail(
              'Minimum par retrait',
              _minWithdrawal,
              AppTheme.textSecondary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _ligneDetail(String label, double montant, Color couleur) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Text(
          '${_formatMontant(montant)} FCFA',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: couleur,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoriqueVide() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 44, color: AppTheme.muted),
          const SizedBox(height: 10),
          Text(
            "Aucune demande de retrait pour l'instant",
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoriqueItem(Map<String, dynamic> w) {
    final status = '${w['status'] ?? 'en attente'}';
    final couleur = _statusColor(status);
    final note = '${w['noteAdmin'] ?? ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
                  '${_formatMontant(_toDouble(w['montant']))} FCFA',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
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
                  status,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: couleur,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${w['paymentMethod'] ?? ''} · ${w['mobileNumber'] ?? ''}',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Demandé le ${_formatDate(w['createdAt'])}'
            '${w['paidAt'] != null ? ' · Payé le ${_formatDate(w['paidAt'])}' : ''}',
            style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.muted),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: couleur.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                note,
                style: GoogleFonts.outfit(fontSize: 12, color: couleur),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
