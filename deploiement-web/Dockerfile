# Version web de l'appli Asoukaa (fichiers déjà compilés dans ./site)
FROM nginx:1.27-alpine
ENV PORT=8080
COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY site/ /usr/share/nginx/html/
