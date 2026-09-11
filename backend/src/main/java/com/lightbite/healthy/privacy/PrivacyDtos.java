package com.lightbite.healthy.privacy;

import java.time.Instant;
import java.util.List;

public final class PrivacyDtos {
    private PrivacyDtos() {}
    public record Document(String type, String version, Instant effectiveAt, String changeSummary,
                           String content, boolean materialChange) {}
    public record ConsentEvent(String type, String version, String action, Instant createdAt) {}
    public record Center(List<Document> latestDocuments, List<ConsentEvent> history,
                         String acceptedPrivacyVersion, String acceptedHealthVersion,
                         boolean healthAuthorized) {}
    public record AcceptRequest(String documentType, String version) {}
}
