# ─── Image du backend Asoukaa (serveur de test / production) ───────────────
# Construit le code depuis les sources (src/), donc indépendant de ton dossier dist local.
FROM node:22-slim AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --omit=dev

FROM node:22-slim
ENV NODE_ENV=production \
    TZ=Africa/Lagos
WORKDIR /app
COPY --from=build /app/package*.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
RUN mkdir -p uploads
# Railway fournit la variable PORT ; en local on retombe sur APP_PORT (3001 chez toi)
EXPOSE 3001
# 1) applique les migrations (crée / met à jour les tables)  2) démarre le serveur
CMD ["sh", "-c", "node node_modules/typeorm/cli.js migration:run -d dist/database/data-source.js && node dist/main"]
