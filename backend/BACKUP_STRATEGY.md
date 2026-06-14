# Stratégie de Sauvegarde - Asoukaa Backend

## Vue d'ensemble
Ce document définit la stratégie complète de sauvegarde et de récupération en cas de sinistre pour le backend Asoukaa.

---

## 1. Types de Données à Sauvegarder

### 1.1 Base de Données
- **Contenu**: Tous les enregistrements (users, admins, payments, products, etc.)
- **Importance**: CRITIQUE
- **Fréquence**: Quotidienne (minimum)
- **Rétention**: 30 jours de backups complets

### 1.2 Fichiers Uploadés
- **Localisation**: `/uploads` ou Cloud Storage (S3, GCS, etc.)
- **Importance**: HAUTE
- **Fréquence**: Quotidienne
- **Rétention**: 90 jours

### 1.3 Logs Applicatifs
- **Contenu**: Activity logs, error logs, audit trails
- **Importance**: MOYENNE
- **Fréquence**: Continu (streaming)
- **Rétention**: 90 jours en hot, 1 an en archive froide

### 1.4 Configurations
- **Contenu**: `.env`, variables d'environnement, configurations déployées
- **Importance**: HAUTE
- **Fréquence**: À chaque changement + quotidienne
- **Rétention**: Historique complet (git)

---

## 2. Stratégies par Environnement

### 2.1 PRODUCTION

#### Base de Données
```bash
# Backup quotidien automatisé
# Utiliser: AWS RDS Automated Backups + Snapshots manuels
# - Rétention automatique: 30 jours
# - Snapshots manuels: Chaque semaine + fin de mois
# - Chiffrement: AES-256
```

#### Commandes de Backup Manual
```bash
# PostgreSQL
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME | gzip > backup_$(date +%Y%m%d).sql.gz

# MySQL
mysqldump -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME | gzip > backup_$(date +%Y%m%d).sql.gz

# MongoDB
mongodump --uri="mongodb://$MONGO_USER:$MONGO_PASS@$MONGO_HOST:27017" --out=./backup_$(date +%Y%m%d)
```

#### Cloud Storage (S3)
```bash
# Upload backups to AWS S3
aws s3 cp backup_$(date +%Y%m%d).sql.gz s3://asoukaa-backups/prod/$(date +%Y-%m-%d)/

# Configure lifecycle policy (Glacier after 30 days)
aws s3api put-bucket-lifecycle-configuration \
  --bucket asoukaa-backups \
  --lifecycle-configuration file://lifecycle.json
```

#### Fichiers
- **Service**: AWS S3 + CloudFront
- **Versioning**: Activé
- **Replication**: Cross-region replication (région secondaire)
- **Lifecycle**: Archive après 90 jours

#### Logs
- **Service**: AWS CloudWatch Logs / ELK Stack
- **Retention**: 90 jours en hot
- **Archive**: S3 Glacier après 90 jours
- **Monitoring**: AlerteError après 10 erreurs en 5 minutes

### 2.2 STAGING

#### Base de Données
- **Fréquence**: Quotidienne (point de restauration nocturne)
- **Méthode**: Replication depuis Production + snapshots locaux
- **Rétention**: 14 jours

#### Fichiers
- **Synchronisation**: Miroir quotidien de Production (volume réduit)
- **Rétention**: 7 jours

### 2.3 DÉVELOPPEMENT

#### Base de Données
- **Source**: Snapshot anonymisé de Production (hebdomadaire)
- **Fréquence**: Manuelle ou CI/CD
- **Rétention**: 3 jours

---

## 3. Procédures de Récupération

### 3.1 Scénario 1: Data Corruption (Correctable)
**Durée de RTO**: < 1 heure
**Durée de RPO**: 1 jour

```bash
# 1. Identifier la corruption
SELECT * FROM activity_logs WHERE created_at > NOW() - INTERVAL '1 day' ORDER BY created_at DESC;

# 2. Restaurer depuis le backup d'avant-hier
pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME_TEMP backup_20260610.sql.gz

# 3. Valider les données
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM activity_logs;

# 4. Basculer vers la base restaurée
# (Après validation et approbation)
```

### 3.2 Scénario 2: Perte Totale de Base de Données
**Durée de RTO**: < 4 heures
**Durée de RPO**: < 24 heures

```bash
# 1. Provisionner une nouvelle instance DB
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier asoukaa-prod-restored \
  --db-snapshot-identifier asoukaa-prod-20260610

# 2. Attendre la disponibilité (10-30 min)
aws rds describe-db-instances --db-instance-identifier asoukaa-prod-restored

# 3. Mettre à jour l'application pour pointer vers la nouvelle DB
# - Modifier les credentials dans Secrets Manager
# - Redéployer l'application

# 4. Valider la connectivité
curl https://api.asoukaa.com/health
```

### 3.3 Scénario 3: Perte de Fichiers Uploadés
**Durée de RTO**: < 30 minutes
**Durée de RPO**: 1 jour

```bash
# 1. Vérifier les fichiers perdus
aws s3 ls s3://asoukaa-uploads/ --recursive | grep "2026-06"

# 2. Restaurer depuis la version antérieure
aws s3api get-object-version-tagging \
  --bucket asoukaa-uploads \
  --key user-doc-12345 \
  --version-id <version-id>

# 3. Ou restaurer depuis Glacier
aws s3api restore-object \
  --bucket asoukaa-uploads \
  --key user-doc-12345 \
  --restore-request Days=7
```

### 3.4 Scénario 4: Attaque Sécurité (Ransomware/Compromise)
**Durée de RTO**: < 2 heures
**Durée de RPO**: < 4 heures

```bash
# 1. Isoler immédiatement les systèmes affectés
# 2. Contactez l'équipe sécurité et management
# 3. Restaurer depuis le snapshot pré-attaque (basé sur les logs)

# Identifier le moment de compromise
SELECT * FROM activity_logs 
WHERE action = 'SUSPICIOUS_ACTIVITY' 
ORDER BY created_at DESC LIMIT 10;

# Restaurer depuis le snapshot approprié
pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME backup_20260609.sql.gz
```

---

## 4. Test de Récupération

### 4.1 Fréquence des Tests
- **Base de Données**: Mensuellement
- **Fichiers**: Tous les 3 mois
- **Procédure Complète**: Trimestriellement

### 4.2 Checklist de Test
```markdown
- [ ] Backup créé sans erreurs
- [ ] Taille du backup vérifiée (> 100MB pour prod)
- [ ] Archive chiffrée correctement
- [ ] Transfert vers le stockage secondaire réussi
- [ ] Restauration test réussie sur DB-TEST
- [ ] Validation des données post-restauration
- [ ] Performance acceptable après restauration
- [ ] Documentation mise à jour
```

### 4.3 Rapports de Test
```bash
# Créer un rapport mensuel
cat > BACKUP_TEST_REPORT_$(date +%Y-%m).md << EOF
# Rapport de Test de Backup - $(date +%B %Y)

## Calendrier de Tests
- [ ] Test DB: $(date)
- [ ] Test Fichiers: $(date)
- [ ] Test Logs: $(date)

## Résultats
- **État Global**: PASS / FAIL
- **Durée RTO Réelle**: X minutes
- **Intégrité Données**: Vérifiée
- **Points d'Amélioration**: [...]

## Signature
- Équipe: DevOps
- Date: $(date)
- Approuvé par: Manager
EOF
```

---

## 5. Monitoring & Alertes

### 5.1 Métriques à Monitorer
```bash
# Backup Success Rate
- Pourcentage de backups réussis: > 99%
- Dernière sauvegarde: < 24h
- Taille du backup: entre X et Y GB

# Recovery Metrics
- Temps pour restaurer la DB: < 1h
- Intégrité des données après restore: 100%
- Nombre de fichiers restaurables: > 99.9%
```

### 5.2 Alertes
```yaml
alerts:
  backup_failed:
    severity: CRITICAL
    condition: backup_status == 'FAILED'
    action: Notifier DevOps immédiatement

  backup_delayed:
    severity: HIGH
    condition: last_backup_time > 24h
    action: Relancer le backup + notification

  storage_low:
    severity: MEDIUM
    condition: storage_used > 80%
    action: Archiver anciens backups

  recovery_failed:
    severity: CRITICAL
    condition: restore_test_status == 'FAILED'
    action: Panique + investigation immédiate
```

---

## 6. Rétention et Conformité

### 6.1 Politique de Rétention
```
Production:
├─ Backups quotidiens: 30 jours
├─ Snapshots hebdo: 3 mois
├─ Snapshots mensuels: 1 an
└─ Archive légale: 7 ans (Glacier)

Staging:
├─ Backups: 14 jours
└─ Snapshots: 3 mois

Dev:
├─ Backups: 3 jours
└─ Snapshots: À la demande
```

### 6.2 Conformité
- **GDPR**: Les backups inclus dans la portée DPIA
- **CCPA**: Respecter les droits de suppression même dans les backups
- **Audit**: Logs de tous les accès aux backups
- **Chiffrement**: AES-256 pour tous les backups au repos

---

## 7. Contacts et Escalade

### 7.1 Procédure d'Escalade
```
1. Détection: Monitoring -> Slack (#incidents)
2. Alerte: Notifier l'équipe DevOps lead
3. Investigation: < 15 minutes
4. Décision: < 30 minutes
5. Restauration: Commencer < 1 heure
6. Vérification: Compléter < 4 heures
7. Post-mortem: 48 heures après
```

### 7.2 Contacts Clés
| Rôle | Nom | Téléphone | Email |
|------|-----|-----------|-------|
| DevOps Lead | [NAME] | [PHONE] | [EMAIL] |
| DB Admin | [NAME] | [PHONE] | [EMAIL] |
| Manager | [NAME] | [PHONE] | [EMAIL] |
| CEO | [NAME] | [PHONE] | [EMAIL] |

---

## 8. Amélioration Continue

### 8.1 Revue Trimestrielle
- Analyser les incidents de backup
- Vérifier l'RPO/RTO réels vs attendus
- Mettre à jour les procédures
- Former l'équipe sur les changements

### 8.2 Optimisations Futures
- [ ] Implémenter incremental backups (réduire la durée)
- [ ] Ajouter backup géographiquement distributed
- [ ] Automatiser les tests de récupération
- [ ] Implémenter PITR (Point-In-Time Recovery)

---

**Dernière mise à jour**: 2026-06-12  
**Prochaine revue**: 2026-09-12  
**Approuvé par**: [Manager Name]
