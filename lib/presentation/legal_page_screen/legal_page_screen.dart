import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

enum LegalPageType { security, refund, terms }

class LegalPageScreen extends StatelessWidget {
  final LegalPageType pageType;

  const LegalPageScreen({super.key, required this.pageType});

  String get _title {
    switch (pageType) {
      case LegalPageType.security:
        return 'Sécurité et Confidentialité';
      case LegalPageType.refund:
        return 'Remboursement et Retours';
      case LegalPageType.terms:
        return 'Conditions Générales d\'Utilisation';
    }
  }

  IconData get _icon {
    switch (pageType) {
      case LegalPageType.security:
        return Icons.security_rounded;
      case LegalPageType.refund:
        return Icons.assignment_return_outlined;
      case LegalPageType.terms:
        return Icons.article_outlined;
    }
  }

  Color get _color {
    switch (pageType) {
      case LegalPageType.security:
        return const Color(0xFF3B82F6);
      case LegalPageType.refund:
        return const Color(0xFF10B981);
      case LegalPageType.terms:
        return const Color(0xFFFF6210);
    }
  }

  List<_LegalSection> get _sections {
    switch (pageType) {
      case LegalPageType.security:
        return _securitySections;
      case LegalPageType.refund:
        return _refundSections;
      case LegalPageType.terms:
        return _termsSections;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppTheme.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _title,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _color.withAlpha(15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _color.withAlpha(40)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _color.withAlpha(25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_icon, color: _color, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Asoukaa — Bénin Facile\nDernière mise à jour : Mars 2026',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: AppTheme.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Sections
            ..._sections.map((section) => _buildSection(section)),

            const SizedBox(height: 24),

            // Contact footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contact',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ContactRow(
                    icon: Icons.business_rounded,
                    text: 'Bénin Facile — Asoukaa',
                  ),
                  _ContactRow(
                    icon: Icons.location_on_rounded,
                    text: 'Cotonou, Akpakpa Segbeya Nord, Immeuble Avé Maria',
                  ),
                  _ContactRow(
                    icon: Icons.phone_rounded,
                    text: '+229 0164693637',
                  ),
                  _ContactRow(
                    icon: Icons.email_rounded,
                    text: 'contact@asoukaa.com',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(_LegalSection section) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _color.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    section.number,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            section.content,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Security & Privacy Sections ─────────────────────────────────────────

  static const List<_LegalSection> _securitySections = [
    _LegalSection(
      number: '1',
      title: 'Collecte des données',
      content:
          'Asoukaa, une marque de Bénin Facile (structure légalement enregistrée, siège social : Cotonou, Akpakpa Segbeya Nord, Immeuble Avé Maria), collecte uniquement les données nécessaires au bon fonctionnement de la plateforme : nom, adresse e-mail, numéro de téléphone, adresse de livraison et historique de commandes.',
    ),
    _LegalSection(
      number: '2',
      title: 'Utilisation des données',
      content:
          'Vos données sont utilisées exclusivement pour :\n• Traiter vos commandes et livraisons\n• Vous envoyer des notifications relatives à vos achats\n• Améliorer nos services\n• Vous contacter en cas de besoin lié à votre compte',
    ),
    _LegalSection(
      number: '3',
      title: 'Protection des données',
      content:
          'Toutes les données sont stockées de manière sécurisée via des serveurs chiffrés. Nous ne vendons ni ne partageons vos données personnelles avec des tiers à des fins commerciales.',
    ),
    _LegalSection(
      number: '4',
      title: 'Sécurité des paiements',
      content:
          'Tous les paiements effectués sur Asoukaa sont sécurisés via des protocoles SSL/TLS. Nous ne stockons jamais vos informations bancaires complètes. Les transactions sont traitées par des prestataires de paiement certifiés.',
    ),
    _LegalSection(
      number: '5',
      title: 'Cookies',
      content:
          'Notre application utilise des cookies techniques nécessaires au fonctionnement. Vous pouvez les désactiver dans les paramètres de votre appareil, mais certaines fonctionnalités pourraient être affectées.',
    ),
    _LegalSection(
      number: '6',
      title: 'Vos droits',
      content:
          'Vous avez le droit d\'accéder, de modifier ou de supprimer vos données personnelles à tout moment depuis votre profil ou en nous contactant à contact@asoukaa.com. Toute demande sera traitée dans un délai de 30 jours.',
    ),
    _LegalSection(
      number: '7',
      title: 'Durée de conservation',
      content:
          'Vos données sont conservées pendant la durée de votre relation avec Asoukaa et jusqu\'à 3 ans après la clôture de votre compte, conformément aux obligations légales en vigueur au Bénin.',
    ),
  ];

  // ─── Refund & Returns Sections ────────────────────────────────────────────

  static const List<_LegalSection> _refundSections = [
    _LegalSection(
      number: '1',
      title: 'Conditions de retour',
      content:
          'Vous pouvez retourner un article dans les 7 jours suivant la réception si :\n• L\'article est défectueux ou endommagé à la livraison\n• L\'article reçu ne correspond pas à la description\n• L\'article est dans son état d\'origine, non utilisé et dans son emballage d\'origine',
    ),
    _LegalSection(
      number: '2',
      title: 'Articles non retournables',
      content:
          '• Articles personnalisés ou sur mesure\n• Produits alimentaires et cosmétiques ouverts\n• Articles en promotion marqués "Vente finale"\n• Produits numériques ou téléchargeables',
    ),
    _LegalSection(
      number: '3',
      title: 'Procédure de retour',
      content:
          'a) Ouvrez un ticket de support depuis votre compte (Support et Aide)\nb) Indiquez le numéro de commande et la raison du retour\nc) Notre équipe vous contactera sous 24h pour organiser le retour\nd) Une fois l\'article reçu et vérifié, le remboursement sera traité',
    ),
    _LegalSection(
      number: '4',
      title: 'Délais de remboursement',
      content:
          '• Mobile Money (MTN/Moov/Orange) : 24 à 72 heures\n• Virement bancaire : 3 à 5 jours ouvrables\n• Le remboursement est effectué sur le même moyen de paiement utilisé lors de l\'achat',
    ),
    _LegalSection(
      number: '5',
      title: 'Frais de retour',
      content:
          'Les frais de retour sont à la charge du vendeur si l\'article est défectueux ou ne correspond pas à la description. Dans les autres cas, les frais sont partagés entre l\'acheteur et le vendeur selon accord préalable.',
    ),
    _LegalSection(
      number: '6',
      title: 'Programme Asoukaa Protect',
      content:
          'Asoukaa Protect garantit votre achat. Si vous ne recevez pas votre commande ou si l\'article est significativement différent de la description, nous vous remboursons intégralement, y compris les frais de livraison.',
    ),
    _LegalSection(
      number: '7',
      title: 'Litiges',
      content:
          'En cas de litige non résolu entre acheteur et vendeur, Asoukaa joue le rôle de médiateur. Notre décision finale sera communiquée dans les 5 jours ouvrables. Pour tout litige, contactez-nous à contact@asoukaa.com.',
    ),
  ];

  // ─── Terms & Conditions Sections ─────────────────────────────────────────

  static const List<_LegalSection> _termsSections = [
    _LegalSection(
      number: '1',
      title: 'Présentation',
      content:
          'Asoukaa est une plateforme de commerce en ligne opérée par Bénin Facile, structure légalement enregistrée au Bénin.\n\nSiège social : Cotonou, Akpakpa Segbeya Nord, Immeuble Avé Maria\nContact : +229 0164693637 | contact@asoukaa.com',
    ),
    _LegalSection(
      number: '2',
      title: 'Acceptation des conditions',
      content:
          'En utilisant l\'application Asoukaa, vous acceptez sans réserve les présentes conditions générales d\'utilisation. Si vous n\'acceptez pas ces conditions, veuillez ne pas utiliser notre plateforme.',
    ),
    _LegalSection(
      number: '3',
      title: 'Inscription et compte',
      content:
          '• Vous devez avoir au moins 18 ans pour créer un compte\n• Vous êtes responsable de la confidentialité de vos identifiants\n• Toute activité frauduleuse entraînera la suspension immédiate du compte\n• Un seul compte par personne est autorisé',
    ),
    _LegalSection(
      number: '4',
      title: 'Règles pour les vendeurs',
      content:
          '• Les vendeurs doivent fournir des informations exactes sur leurs produits\n• Les produits illicites, contrefaits ou dangereux sont strictement interdits\n• Asoukaa se réserve le droit de retirer tout produit non conforme\n• Une commission est prélevée sur chaque vente (voir grille tarifaire)\n• Les vendeurs doivent honorer leurs commandes dans les délais annoncés',
    ),
    _LegalSection(
      number: '5',
      title: 'Règles pour les acheteurs',
      content:
          '• Les commandes passées sont fermes et définitives sauf cas de retour éligible\n• Le paiement doit être effectué au moment de la commande\n• Toute tentative de fraude sera signalée aux autorités compétentes\n• Les acheteurs doivent fournir une adresse de livraison exacte',
    ),
    _LegalSection(
      number: '6',
      title: 'Responsabilités',
      content:
          'Asoukaa agit en tant qu\'intermédiaire entre acheteurs et vendeurs. Nous ne sommes pas responsables des produits vendus par les vendeurs tiers, mais nous nous engageons à protéger les acheteurs via notre programme Asoukaa Protect.',
    ),
    _LegalSection(
      number: '7',
      title: 'Propriété intellectuelle',
      content:
          'Tout le contenu de l\'application (logo, design, textes, images) est la propriété exclusive de Bénin Facile et est protégé par les lois sur la propriété intellectuelle. Toute reproduction non autorisée est interdite.',
    ),
    _LegalSection(
      number: '8',
      title: 'Modifications',
      content:
          'Asoukaa se réserve le droit de modifier ces conditions à tout moment. Les utilisateurs seront notifiés de tout changement majeur via l\'application. La poursuite de l\'utilisation après notification vaut acceptation des nouvelles conditions.',
    ),
    _LegalSection(
      number: '9',
      title: 'Droit applicable',
      content:
          'Les présentes conditions sont régies par le droit béninois. Tout litige sera soumis aux tribunaux compétents de Cotonou, Bénin. En cas de litige transfrontalier, les parties s\'engagent à rechercher une solution amiable avant toute procédure judiciaire.',
    ),
  ];
}

class _LegalSection {
  final String number;
  final String title;
  final String content;

  const _LegalSection({
    required this.number,
    required this.title,
    required this.content,
  });
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ContactRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
