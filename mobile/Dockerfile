# ---- Etapa 1: exportacion web de Expo ----
FROM node:20-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npx expo export --platform web --output-dir dist

# ---- Etapa 2: servidor estatico sin root ----
FROM nginxinc/nginx-unprivileged:1.27-alpine
ARG VERSION=0.0.0-dev
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="circleguard-web" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://github.com/LissaAN1/circle-guard-finalproject-ingesoft5"
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
COPY --chmod=755 docker-entrypoint.sh /docker-entrypoint-cg.sh
# nginx-unprivileged corre como UID 101; config.js se escribe en tiempo de arranque
USER root
RUN chown 101:101 /usr/share/nginx/html
USER 101
EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint-cg.sh"]