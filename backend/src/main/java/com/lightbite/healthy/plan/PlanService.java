package com.lightbite.healthy.plan;

import com.lightbite.healthy.common.api.ApiException;
import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.Period;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PlanService {

    private final JdbcTemplate jdbc;
    private final PlanCalculator calculator;
    private final PlanPolicy policy;

    public PlanService(JdbcTemplate jdbc, PlanCalculator calculator, PlanPolicy policy) {
        this.jdbc = jdbc;
        this.calculator = calculator;
        this.policy = policy;
    }

    public PlanDtos.PlanResultResponse preview(String userId) {
        return PlanDtos.PlanResultResponse.from(calculate(snapshot(userId), null));
    }

    @Transactional
    public PlanDtos.CurrentResponse create(String userId, PlanDtos.ConfirmRequest request) {
        if (count("SELECT COUNT(*) FROM health_plans WHERE user_id = ?", userId) > 0) {
            throw conflict("PLAN_ALREADY_EXISTS", "当前计划已存在");
        }
        PlanCalculator.Adjustments adjustments = request == null ? null : request.toAdjustments();
        policy.validateAdjustments(adjustments);
        PlanPolicy.ProfileSnapshot profile = snapshot(userId);
        PlanCalculator.Result result = calculate(profile, adjustments);
        String planId = UUID.randomUUID().toString();
        LocalDate today = LocalDate.now();
        Instant now = Instant.now();
        jdbc.update("""
                INSERT INTO health_plans
                (id,user_id,status,phase_start_date,phase_end_date,current_version,created_at,updated_at)
                VALUES (?,?,'ACTIVE',?,?,1,?,?)
                """, planId, userId, today, today.plusDays(27), Timestamp.from(now), Timestamp.from(now));
        insertVersion(planId, 1, profile, result, request == null ? null : request.reason());
        jdbc.update("UPDATE health_profiles SET plan_needs_recalculation=FALSE WHERE user_id=?", userId);
        return current(userId);
    }

    public PlanDtos.CurrentResponse current(String userId) {
        Map<String, Object> plan;
        try {
            plan = jdbc.queryForMap("SELECT * FROM health_plans WHERE user_id=?", userId);
        } catch (EmptyResultDataAccessException exception) {
            return PlanDtos.CurrentResponse.empty();
        }
        Map<String, Object> profileState = jdbc.queryForMap(
                "SELECT plan_needs_recalculation,risk_blocked FROM health_profiles WHERE user_id=?", userId);
        boolean needsRecalculation = bool(profileState, "plan_needs_recalculation");
        boolean riskBlocked = bool(profileState, "risk_blocked");
        Map<String, Object> version = version(plan.get("id").toString(), number(plan, "current_version"));
        String status = plan.get("status").toString();
        String state = riskBlocked ? "RISK_BLOCKED"
                : "PAUSED".equals(status) ? "PAUSED"
                : needsRecalculation ? "NEEDS_RECALCULATION" : "ACTIVE";
        LocalDate effectiveDate = "PAUSED".equals(status)
                ? instant(plan.get("paused_at")).atZone(ZoneId.systemDefault()).toLocalDate() : LocalDate.now();
        int currentWeek = Math.max(1, Math.min(4,
                (int) (ChronoUnit.DAYS.between(date(plan, "phase_start_date"), effectiveDate) / 7) + 1));
        return new PlanDtos.CurrentResponse(state, plan.get("id").toString(), number(plan, "current_version"), currentWeek,
                date(plan, "phase_start_date"), date(plan, "phase_end_date"), instant(plan.get("paused_at")),
                needsRecalculation, riskBlocked ? null : response(version));
    }

    public List<PlanDtos.HistoryResponse> history(String userId, int limit) {
        Map<String, Object> plan = ownedPlan(userId, null, false);
        return jdbc.query("""
                SELECT version_number,rule_version,profile_version,calculation_date,target_kcal,water_ml,
                       exercise_days,exercise_minutes,sleep_hours,adjustment_reason,created_at
                FROM health_plan_versions WHERE plan_id=? ORDER BY version_number DESC LIMIT ?
                """, (rs, row) -> new PlanDtos.HistoryResponse(
                rs.getInt("version_number"), rs.getString("rule_version"), rs.getInt("profile_version"),
                rs.getObject("calculation_date", LocalDate.class), rs.getInt("target_kcal"),
                rs.getInt("water_ml"), rs.getInt("exercise_days"), rs.getInt("exercise_minutes"),
                rs.getBigDecimal("sleep_hours"), rs.getString("adjustment_reason"),
                rs.getTimestamp("created_at").toInstant()), plan.get("id"), limit);
    }

    @Transactional
    public PlanDtos.CurrentResponse updateTargets(
            String userId, String planId, PlanDtos.UpdateTargetsRequest request
    ) {
        Map<String, Object> plan = ownedPlan(userId, planId, true);
        requireActive(plan);
        requireVersion(plan, request.expectedVersion());
        if (Boolean.TRUE.equals(jdbc.queryForObject(
                "SELECT plan_needs_recalculation FROM health_profiles WHERE user_id=?", Boolean.class, userId))) {
            throw conflict("PLAN_RECALCULATION_REQUIRED", "健康档案已变化，请先重新计算计划");
        }
        PlanCalculator.Adjustments adjustments = request.toAdjustments();
        if (adjustments.targetKcal() == null && adjustments.waterMl() == null
                && adjustments.exerciseDays() == null && adjustments.exerciseMinutes() == null
                && adjustments.sleepHours() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PLAN_TARGETS_REQUIRED", "请至少调整一项目标");
        }
        policy.validateAdjustments(adjustments);
        PlanPolicy.ProfileSnapshot profile = snapshot(userId);
        PlanCalculator.Result result = calculate(profile, adjustments);
        int nextVersion = request.expectedVersion() + 1;
        optimisticVersionUpdate(userId, planId, request.expectedVersion(), nextVersion, null);
        insertVersion(planId, nextVersion, profile, result,
                request.reason() == null || request.reason().isBlank() ? "用户调整目标" : request.reason());
        return current(userId);
    }

    @Transactional
    public PlanDtos.CurrentResponse recalculate(
            String userId, String planId, PlanDtos.RecalculateRequest request
    ) {
        Map<String, Object> plan = ownedPlan(userId, planId, true);
        requireActive(plan);
        requireVersion(plan, request.expectedVersion());
        PlanPolicy.ProfileSnapshot profile = snapshot(userId);
        PlanCalculator.Result result = calculate(profile, null);
        int nextVersion = request.expectedVersion() + 1;
        LocalDate today = LocalDate.now();
        optimisticVersionUpdate(userId, planId, request.expectedVersion(), nextVersion, today);
        insertVersion(planId, nextVersion, profile, result, "健康档案变化后重新计算");
        jdbc.update("UPDATE health_profiles SET plan_needs_recalculation=FALSE WHERE user_id=?", userId);
        return current(userId);
    }

    @Transactional
    public PlanDtos.CurrentResponse pause(String userId, String planId) {
        Map<String, Object> plan = ownedPlan(userId, planId, true);
        if ("PAUSED".equals(plan.get("status"))) {
            return current(userId);
        }
        jdbc.update("UPDATE health_plans SET status='PAUSED',paused_at=?,updated_at=? WHERE id=? AND user_id=?",
                Timestamp.from(Instant.now()), Timestamp.from(Instant.now()), planId, userId);
        return current(userId);
    }

    @Transactional
    public PlanDtos.CurrentResponse resume(String userId, String planId) {
        Map<String, Object> plan = ownedPlan(userId, planId, true);
        if ("ACTIVE".equals(plan.get("status"))) {
            return current(userId);
        }
        Instant pausedAt = instant(plan.get("paused_at"));
        long pausedDays = Math.max(0, ChronoUnit.DAYS.between(
                pausedAt.atZone(ZoneId.systemDefault()).toLocalDate(), LocalDate.now()));
        LocalDate start = date(plan, "phase_start_date").plusDays(pausedDays);
        LocalDate end = date(plan, "phase_end_date").plusDays(pausedDays);
        jdbc.update("""
                UPDATE health_plans SET status='ACTIVE',paused_at=NULL,phase_start_date=?,phase_end_date=?,updated_at=?
                WHERE id=? AND user_id=?
                """, start, end, Timestamp.from(Instant.now()), planId, userId);
        return current(userId);
    }

    private PlanPolicy.ProfileSnapshot snapshot(String userId) {
        Map<String, Object> row;
        try {
            row = jdbc.queryForMap("""
                    SELECT hp.completed,hp.risk_blocked,hp.birth_date,hp.sex,hp.metabolic_basis,
                           hp.height_cm,hp.activity_level,hp.sleep_hours,hp.exercise_days,hp.version,
                           hg.goal_type,hg.target_weight_kg,hg.target_date,bm.weight_kg
                    FROM health_profiles hp
                    JOIN health_goals hg ON hg.user_id=hp.user_id
                    JOIN body_measurements bm ON bm.id=(
                      SELECT id FROM body_measurements WHERE user_id=hp.user_id
                      ORDER BY measured_at DESC,id DESC LIMIT 1)
                    WHERE hp.user_id=?
                    """, userId);
        } catch (EmptyResultDataAccessException exception) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PROFILE_INCOMPLETE",
                    "请先完成全部健康档案步骤");
        }
        LocalDate birthDate = date(row, "birth_date");
        String sex = string(row, "sex");
        String basis = string(row, "metabolic_basis");
        if (!"OTHER".equals(sex) && ("MALE".equals(sex) || "FEMALE".equals(sex))) {
            basis = sex;
        }
        PlanPolicy.ProfileSnapshot profile = new PlanPolicy.ProfileSnapshot(
                bool(row, "completed"), bool(row, "risk_blocked"),
                birthDate == null ? 0 : Period.between(birthDate, LocalDate.now()).getYears(),
                sex, basis, decimal(row, "height_cm"), decimal(row, "weight_kg"),
                string(row, "activity_level"), decimal(row, "sleep_hours"), number(row, "exercise_days"),
                string(row, "goal_type"), decimal(row, "target_weight_kg"), date(row, "target_date"),
                number(row, "version"));
        policy.validateProfile(profile);
        return profile;
    }

    private PlanCalculator.Result calculate(
            PlanPolicy.ProfileSnapshot profile, PlanCalculator.Adjustments adjustments
    ) {
        return calculator.calculate(new PlanCalculator.Input(
                profile.age(), profile.metabolicBasis(), profile.heightCm(), profile.weightKg(),
                profile.activityLevel(), profile.targetWeightKg(), profile.targetDate(), profile.sleepHours(),
                profile.exerciseDays(), LocalDate.now(), adjustments));
    }

    private void insertVersion(
            String planId, int versionNumber, PlanPolicy.ProfileSnapshot profile,
            PlanCalculator.Result result, String reason
    ) {
        jdbc.update("""
                INSERT INTO health_plan_versions
                (id,plan_id,version_number,rule_version,profile_version,calculation_date,age,metabolic_basis,
                 height_cm,weight_kg,activity_level,target_weight_kg,requested_target_date,bmi,bmr_kcal,
                 tdee_kcal,target_kcal,protein_g,carbs_g,fat_g,water_ml,exercise_days,exercise_minutes,
                 sleep_hours,expected_weekly_change_kg,suggested_target_date,safety_message,adjustment_reason)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, UUID.randomUUID().toString(), planId, versionNumber, result.ruleVersion(),
                profile.profileVersion(), LocalDate.now(), profile.age(), profile.metabolicBasis(),
                profile.heightCm(), profile.weightKg(), profile.activityLevel(), profile.targetWeightKg(),
                profile.targetDate(), result.bmi(), result.bmrKcal(), result.tdeeKcal(), result.targetKcal(),
                result.proteinG(), result.carbsG(), result.fatG(), result.waterMl(), result.exerciseDays(),
                result.exerciseMinutes(), result.sleepHours(), result.expectedWeeklyChangeKg(),
                result.suggestedTargetDate(), result.safetyMessage(), blankToNull(reason));
    }

    private void optimisticVersionUpdate(
            String userId, String planId, int expectedVersion, int nextVersion, LocalDate newPhaseStart
    ) {
        int updated;
        if (newPhaseStart == null) {
            updated = jdbc.update("""
                    UPDATE health_plans SET current_version=?,updated_at=?
                    WHERE id=? AND user_id=? AND current_version=? AND status='ACTIVE'
                    """, nextVersion, Timestamp.from(Instant.now()), planId, userId, expectedVersion);
        } else {
            updated = jdbc.update("""
                    UPDATE health_plans SET current_version=?,phase_start_date=?,phase_end_date=?,updated_at=?
                    WHERE id=? AND user_id=? AND current_version=? AND status='ACTIVE'
                    """, nextVersion, newPhaseStart, newPhaseStart.plusDays(27), Timestamp.from(Instant.now()),
                    planId, userId, expectedVersion);
        }
        if (updated == 0) {
            throw conflict("PLAN_VERSION_CONFLICT", "计划已更新，请刷新后重试");
        }
    }

    private Map<String, Object> ownedPlan(String userId, String planId, boolean requireId) {
        try {
            if (requireId) {
                return jdbc.queryForMap("SELECT * FROM health_plans WHERE id=? AND user_id=?", planId, userId);
            }
            return jdbc.queryForMap("SELECT * FROM health_plans WHERE user_id=?", userId);
        } catch (EmptyResultDataAccessException exception) {
            throw new ApiException(HttpStatus.NOT_FOUND, "PLAN_NOT_FOUND", "计划不存在");
        }
    }

    private Map<String, Object> version(String planId, int version) {
        return jdbc.queryForMap("SELECT * FROM health_plan_versions WHERE plan_id=? AND version_number=?",
                planId, version);
    }

    private PlanDtos.PlanResultResponse response(Map<String, Object> row) {
        return new PlanDtos.PlanResultResponse(string(row, "rule_version"), true, decimal(row, "bmi"),
                number(row, "bmr_kcal"), number(row, "tdee_kcal"), number(row, "target_kcal"),
                number(row, "protein_g"), number(row, "carbs_g"), number(row, "fat_g"),
                number(row, "water_ml"), number(row, "exercise_days"), number(row, "exercise_minutes"),
                decimal(row, "sleep_hours"), decimal(row, "expected_weekly_change_kg"),
                date(row, "suggested_target_date"), string(row, "safety_message"));
    }

    private void requireActive(Map<String, Object> plan) {
        if (!"ACTIVE".equals(plan.get("status"))) {
            throw conflict("PLAN_STATE_CONFLICT", "请先恢复计划再执行此操作");
        }
    }

    private void requireVersion(Map<String, Object> plan, int expectedVersion) {
        if (number(plan, "current_version") != expectedVersion) {
            throw conflict("PLAN_VERSION_CONFLICT", "计划已更新，请刷新后重试");
        }
    }

    private ApiException conflict(String code, String message) {
        return new ApiException(HttpStatus.CONFLICT, code, message);
    }

    private int count(String sql, Object... arguments) {
        Integer value = jdbc.queryForObject(sql, Integer.class, arguments);
        return value == null ? 0 : value;
    }

    private int number(Map<String, Object> row, String key) {
        return ((Number) row.get(key)).intValue();
    }

    private BigDecimal decimal(Map<String, Object> row, String key) {
        Object value = row.get(key);
        return value == null ? null : value instanceof BigDecimal decimal ? decimal : new BigDecimal(value.toString());
    }

    private boolean bool(Map<String, Object> row, String key) {
        return Boolean.TRUE.equals(row.get(key));
    }

    private String string(Map<String, Object> row, String key) {
        Object value = row.get(key);
        return value == null ? null : value.toString();
    }

    private LocalDate date(Map<String, Object> row, String key) {
        Object value = row.get(key);
        if (value == null) return null;
        if (value instanceof LocalDate localDate) return localDate;
        if (value instanceof java.sql.Date sqlDate) return sqlDate.toLocalDate();
        return LocalDate.parse(value.toString());
    }

    private Instant instant(Object value) {
        return value == null ? null : ((Timestamp) value).toInstant();
    }

    private String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }
}
