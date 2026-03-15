package com.nautilus.infra.pulumi.policy;

import java.util.HashMap;
import java.util.Map;

/**
 * Required tagging policy.
 * Injects mandatory tags onto every Azure resource.
 * Developers never call this directly — components call it automatically.
 */
public final class Tagging {

    private Tagging() {}

    /**
     * Returns the mandatory tag set for all Azure resources.
     * Required tags always win — extra keys are merged underneath them.
     */
    public static Map<String, String> requiredTags(
            String project,
            String environment,
            Map<String, String> extra) {

        var tags = new HashMap<>(extra != null ? extra : Map.of());
        tags.put("managed_by",  "pulumi");
        tags.put("project",     project);
        tags.put("environment", environment);
        return Map.copyOf(tags);
    }

    public static Map<String, String> requiredTags(String project, String environment) {
        return requiredTags(project, environment, null);
    }
}
