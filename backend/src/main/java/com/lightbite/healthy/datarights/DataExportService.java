package com.lightbite.healthy.datarights;

import com.lightbite.healthy.auth.AuthService;
import com.lightbite.healthy.common.api.ApiException;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DataExportService {
    private static final Duration DOWNLOAD_TTL = Duration.ofHours(24);
    private final JdbcTemplate jdbc;
    private final AuthService auth;
    private final DataExportPdfService pdf;
    private final Path exportDirectory;

    public DataExportService(JdbcTemplate jdbc, AuthService auth, DataExportPdfService pdf) {
        this.jdbc = jdbc; this.auth = auth; this.pdf = pdf;
        this.exportDirectory = Path.of(System.getProperty("java.io.tmpdir"), "healthy-data-exports");
    }

    @Transactional
    public DataExportDtos.Job create(String userId, DataExportDtos.Request request) {
        String phone = jdbc.queryForObject("SELECT phone FROM users WHERE id=?", String.class, userId);
        auth.consumeCode(phone, "DATA_EXPORT", request.code());
        Integer recent = jdbc.queryForObject("SELECT COUNT(*) FROM data_export_jobs WHERE user_id=? "
                        + "AND status='READY' AND completed_at>?", Integer.class, userId,
                Timestamp.from(Instant.now().minus(Duration.ofHours(24))));
        if (recent != null && recent > 0)
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "DATA_EXPORT_LIMIT", "每 24 小时只能成功导出一次");
        Integer active = jdbc.queryForObject("SELECT COUNT(*) FROM data_export_jobs WHERE user_id=? "
                + "AND status IN ('PENDING','PROCESSING')", Integer.class, userId);
        if (active != null && active > 0)
            throw new ApiException(HttpStatus.CONFLICT, "DATA_EXPORT_ACTIVE", "已有数据导出正在处理");

        String id = UUID.randomUUID().toString();
        Instant cutoff = Instant.now();
        jdbc.update("INSERT INTO data_export_jobs (id,user_id,status,data_cutoff_at) VALUES (?,?,'PROCESSING',?)",
                id, userId, Timestamp.from(cutoff));
        char[] password = request.password().toCharArray();
        try {
            Files.createDirectories(exportDirectory);
            Path file = exportDirectory.resolve(id + ".pdf");
            try (OutputStream output = Files.newOutputStream(file)) {
                pdf.write(sections(userId, cutoff), password, output);
            }
            Instant completed = Instant.now();
            Instant expires = completed.plus(DOWNLOAD_TTL);
            jdbc.update("UPDATE data_export_jobs SET status='READY',file_path=?,completed_at=?,expires_at=? WHERE id=?",
                    file.toString(), Timestamp.from(completed), Timestamp.from(expires), id);
        } catch (IOException exception) {
            jdbc.update("UPDATE data_export_jobs SET status='FAILED',failure_code='PDF_GENERATION_FAILED' WHERE id=?", id);
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "DATA_EXPORT_FAILED", "数据导出失败，请稍后重试");
        } finally {
            Arrays.fill(password, '\0');
        }
        return owned(userId, id);
    }

    public List<DataExportDtos.Job> list(String userId) {
        return jdbc.query("SELECT id,status,data_cutoff_at,created_at,completed_at,expires_at,failure_code "
                        + "FROM data_export_jobs WHERE user_id=? ORDER BY created_at DESC",
                (rs, row) -> job(rs.getString(1), rs.getString(2), rs.getTimestamp(3), rs.getTimestamp(4),
                        rs.getTimestamp(5), rs.getTimestamp(6), rs.getString(7)), userId);
    }

    public Path download(String userId, String id) {
        Map<String, Object> row;
        try {
            row = jdbc.queryForMap("SELECT status,file_path,expires_at FROM data_export_jobs WHERE id=? AND user_id=?", id, userId);
        } catch (org.springframework.dao.EmptyResultDataAccessException exception) {
            throw new ApiException(HttpStatus.NOT_FOUND, "DATA_EXPORT_NOT_FOUND", "导出文件不存在");
        }
        if (!"READY".equals(row.get("status")) || row.get("expires_at") == null
                || !((Timestamp) row.get("expires_at")).toInstant().isAfter(Instant.now()))
            throw new ApiException(HttpStatus.GONE, "DATA_EXPORT_EXPIRED", "导出文件已过期，请重新申请");
        Path path = Path.of(row.get("file_path").toString());
        if (!Files.exists(path)) throw new ApiException(HttpStatus.GONE, "DATA_EXPORT_EXPIRED", "导出文件已过期，请重新申请");
        return path;
    }

    private DataExportDtos.Job owned(String userId, String id) {
        return list(userId).stream().filter(value -> id.equals(value.id())).findFirst().orElseThrow();
    }

    private DataExportDtos.Job job(String id, String status, Timestamp cutoff, Timestamp created,
                                   Timestamp completed, Timestamp expires, String failure) {
        return new DataExportDtos.Job(id, status, cutoff.toInstant(), created.toInstant(), instant(completed),
                instant(expires), failure == null ? null : "生成失败，请重新申请");
    }

    private Instant instant(Timestamp value) { return value == null ? null : value.toInstant(); }

    private List<DataExportPdfService.Section> sections(String userId, Instant cutoff) {
        Map<String, Object> user = jdbc.queryForMap("SELECT phone,display_name,created_at FROM users WHERE id=?", userId);
        String phone = user.get("phone").toString();
        List<String> account = List.of("昵称：" + (user.get("display_name") == null ? "未设置" : user.get("display_name")),
                "手机号：" + phone.substring(0, 3) + "****" + phone.substring(7), "注册时间：" + user.get("created_at"));
        return List.of(
                new DataExportPdfService.Section("账户信息", account),
                new DataExportPdfService.Section("健康档案", List.of("档案状态：" + count("health_profiles", userId) + " 份", "身体测量：" + count("body_measurements", userId) + " 条")),
                new DataExportPdfService.Section("健康计划", List.of("计划：" + count("health_plans", userId) + " 份")),
                new DataExportPdfService.Section("健康记录", List.of("饮食记录：" + count("meal_entries", userId) + " 条", "饮水记录：" + count("hydration_entries", userId) + " 条", "活动记录：" + count("activity_records", userId) + " 条", "睡眠记录：" + count("sleep_records", userId) + " 条", "健康报告：" + count("health_reports", userId) + " 份", "数据截止时间：" + cutoff))
        );
    }

    private int count(String table, String userId) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM " + table + " WHERE user_id=?", Integer.class, userId);
    }
}
