import { Injectable, Logger } from '@nestjs/common';
import * as nodemailer from 'nodemailer';
import { ConfigService } from '@nestjs/config';
import { otpTemplate } from './templates/otp.template';
import { passwordResetTemplate } from './templates/password-reset.template';
import { orderConfirmationTemplate, OrderConfirmationData } from './templates/order-confirmation.template';
import { vendorApprovedTemplate } from './templates/vendor-approved.template';
import { vendorRejectedTemplate } from './templates/vendor-rejected.template';
import { agentApprovedTemplate } from './templates/agent-approved.template';
import { agentRejectedTemplate } from './templates/agent-rejected.template';

@Injectable()
export class MailService {
  private readonly logger = new Logger(MailService.name);
  private transporter: nodemailer.Transporter;

  constructor(private readonly config: ConfigService) {
    this.transporter = nodemailer.createTransport({
      host: this.config.get<string>('MAIL_HOST'),
      port: this.config.get<number>('MAIL_PORT'),
      secure: this.config.get<boolean>('MAIL_SECURE'), // true pour 465
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

  // ─── OTP Vérification compte ───────────────────────────────────────────────
  async sendOtp(to: string, prenom: string, code: string): Promise<void> {
    await this.send(
      to,
      '🔐 Votre code de vérification Asoukaa',
      otpTemplate(prenom, code),
    );
  }

  // ─── Réinitialisation mot de passe ────────────────────────────────────────
  async sendPasswordReset(to: string, prenom: string, code: string): Promise<void> {
    await this.send(
      to,
      '🔑 Réinitialisation de votre mot de passe',
      passwordResetTemplate(prenom, code),
    );
  }

  // ─── Confirmation de commande ─────────────────────────────────────────────
  async sendOrderConfirmation(to: string, data: OrderConfirmationData): Promise<void> {
    await this.send(
      to,
      `✅ Commande #${data.orderNumber} confirmée`,
      orderConfirmationTemplate(data),
    );
  }

  // ─── Validation vendeur ───────────────────────────────────────────────────
  async sendVendorApproved(to: string, prenom: string, shopName: string): Promise<void> {
    await this.send(
      to,
      '🎉 Votre boutique Asoukaa est approuvée !',
      vendorApprovedTemplate(prenom, shopName),
    );
  }

  // ─── Refus vendeur ────────────────────────────────────────────────────────
  async sendVendorRejected(to: string, prenom: string, shopName: string, motif: string): Promise<void> {
    await this.send(
      to,
      ' Demande vendeur Asoukaa — Non approuvée',
      vendorRejectedTemplate(prenom, shopName, motif),
    );
  }

  // ─── Validation livreur ───────────────────────────────────────────────────
  async sendAgentApproved(to: string, prenom: string): Promise<void> {
    await this.send(
      to,
      ' Vous êtes approuvé comme livreur Asoukaa !',
      agentApprovedTemplate(prenom),
    );
  }

  // ─── Refus livreur ────────────────────────────────────────────────────────
  async sendAgentRejected(to: string, prenom: string, motif: string): Promise<void> {
    await this.send(
      to,
      ' Demande livreur Asoukaa — Non approuvée',
      agentRejectedTemplate(prenom, motif),
    );
  }

  async sendAdminInvitation(
  to: string,
  prenom: string,
  role: string,
  link: string,
): Promise<void> {
  await this.send(
    to,
    '🔐 Invitation — Dashboard Asoukaa',
    `
    <p>Bonjour <strong>${prenom}</strong>,</p>
    <p>Vous avez été invité(e) en tant que <strong>${role}</strong> sur Asoukaa.</p>
    <p>Cliquez sur le lien ci-dessous pour définir votre mot de passe :</p>
    <a href="${link}" style="background:#FF6B00;color:#fff;padding:12px 24px;border-radius:8px;text-decoration:none;display:inline-block;margin:16px 0;">
      Définir mon mot de passe
    </a>
    <p style="color:#888;font-size:13px;">Ce lien expire dans <strong>48 heures</strong>.</p>
    `,
  );
}
}