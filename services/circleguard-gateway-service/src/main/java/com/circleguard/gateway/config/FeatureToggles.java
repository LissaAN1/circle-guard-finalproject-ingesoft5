package com.circleguard.gateway.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * HU-15: feature toggles of the gateway, read from external configuration.
 *
 * <p>Each toggle is a property of application.yml bound to an environment variable. In Kubernetes the
 * variable comes from the ConfigMap {@code circleguard-config} of the environment, so changing it and
 * restarting the pods changes the behaviour with the same image.
 */
@Component
@Slf4j
public class FeatureToggles {

    private final boolean denySuspectEntry;

    public FeatureToggles(@Value("${circleguard.features.deny-suspect-entry:true}") boolean denySuspectEntry) {
        this.denySuspectEntry = denySuspectEntry;
        log.info("Feature toggle deny-suspect-entry={}", denySuspectEntry);
    }

    /**
     * Whether a user who is SUSPECT or PROBABLE (not confirmed) is denied entry to campus.
     * {@code true} (default) keeps the strict policy of HU-07; {@code false} lets them in with a warning, for
     * a lower-risk phase decided by the health team. CONFIRMED users are always denied.
     */
    public boolean denySuspectEntry() {
        return denySuspectEntry;
    }
}
