import { Injectable, Logger } from '@nestjs/common';
import * as nodemailer from 'nodemailer';
import { ConfigService } from '@nestjs/config';
import { otpTemplate } from './templates/otp.template';
import { passwordResetTemplate } from './templates/password-reset.template';
import { orderConfirmationTemplate, OrderConfirmationData } from './templates/order-confirmation.template';
import { orderStatusUpdateTemplate, OrderStatusUpdateData } from './templates/order-status-update.template';
import { deliveryAssignedTemplate, DeliveryAssignedData } from './templates/delivery-assigned.template';
import { clientWelcomeTemplate } from './templates/client-welcome.template';
import { vendorSubmittedTemplate } from './templates/vendor-submitted.template';
import { agentSubmittedTemplate } from './templates/agent-submitted.template';
import { vendorApprovedTemplate } from './templates/vendor-approved.template';
import { vendorRejectedTemplate } from './templates/vendor-rejected.template';
import { agentApprovedTemplate } from './templates/agent-approved.template';
import { agentRejectedTemplate } from './templates/agent-rejected.template';
import { adminInvitationTemplate } from './templates/admin-invitation.template';
import { vendorBlockedTemplate } from './templates/vendor-blocked.template';
import { vendorUnblockedTemplate } from './templates/vendor-unblocked.template';
import { agentBlockedTemplate } from './templates/agent-blocked.template';
import { agentUnblockedTemplate } from './templates/agent-unblocked.template';
import { independentDeliveryAcceptedTemplate } from './templates/independent-delivery-accepted.template';
import { paymentConfirmedTemplate } from './templates/payment-confirmed.template';
import { refundApprovedTemplate } from './templates/refund-approved.template';
import { refundRejectedTemplate } from './templates/refund-rejected.template';
import { notificationTemplate, NotificationEmailData } from './templates/notification.template';
import { emailChangeCodeTemplate } from './templates/email-change-code.template';
import { emailChangeAlertTemplate, EmailChangeAlertData } from './templates/email-change-alert.template';
import { emailChangeConfirmedTemplate } from './templates/email-change-confirmed.template';
import { emailChangeSecuredTemplate } from './templates/email-change-secured.template';
import { emailChangeCancelledTemplate } from './templates/email-change-cancelled.template';
import { supportTicketReplyTemplate, SupportTicketReplyData } from './templates/support-ticket-reply.template';
import { supportTicketTeamTemplate, SupportTicketTeamData } from './templates/support-ticket-team.template';

@Injectable()
export class MailService {
  private readonly logger = new Logger(MailService.name);
  private transporter: nodemailer.Transporter;

  constructor(private readonly config: ConfigService) {
    this.transporter = nodemailer.createTransport({
      host: this.config.get<string>('MAIL_HOST'),
      // Les variables d'env arrivent en chaînes : "false" serait truthy si on
      // la passait telle quelle — on compare explicitement à 'true'.
      port: Number(this.config.get<string>('MAIL_PORT')),
      secure: String(this.config.get('MAIL_SECURE')) === 'true', // true pour 465
      auth: {
        user: this.config.get<string>('MAIL_USER'),
        pass: this.config.get<string>('MAIL_PASSWORD'),
      },
    });
  }

  // ─── Méthode privée centrale d'envoi ──────────────────────────────────────
  private async send(to: string, subject: string, html: string): Promise<void> {
    try {
      await this.transporter.sendMail({
        from: this.config.get<string>('MAIL_FROM'),
        to,
        subject,
        html,
      });
      this.logger.log(`Mail envoyé → ${to} | ${subject}`);
    } catch (error) {
      // On logue l'erreur mais on ne bloque pas le flux principal
      this.logger.error(`Échec envoi mail → ${to} | ${subject}`, error?.message);
    }
  }

  // ─── Envoi « strict » : l'échec est PROPAGÉ à l'appelant ──────────────────
  // send() avale volontairement les erreurs (un mail raté ne doit pas faire
  // échouer une commande). Mais pour le code de changement d'e-mail, c'est
  // l'inverse : si le code n'est pas parti, l'utilisateur attendrait un
  // message qui ne viendra jamais — l'appelant doit pouvoir le lui dire.
  private async sendStrict(to: string, subject: string, html: string): Promise<void> {
    try {
      await this.transporter.sendMail({
        from: this.config.get<string>('MAIL_FROM'),
        to,
        subject,
        html,
      });
      this.logger.log(`Mail envoyé → ${to} | ${subject}`);
    } catch (error) {
      this.logger.error(`Échec envoi mail → ${to} | ${subject}`, error?.message);
      throw error;
    }
  }

  // ─── OTP Vérification compte ───────────────────────────────────────────────
  async sendOtp(to: string, prenom: string, code: string): Promise<void> {
    await this.send(
      to,
      'Votre code de vérification Asoukaa',
      otpTemplate(prenom, code),
    );
  }

  // ─── Réinitialisation mot de passe ────────────────────────────────────────
  async sendPasswordReset(to: string, prenom: string, code: string): Promise<void> {
    await this.send(
      to,
      'Réinitialisation de votre mot de passe',
      passwordResetTemplate(prenom, code),
    );
  }

  // ─── Confirmation de commande ─────────────────────────────────────────────
  async sendOrderConfirmation(to: string, data: OrderConfirmationData): Promise<void> {
    await this.send(
      to,
      `Commande #${data.orderNumber} confirmée`,
      orderConfirmationTemplate(data),
    );
  }

  // ─── Mise a jour statut commande ──────────────────────────────────────────
  async sendOrderStatusUpdate(to: string, data: OrderStatusUpdateData): Promise<void> {
    await this.send(
      to,
      `Commande #${data.orderNumber} — mise à jour`,
      orderStatusUpdateTemplate(data),
    );
  }

  // ─── Nouvelle livraison affectée (livreur) ────────────────────────────────
  async sendDeliveryAssigned(to: string, data: DeliveryAssignedData): Promise<void> {
    await this.send(
      to,
      '📦 Nouvelle livraison affectée',
      deliveryAssignedTemplate(data),
    );
  }

  // ─── Bienvenue (inscription client confirmée) ──────────────────────────────
  async sendWelcome(to: string, prenom: string): Promise<void> {
    await this.send(
      to,
      'Bienvenue sur Asoukaa !',
      clientWelcomeTemplate(prenom),
    );
  }

  // ─── Demande vendeur reçue (en attente de validation) ─────────────────────
  async sendVendorSubmitted(to: string, prenom: string, shopName: string): Promise<void> {
    await this.send(
      to,
      'Votre demande vendeur Asoukaa est en cours de traitement',
      vendorSubmittedTemplate(prenom, shopName),
    );
  }

  // ─── Demande livreur reçue (en attente de validation) ──────────────────────
  async sendAgentSubmitted(to: string, prenom: string): Promise<void> {
    await this.send(
      to,
      'Votre demande livreur Asoukaa est en cours de traitement',
      agentSubmittedTemplate(prenom),
    );
  }

  // ─── Validation vendeur ───────────────────────────────────────────────────
  async sendVendorApproved(to: string, prenom: string, shopName: string): Promise<void> {
    await this.send(
      to,
      'Votre boutique Asoukaa est approuvée !',
      vendorApprovedTemplate(prenom, shopName),
    );
  }

  // ─── Refus vendeur ────────────────────────────────────────────────────────
  async sendVendorRejected(to: string, prenom: string, shopName: string, motif: string): Promise<void> {
    await this.send(
      to,
      'Demande vendeur Asoukaa — Non approuvée',
      vendorRejectedTemplate(prenom, shopName, motif),
    );
  }

  // ─── Validation livreur ───────────────────────────────────────────────────
  async sendAgentApproved(to: string, prenom: string): Promise<void> {
    await this.send(
      to,
      'Vous êtes approuvé(e) comme livreur Asoukaa !',
      agentApprovedTemplate(prenom),
    );
  }

  // ─── Refus livreur ────────────────────────────────────────────────────────
  async sendAgentRejected(to: string, prenom: string, motif: string): Promise<void> {
    await this.send(
      to,
      'Demande livreur Asoukaa — Non approuvée',
      agentRejectedTemplate(prenom, motif),
    );
  }

  // ─── Invitation dashboard admin ────────────────────────────────────────────
  async sendAdminInvitation(
    to: string,
    prenom: string,
    role: string,
    link: string,
  ): Promise<void> {
    await this.send(
      to,
      'Invitation — Dashboard Asoukaa',
      adminInvitationTemplate(prenom, role, link),
    );
  }

  // ─── Boutique suspendue (admin) ───────────────────────────────────────────
  async sendVendorBlocked(to: string, prenom: string, shopName: string): Promise<void> {
    await this.send(
      to,
      'Votre boutique Asoukaa a été suspendue',
      vendorBlockedTemplate(prenom, shopName),
    );
  }

  // ─── Boutique réactivée (admin) ───────────────────────────────────────────
  async sendVendorUnblocked(to: string, prenom: string, shopName: string): Promise<void> {
    await this.send(
      to,
      'Votre boutique Asoukaa a été réactivée',
      vendorUnblockedTemplate(prenom, shopName),
    );
  }

  // ─── Compte livreur suspendu (admin) ──────────────────────────────────────
  async sendAgentBlocked(to: string, prenom: string): Promise<void> {
    await this.send(
      to,
      'Votre compte livreur Asoukaa a été suspendu',
      agentBlockedTemplate(prenom),
    );
  }

  // ─── Compte livreur réactivé (admin) ──────────────────────────────────────
  async sendAgentUnblocked(to: string, prenom: string): Promise<void> {
    await this.send(
      to,
      'Votre compte livreur Asoukaa a été réactivé',
      agentUnblockedTemplate(prenom),
    );
  }

  // ─── Livraison indépendante acceptée (au demandeur) ───────────────────────
  async sendIndependentDeliveryAccepted(to: string, prenom: string): Promise<void> {
    await this.send(
      to,
      '✅ Un livreur a accepté votre demande',
      independentDeliveryAcceptedTemplate(prenom),
    );
  }

  // ─── Paiement confirmé ────────────────────────────────────────────────────
  async sendPaymentConfirmed(
    to: string,
    prenom: string,
    orderNumber: string,
    montant: number,
    orderId?: string,
  ): Promise<void> {
    await this.send(
      to,
      `✅ Paiement confirmé — Commande ${orderNumber}`,
      paymentConfirmedTemplate({ prenom, orderNumber, montant, orderId }),
    );
  }

  // ─── Remboursement approuvé ───────────────────────────────────────────────
  async sendRefundApproved(
    to: string,
    prenom: string,
    orderNumber: string,
    montant: number,
    orderId?: string,
  ): Promise<void> {
    await this.send(
      to,
      '✅ Remboursement approuvé',
      refundApprovedTemplate({ prenom, orderNumber, montant, orderId }),
    );
  }

  // ─── Remboursement refusé ─────────────────────────────────────────────────
  async sendRefundRejected(to: string, prenom: string, orderNumber: string): Promise<void> {
    await this.send(
      to,
      'Demande de remboursement',
      refundRejectedTemplate(prenom, orderNumber),
    );
  }

  // ─── Notification in-app doublée par email ────────────────────────────────
  async sendNotification(to: string, data: NotificationEmailData): Promise<void> {
    await this.send(
      to,
      data.title,
      notificationTemplate(data),
    );
  }

  // ─── Changement d'e-mail ──────────────────────────────────────────────────

  /** Code envoyé à la NOUVELLE adresse. Lève une erreur si l'envoi échoue. */
  async sendEmailChangeCode(to: string, prenom: string, code: string): Promise<void> {
    await this.sendStrict(
      to,
      "Votre code pour changer d'adresse email Asoukaa",
      emailChangeCodeTemplate(prenom, code),
    );
  }

  /** Alerte à l'ANCIENNE adresse, avec le lien « Ce n'est pas moi ». */
  async sendEmailChangeAlert(to: string, data: EmailChangeAlertData): Promise<void> {
    await this.send(
      to,
      'Votre adresse de connexion Asoukaa a été changée',
      emailChangeAlertTemplate(data),
    );
  }

  /** Confirmation à la NOUVELLE adresse une fois le changement validé. */
  async sendEmailChangeConfirmed(to: string, prenom: string): Promise<void> {
    await this.send(
      to,
      'Votre adresse email Asoukaa a été modifiée',
      emailChangeConfirmedTemplate(prenom),
    );
  }

  /** « Compte sécurisé » : envoyé à l'adresse d'origine restaurée. */
  async sendEmailChangeSecured(to: string, prenom: string): Promise<void> {
    await this.send(
      to,
      'Compte Asoukaa sécurisé',
      emailChangeSecuredTemplate(prenom),
    );
  }

  /** Info générique à l'adresse « nouvelle » quand le changement est annulé. */
  async sendEmailChangeCancelled(to: string): Promise<void> {
    await this.send(
      to,
      "Changement d'adresse email annulé",
      emailChangeCancelledTemplate(),
    );
  }

  // ─── Tickets de support ───────────────────────────────────────────────────

  // Retire retours à la ligne / caractères de contrôle d'un sujet d'email
  // (anti-injection d'en-têtes) et borne sa longueur.
  private cleanHeader(value: string, max = 120): string {
    return String(value ?? '').replace(/[\u0000-\u001F\u007F]+/g, ' ').trim().slice(0, max);
  }

  /** L'équipe a répondu au ticket : email à l'utilisateur. */
  async sendSupportTicketReply(to: string, data: SupportTicketReplyData): Promise<void> {
    await this.send(
      to,
      `Réponse à votre ticket ${this.cleanHeader(data.reference, 20)} - Asoukaa`,
      supportTicketReplyTemplate(data),
    );
  }

  /** Nouveau ticket / ticket rouvert : email à l'équipe support. */
  async sendSupportTicketToTeam(to: string, data: SupportTicketTeamData): Promise<void> {
    const prefix = data.kind === 'reopened' ? 'Ticket rouvert' : 'Nouveau ticket';
    await this.send(
      to,
      `[Support] ${prefix} ${this.cleanHeader(data.reference, 20)} - ${this.cleanHeader(data.subject, 100)}`,
      supportTicketTeamTemplate(data),
    );
  }
}
