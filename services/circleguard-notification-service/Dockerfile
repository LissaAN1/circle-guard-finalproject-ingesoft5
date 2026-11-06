# syntax=docker/dockerfile:1
# Imagen inmutable de circleguard-notification-service (HU-03). Contexto de build: raiz del monorepo.
#   docker build -f services/circleguard-notification-service/Dockerfile -t circleguard-notification-service:<semver> .

# ---- Etapa 1: compilacion ----
FROM gradle:8.14-jdk21 AS build
WORKDIR /workspace
ENV GRADLE_USER_HOME=/home/gradle/.gradle

# Se usa la imagen oficial de Gradle con gradle-wrapper.jar versionado en el repositorio.
COPY settings.gradle.kts build.gradle.kts ./
COPY services/ ./services/

# Las pruebas se ejecutan en el pipeline (HU-04/HU-05), no al empaquetar.
RUN --mount=type=cache,target=/home/gradle/.gradle \
    gradle :services:circleguard-notification-service:bootJar -x test --no-daemon --console=plain \
 && cp services/circleguard-notification-service/build/libs/*.jar /workspace/app.jar

# ---- Etapa 2: ejecucion ----
FROM eclipse-temurin:21-jre
ARG VERSION=0.0.0-dev
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="circleguard-notification-service" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://github.com/LissaAN1/circle-guard-finalproject-ingesoft5"

# Usuario sin privilegios (no root)
RUN groupadd --system --gid 10001 app \
 && useradd  --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app
WORKDIR /app
COPY --from=build --chown=app:app /workspace/app.jar /app/app.jar
USER 10001:10001

ENV JAVA_OPTS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"
EXPOSE 8082
ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar /app/app.jar"]
