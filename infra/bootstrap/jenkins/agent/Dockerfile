# HU-04 build agent: Java 21 (Gradle builds) + Docker CLI/Compose (image builds).
# It talks to the host Docker daemon through the mounted socket; see docs/operaciones/hu-04-pipeline-ci.md.
FROM docker:29.9.3-cli AS docker-cli

FROM jenkins/inbound-agent:3395.v6e5377b_0fb_3c-4-jdk21

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates jq \
 && rm -rf /var/lib/apt/lists/*

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx

# Keep Gradle's cache on a volume and stay inside the 4 GiB of the EC2 host.
ENV GRADLE_USER_HOME=/home/jenkins/.gradle \
    GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=2 -Xmx1g"
RUN mkdir -p /home/jenkins/.gradle /home/jenkins/agent \
 && chown -R jenkins:jenkins /home/jenkins

USER jenkins
