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
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.context.event.EventListener;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.scheduling.annotation.Scheduled;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

@Service
public class DataExportService {
    private static final Duration DOWNLOAD_TTL = Duration.ofHours(24);
    private final JdbcTemplate jdbc;
    private final AuthService auth;
    private final DataExportPdfService pdf;
    private final ObjectMapper json;
    private final Path exportDirectory;

    public DataExportService(JdbcTemplate jdbc, AuthService auth, DataExportPdfService pdf, ObjectMapper json) {
        this.jdbc = jdbc; this.auth = auth; this.pdf = pdf; this.json = json;
        this.exportDirectory = Path.of(System.getProperty("java.io.tmpdir"), "healthy-data-exports");
    }

    public synchronized DataExportDtos.Job create(String userId, DataExportDtos.Request request) {
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
        Path file = exportDirectory.resolve(id + ".pdf");
        try {
            Files.createDirectories(exportDirectory);
            try (OutputStream output = Files.newOutputStream(file)) {
                pdf.write(sections(userId, cutoff), password, output);
            }
            Instant completed = Instant.now();
            Instant expires = completed.plus(DOWNLOAD_TTL);
            jdbc.update("UPDATE data_export_jobs SET status='READY',file_path=?,completed_at=?,expires_at=? WHERE id=?",
                    file.toString(), Timestamp.from(completed), Timestamp.from(expires), id);
        } catch (IOException | RuntimeException exception) {
            boolean deleted = deleteFile(file);
            jdbc.update("UPDATE data_export_jobs SET status='FAILED',failure_code=?,file_path=? WHERE id=?",
                    deleted ? "PDF_GENERATION_FAILED" : "FILE_DELETE_FAILED", deleted ? null : file.toString(), id);
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
        if ("READY".equals(row.get("status")) && row.get("expires_at") != null
                && !((Timestamp) row.get("expires_at")).toInstant().isAfter(Instant.now())) {
            if (deleteFile(row.get("file_path"))) {
                jdbc.update("UPDATE data_export_jobs SET status='EXPIRED',file_path=NULL WHERE id=? AND user_id=?", id, userId);
            } else {
                jdbc.update("UPDATE data_export_jobs SET status='FAILED',failure_code='FILE_DELETE_FAILED' WHERE id=? AND user_id=?", id, userId);
            }
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
        List<String> account = List.of("昵称：" + value(user.get("display_name")),
                "手机号：" + maskPhone(phone), "注册时间：" + user.get("created_at"));
        List<DataExportPdfService.Section> sections = new ArrayList<>();
        sections.add(new DataExportPdfService.Section("导出说明", List.of(
                "生成时间：" + displayTime(Instant.now()), "数据截止时间：" + displayTime(cutoff),
                "本导出包含截止时间前的账户、健康档案、计划和健康记录明细。")));
        sections.add(new DataExportPdfService.Section("账户信息", account));
        sections.add(profileSection(userId, cutoff));
        sections.add(planSection(userId, cutoff));
        sections.add(recordSection(userId, cutoff));
        sections.add(reportSection(userId, cutoff));
        return sections;
    }

    private DataExportPdfService.Section profileSection(String userId, Instant cutoff) {
        List<String> lines = new ArrayList<>();
        jdbc.query("SELECT hp.birth_date,hp.sex,hp.height_cm,hp.activity_level,hp.work_style,hp.sleep_hours,"
                        + "hp.exercise_days,hg.goal_type,hg.target_weight_kg,hg.target_date,dp.diet_type,"
                        + "dp.allergies,dp.avoid_foods FROM health_profiles hp LEFT JOIN health_goals hg ON hg.user_id=hp.user_id "
                        + "LEFT JOIN dietary_preferences dp ON dp.user_id=hp.user_id WHERE hp.user_id=? AND hp.created_at<=?",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> lines.add("出生日期：" + value(rs.getObject(1)) + "；性别：" + label(rs.getString(2))
                        + "；身高：" + value(rs.getObject(3)) + " 厘米；活动水平：" + label(rs.getString(4))
                        + "；工作方式：" + label(rs.getString(5)) + "；睡眠：" + value(rs.getObject(6))
                        + " 小时；每周运动：" + value(rs.getObject(7)) + " 天；目标：" + label(rs.getString(8))
                        + "；目标体重：" + value(rs.getObject(9)) + " 千克；目标日期：" + value(rs.getObject(10))
                        + "；饮食类型：" + label(rs.getString(11)) + "；过敏：" + value(rs.getObject(12))
                        + "；忌口：" + value(rs.getObject(13))), userId, Timestamp.from(cutoff));
        jdbc.query("SELECT weight_kg,waist_cm,body_fat_percent,measured_at FROM body_measurements "
                        + "WHERE user_id=? AND measured_at<=? ORDER BY measured_at",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> lines.add("身体测量：" + rs.getTimestamp(4) + "，体重 " + rs.getBigDecimal(1)
                        + " 千克，腰围 " + value(rs.getObject(2)) + " 厘米，体脂率 " + value(rs.getObject(3)) + "%"),
                userId, Timestamp.from(cutoff));
        if (lines.isEmpty()) lines.add("暂无健康档案");
        return new DataExportPdfService.Section("健康档案", lines);
    }

    private DataExportPdfService.Section planSection(String userId, Instant cutoff) {
        List<String> lines = jdbc.query("SELECT p.status,v.version_number,v.calculation_date,v.target_kcal,v.protein_g,"
                        + "v.carbs_g,v.fat_g,v.water_ml,v.exercise_days,v.exercise_minutes,v.sleep_hours,v.adjustment_reason "
                        + "FROM health_plans p JOIN health_plan_versions v ON v.plan_id=p.id "
                        + "WHERE p.user_id=? AND v.created_at<=? ORDER BY v.version_number",
                (rs, row) -> "计划版本 " + rs.getInt(2) + "（" + label(rs.getString(1)) + "，计算日期 "
                        + rs.getObject(3) + "）：每日 " + rs.getInt(4) + " 千卡，蛋白质 " + rs.getInt(5)
                        + " 克，碳水 " + rs.getInt(6) + " 克，脂肪 " + rs.getInt(7) + " 克，饮水 "
                        + rs.getInt(8) + " 毫升，每周运动 " + rs.getInt(9) + " 天/" + rs.getInt(10)
                        + " 分钟，睡眠 " + rs.getBigDecimal(11) + " 小时，调整原因：" + value(rs.getObject(12)),
                userId, Timestamp.from(cutoff));
        return new DataExportPdfService.Section("健康计划", empty(lines, "暂无健康计划"));
    }

    private DataExportPdfService.Section recordSection(String userId, Instant cutoff) {
        List<String> lines = new ArrayList<>();
        lines.addAll(jdbc.query("SELECT entry_date,meal_type,food_name_snapshot,grams,calories_snapshot,protein_snapshot,"
                        + "carbs_snapshot,fat_snapshot FROM meal_entries WHERE user_id=? AND deleted_at IS NULL AND created_at<=? ORDER BY entry_date,created_at",
                (rs, row) -> "饮食：" + rs.getObject(1) + " " + label(rs.getString(2)) + "，" + rs.getString(3)
                        + " " + rs.getBigDecimal(4).stripTrailingZeros().toPlainString() + " 克，"
                        + rs.getBigDecimal(5).setScale(0, java.math.RoundingMode.HALF_UP) + " 千卡，蛋白质 "
                        + rs.getBigDecimal(6).stripTrailingZeros().toPlainString() + " 克，碳水 "
                        + rs.getBigDecimal(7).stripTrailingZeros().toPlainString() + " 克，脂肪 "
                        + rs.getBigDecimal(8).stripTrailingZeros().toPlainString() + " 克", userId, Timestamp.from(cutoff)));
        lines.addAll(jdbc.query("SELECT occurred_at,amount_ml FROM hydration_entries WHERE user_id=? AND deleted_at IS NULL AND created_at<=? ORDER BY occurred_at",
                (rs, row) -> "饮水：" + rs.getTimestamp(1) + "，" + rs.getInt(2) + " 毫升", userId, Timestamp.from(cutoff)));
        lines.addAll(jdbc.query("SELECT occurred_at,activity_name_snapshot,intensity,duration_minutes,final_kcal FROM activity_records WHERE user_id=? AND deleted_at IS NULL AND created_at<=? ORDER BY occurred_at",
                (rs, row) -> "运动：" + rs.getTimestamp(1) + "，" + rs.getString(2) + "，" + label(rs.getString(3))
                        + "，" + rs.getInt(4) + " 分钟，" + rs.getInt(5) + " 千卡", userId, Timestamp.from(cutoff)));
        lines.addAll(jdbc.query("SELECT started_at,ended_at,record_type,duration_minutes,quality_score,note FROM sleep_records WHERE user_id=? AND deleted_at IS NULL AND created_at<=? ORDER BY started_at",
                (rs, row) -> "睡眠：" + rs.getTimestamp(1) + " 至 " + rs.getTimestamp(2) + "，" + label(rs.getString(3))
                        + "，" + rs.getInt(4) + " 分钟，质量 " + value(rs.getObject(5)) + "，备注：" + value(rs.getObject(6)),
                userId, Timestamp.from(cutoff)));
        return new DataExportPdfService.Section("健康记录明细", empty(lines, "暂无健康记录"));
    }

    private DataExportPdfService.Section reportSection(String userId, Instant cutoff) {
        List<String> lines = new ArrayList<>();
        jdbc.query("SELECT report_type,period_start,period_end,version,created_at,snapshot_json FROM health_reports "
                        + "WHERE user_id=? AND deleted_at IS NULL AND created_at<=? ORDER BY period_start,version",
                (org.springframework.jdbc.core.RowCallbackHandler) rs -> {
                    lines.add("健康报告：" + label(rs.getString(1)) + "，周期 " + rs.getObject(2) + " 至 "
                            + rs.getObject(3) + "，版本 " + rs.getInt(4) + "，生成时间 " + rs.getTimestamp(5));
                    lines.addAll(reportContent(rs.getString(6)));
                }, userId, Timestamp.from(cutoff));
        return new DataExportPdfService.Section("健康报告目录", empty(lines, "暂无健康报告"));
    }

    private List<String> reportContent(String value) {
        JsonNode snapshot = json.readTree(value);
        List<String> lines = new ArrayList<>();
        add(lines, "报告结论：", snapshot.path("conclusion").asText());
        for (JsonNode metric : snapshot.path("keyMetrics"))
            add(lines, "关键指标：", metric.path("label").asText() + "：" + metric.path("value").asText()
                    + (metric.path("unit").asText().isBlank() ? "" : " " + metric.path("unit").asText()));
        for (JsonNode advice : snapshot.path("advice"))
            add(lines, "建议：", advice.path("title").asText() + "：" + advice.path("description").asText());
        add(lines, "说明：", snapshot.path("disclaimer").asText());
        return lines;
    }

    private void add(List<String> lines, String prefix, String value) {
        if (value != null && !value.isBlank()) lines.add(prefix + value);
    }

    @EventListener(ApplicationReadyEvent.class)
    public void recoverInterruptedJobs() {
        jdbc.query("SELECT id,file_path FROM data_export_jobs WHERE status IN ('PENDING','PROCESSING')",
                rs -> { boolean deleted = deleteFile(rs.getObject(2)); jdbc.update("UPDATE data_export_jobs SET status='FAILED',failure_code=?,file_path=? WHERE id=?",
                        deleted ? "PROCESS_INTERRUPTED" : "FILE_DELETE_FAILED", deleted ? null : rs.getObject(2), rs.getString(1)); });
        cleanupExpired();
    }

    @Scheduled(cron = "0 30 * * * *")
    public void cleanupExpired() {
        jdbc.query("SELECT id,file_path FROM data_export_jobs WHERE status='READY' AND expires_at<=CURRENT_TIMESTAMP",
                rs -> { boolean deleted = deleteFile(rs.getObject(2)); jdbc.update("UPDATE data_export_jobs SET status=?,failure_code=?,file_path=? WHERE id=?",
                        deleted ? "EXPIRED" : "FAILED", deleted ? null : "FILE_DELETE_FAILED",
                        deleted ? null : rs.getObject(2), rs.getString(1)); });
    }

    public void deleteFiles(String userId) {
        List<String> paths = jdbc.queryForList("SELECT file_path FROM data_export_jobs WHERE user_id=? AND file_path IS NOT NULL",
                String.class, userId);
        boolean deleted = true;
        for (String path : paths) deleted &= deleteFile(path);
        if (!deleted) {
            jdbc.update("UPDATE data_export_jobs SET status='FAILED',failure_code='FILE_DELETE_FAILED' WHERE user_id=? AND file_path IS NOT NULL", userId);
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "DATA_EXPORT_FILE_DELETE_FAILED", "导出文件清理失败，请稍后重试");
        }
        jdbc.update("UPDATE data_export_jobs SET file_path=NULL,expires_at=NULL WHERE user_id=?", userId);
    }

    private boolean deleteFile(Object value) {
        if (value == null) return true;
        try { Files.deleteIfExists(Path.of(value.toString())); return true; } catch (IOException ignored) { return false; }
    }

    private List<String> empty(List<String> lines, String fallback) { return lines.isEmpty() ? List.of(fallback) : lines; }
    private String value(Object value) { return value == null || value.toString().isBlank() ? "未设置" : value.toString(); }
    private String maskPhone(String phone) { return phone.length() >= 11 ? phone.substring(0, 3) + "****" + phone.substring(phone.length() - 4) : "已脱敏"; }
    private String displayTime(Instant value) { return DateTimeFormatter.ofPattern("yyyy年MM月dd日 HH:mm:ss").withZone(ZoneId.of("Asia/Shanghai")).format(value); }
    private String label(String code) {
        if (code == null) return "未设置";
        return Map.ofEntries(Map.entry("FEMALE", "女"), Map.entry("MALE", "男"), Map.entry("OTHER", "其他"),
                Map.entry("BREAKFAST", "早餐"), Map.entry("LUNCH", "午餐"), Map.entry("DINNER", "晚餐"),
                Map.entry("SNACK", "加餐"), Map.entry("LOW", "低强度"), Map.entry("MEDIUM", "中等强度"),
                Map.entry("HIGH", "高强度"), Map.entry("NIGHT", "夜间睡眠"), Map.entry("NAP", "小睡"),
                Map.entry("ACTIVE", "进行中"), Map.entry("PAUSED", "已暂停"), Map.entry("FAT_LOSS", "减脂"),
                Map.entry("DAILY", "日报"), Map.entry("WEEKLY", "周报"), Map.entry("MONTHLY", "月报"))
                .getOrDefault(code, code);
    }
}
