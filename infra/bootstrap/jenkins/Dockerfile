# Pinned Jenkins LTS + Java 21; no Docker socket or image-building tools in the controller.
# HU-01 plugins (configuration-as-code, matrix-auth) plus the HU-04 pipeline plugins.
# Builds run on the separate build-agent container, never on the controller.
FROM jenkins/jenkins:2.580.2-lts-jdk21

RUN jenkins-plugin-cli --plugins \
    configuration-as-code:2147.v8a_8d38668c72 \
    matrix-auth:3.3 \
    workflow-aggregator:608.v67378e9d3db_1 \
    workflow-multibranch:842.v3a_b_59b_57b_e6e \
    pipeline-groovy-lib:822.vc95f70dea_db_7 \
    pipeline-stage-view:2.41 \
    pipeline-utility-steps:3.810.va_7672d206740 \
    git:5.11.0 \
    github:1.47.0 \
    github-branch-source:1986.v801e40614d00 \
    job-dsl:3732.v9a_c49a_61a_313 \
    credentials-binding:728.v902a_273b_8947 \
    junit:1458.v38661c0638e2 \
    jacoco:3.3.7 \
    timestamper:1.30 \
    ws-cleanup:0.49
