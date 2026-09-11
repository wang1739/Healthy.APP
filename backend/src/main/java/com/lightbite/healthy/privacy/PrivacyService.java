package com.lightbite.healthy.privacy;

import com.lightbite.healthy.common.api.ApiException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PrivacyService {
    private final JdbcTemplate jdbc;
    public PrivacyService(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public PrivacyDtos.Center center(String userId) {
        List<PrivacyDtos.Document> documents = jdbc.query("SELECT document_type,version,effective_at,"
                        + "change_summary,content_text,material_change FROM privacy_documents ORDER BY effective_at DESC",
                (rs, row) -> new PrivacyDtos.Document(rs.getString(1), rs.getString(2),
                        rs.getTimestamp(3).toInstant(), rs.getString(4), rs.getString(5), rs.getBoolean(6)));
        List<PrivacyDtos.ConsentEvent> history = jdbc.query("SELECT document_type,document_version,action,created_at "
                        + "FROM consent_events WHERE user_id=? ORDER BY created_at DESC",
                (rs, row) -> new PrivacyDtos.ConsentEvent(rs.getString(1), rs.getString(2), rs.getString(3),
                        rs.getTimestamp(4).toInstant()), userId);
        String privacy = latestAccepted(history, "PRIVACY_POLICY");
        String health = latestAccepted(history, "HEALTH_DATA_AUTHORIZATION");
        boolean authorized = Boolean.TRUE.equals(jdbc.queryForObject("SELECT EXISTS(SELECT 1 FROM health_permissions "
                + "WHERE user_id=? AND health_data_authorized=TRUE)", Boolean.class, userId));
        return new PrivacyDtos.Center(documents, history, privacy, health, authorized);
    }

    public PrivacyDtos.Document document(String type, String version) {
        List<PrivacyDtos.Document> rows = jdbc.query("SELECT document_type,version,effective_at,change_summary,"
                        + "content_text,material_change FROM privacy_documents WHERE document_type=? AND version=?",
                (rs, row) -> new PrivacyDtos.Document(rs.getString(1), rs.getString(2),
                        rs.getTimestamp(3).toInstant(), rs.getString(4), rs.getString(5), rs.getBoolean(6)), type, version);
        if (rows.isEmpty()) throw new ApiException(HttpStatus.NOT_FOUND, "PRIVACY_DOCUMENT_NOT_FOUND", "隐私文件不存在");
        return rows.get(0);
    }

    @Transactional
    public void accept(String userId, PrivacyDtos.AcceptRequest request) {
        PrivacyDtos.Document document = document(request.documentType(), request.version());
        jdbc.update("INSERT INTO consent_events (id,user_id,document_type,document_version,action) VALUES (?,?,?,?,?)",
                UUID.randomUUID().toString(), userId, document.type(), document.version(), "ACCEPT");
        if ("HEALTH_DATA_AUTHORIZATION".equals(document.type())) {
            int changed = jdbc.update("UPDATE health_permissions SET health_data_authorized=TRUE,authorization_version=?,"
                    + "updated_at=CURRENT_TIMESTAMP WHERE user_id=?", document.version(), userId);
            if (changed == 0) jdbc.update("INSERT INTO health_permissions "
                    + "(user_id,health_data_authorized,authorization_version) VALUES (?,TRUE,?)", userId, document.version());
        }
    }

    @Transactional
    public void revokeHealth(String userId) {
        int changed = jdbc.update("UPDATE health_permissions SET health_data_authorized=FALSE,updated_at=CURRENT_TIMESTAMP "
                + "WHERE user_id=?", userId);
        if (changed == 0) jdbc.update("INSERT INTO health_permissions (user_id,health_data_authorized) VALUES (?,FALSE)", userId);
        String version = latestAccepted(center(userId).history(), "HEALTH_DATA_AUTHORIZATION");
        jdbc.update("INSERT INTO consent_events (id,user_id,document_type,document_version,action) VALUES (?,?,?,?,?)",
                UUID.randomUUID().toString(), userId, "HEALTH_DATA_AUTHORIZATION",
                version == null ? "未同意" : version, "WITHDRAW");
    }

    private String latestAccepted(List<PrivacyDtos.ConsentEvent> history, String type) {
        return history.stream().filter(e -> type.equals(e.type()) && "ACCEPT".equals(e.action()))
                .map(PrivacyDtos.ConsentEvent::version).findFirst().orElse(null);
    }
}
