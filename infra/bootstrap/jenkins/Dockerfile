# Pinned Jenkins LTS + Java 21; no Docker socket or image-building tools in the controller.
FROM jenkins/jenkins:2.580.2-lts-jdk21

RUN jenkins-plugin-cli --plugins configuration-as-code:2147.v8a_8d38668c72 matrix-auth:3.3
