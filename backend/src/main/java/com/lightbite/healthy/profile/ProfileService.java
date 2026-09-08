package com.lightbite.healthy.profile;

import com.lightbite.healthy.common.api.ApiException;
import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.Period;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProfileService {

    private static final Set<String> SEXES = Set.of("FEMALE", "MALE", "OTHER");
    private static final Set<String> METABOLIC_BASES = Set.of("FEMALE", "MALE");
    private static final Set<String> ACTIVITY_LEVELS = Set.of("LOW", "LIGHT", "MODERATE", "HIGH");
    private static final Set<String> WORK_STYLES = Set.of("SEDENTARY", "MIXED", "ACTIVE");
    private static final Set<String> GOAL_TYPES = Set.of("FAT_LOSS", "MUSCLE_GAIN", "MAINTAIN", "BETTER_DIET");
    private static final Set<String> DIET_TYPES = Set.of("BALANCED", "VEGETARIAN", "LOW_CARB", "HIGH_PROTEIN");

    private final JdbcTemplate jdbc;

    public ProfileService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Transactional
    public ProfileDtos.CompletenessResponse saveProfile(String userId, ProfileDtos.ProfileRequest request) {
        ensureProfile(userId);
        Map<String, Object> existing = jdbc.queryForMap("SELECT * FROM health_profiles WHERE user_id = ?", userId);
        String effectiveSex = request.sex() != null ? request.sex() : (String) existing.get("sex");
        boolean wasComplete = Boolean.TRUE.equals(jdbc.queryForObject(
                "SELECT completed FROM health_profiles WHERE user_id = ?", Boolean.class, userId));
        boolean keyDataChanged = changedDate(existing.get("birth_date"), request.birthDate())
                || changed(existing.get("sex"), request.sex())
                || changedNumber(existing.get("height_cm"), request.heightCm())
                || changed(existing.get("activity_level"), request.activityLevel())
                || ("OTHER".equals(effectiveSex)
                && changed(existing.get("metabolic_basis"), request.metabolicBasis()));

        if (request.birthDate() != null) {
            if (request.birthDate().isAfter(LocalDate.now()) || request.birthDate().isBefore(LocalDate.now().minusYears(120))) {
                throw invalid("birthDate", "出生日期不正确");
            }
            jdbc.update("UPDATE health_profiles SET birth_date = ? WHERE user_id = ?", request.birthDate(), userId);
        }
        if (request.sex() != null) {
            requireEnum(request.sex(), SEXES, "sex");
            String automaticBasis = "OTHER".equals(request.sex()) ? request.metabolicBasis() : request.sex();
            jdbc.update("UPDATE health_profiles SET sex = ?, metabolic_basis = ? WHERE user_id = ?",
                    request.sex(), automaticBasis, userId);
        }
        if (request.metabolicBasis() != null) {
            requireEnum(request.metabolicBasis(), METABOLIC_BASES, "metabolicBasis");
            String sex = request.sex() != null ? request.sex() : (String) existing.get("sex");
            if ("OTHER".equals(sex)) {
                jdbc.update("UPDATE health_profiles SET metabolic_basis = ? WHERE user_id = ?",
                        request.metabolicBasis(), userId);
            }
        }
        if (request.heightCm() != null) {
            jdbc.update("UPDATE health_profiles SET height_cm = ? WHERE user_id = ?", request.heightCm(), userId);
        }
        if (request.activityLevel() != null) {
            requireEnum(request.activityLevel(), ACTIVITY_LEVELS, "activityLevel");
            jdbc.update("UPDATE health_profiles SET activity_level = ? WHERE user_id = ?", request.activityLevel(), userId);
        }
        if (request.workStyle() != null) {
            requireEnum(request.workStyle(), WORK_STYLES, "workStyle");
            jdbc.update("UPDATE health_profiles SET work_style = ? WHERE user_id = ?", request.workStyle(), userId);
        }
        if (request.sleepHours() != null) {
            jdbc.update("UPDATE health_profiles SET sleep_hours = ? WHERE user_id = ?", request.sleepHours(), userId);
        }
        if (request.exerciseDays() != null) {
            jdbc.update("UPDATE health_profiles SET exercise_days = ? WHERE user_id = ?", request.exerciseDays(), userId);
        }
        if (request.goalType() != null || request.targetWeightKg() != null || request.targetDate() != null) {
            Map<String, Object> currentGoal;
            try {
                currentGoal = jdbc.queryForMap("SELECT * FROM health_goals WHERE user_id = ?", userId);
            } catch (EmptyResultDataAccessException exception) {
                currentGoal = Map.of();
            }
            String goalType = request.goalType() != null
                    ? request.goalType() : (String) currentGoal.get("goal_type");
            BigDecimal targetWeight = request.targetWeightKg() != null
                    ? request.targetWeightKg() : (BigDecimal) currentGoal.get("target_weight_kg");
            LocalDate targetDate = request.targetDate() != null
                    ? request.targetDate() : toLocalDate(currentGoal.get("target_date"));
            if (goalType == null) {
                throw invalid("goalType", "请选择健康目标");
            }
            requireEnum(goalType, GOAL_TYPES, "goalType");
            if (targetDate != null && !targetDate.isAfter(LocalDate.now())) {
                throw invalid("targetDate", "目标日期必须晚于今天");
            }
            keyDataChanged = !goalType.equals(currentGoal.get("goal_type"))
                    || changedNumber(currentGoal.get("target_weight_kg"), request.targetWeightKg())
                    || changedDate(currentGoal.get("target_date"), request.targetDate()) || keyDataChanged;
            jdbc.update("DELETE FROM health_goals WHERE user_id = ?", userId);
            jdbc.update("""
                    INSERT INTO health_goals (user_id, goal_type, target_weight_kg, target_date)
                    VALUES (?, ?, ?, ?)
                    """, userId, goalType, targetWeight, targetDate);
        }
        if (request.currentStep() != null) {
            jdbc.update("UPDATE health_profiles SET current_step = ? WHERE user_id = ?", request.currentStep(), userId);
        }
        if (wasComplete && keyDataChanged) {
            jdbc.update("UPDATE health_profiles SET plan_needs_recalculation = TRUE WHERE user_id = ?", userId);
        }
        if (Boolean.TRUE.equals(request.completed())) {
            validateComplete(userId);
            jdbc.update("UPDATE health_profiles SET completed = TRUE, current_step = 7 WHERE user_id = ?", userId);
        }
        jdbc.update("""
                UPDATE health_profiles SET version = version + 1, updated_at = ? WHERE user_id = ?
                """, Timestamp.from(Instant.now()), userId);
        return completeness(userId);
    }

    @Transactional
    public ProfileDtos.MeasurementResponse addMeasurement(
            String userId,
            ProfileDtos.MeasurementRequest request
    ) {
        if (request.weightKg() == null) {
            throw invalid("weightKg", "请输入体重");
        }
        ensureProfile(userId);
        boolean wasComplete = Boolean.TRUE.equals(jdbc.queryForObject(
                "SELECT completed FROM health_profiles WHERE user_id = ?", Boolean.class, userId));
        String id = UUID.randomUUID().toString();
        Instant now = Instant.now();
        jdbc.update("""
                INSERT INTO body_measurements
                (id, user_id, weight_kg, waist_cm, body_fat_percent, measured_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, id, userId, request.weightKg(), request.waistCm(), request.bodyFatPercent(), Timestamp.from(now));
        jdbc.update("UPDATE health_profiles SET current_step = CASE WHEN current_step < 2 THEN 2 ELSE current_step END WHERE user_id = ?", userId);
        if (wasComplete) {
            jdbc.update("""
                    UPDATE health_profiles
                    SET plan_needs_recalculation = TRUE, version = version + 1, updated_at = ?
                    WHERE user_id = ?
                    """, Timestamp.from(Instant.now()), userId);
        }
        return new ProfileDtos.MeasurementResponse(
                id, request.weightKg(), request.waistCm(), request.bodyFatPercent(), now);
    }

    public List<ProfileDtos.MeasurementResponse> measurements(String userId) {
        return jdbc.query("""
                SELECT id, weight_kg, waist_cm, body_fat_percent, measured_at
                FROM body_measurements WHERE user_id = ? ORDER BY measured_at DESC
                """, (resultSet, rowNum) -> measurement(resultSet), userId);
    }

    @Transactional
    public void savePreferences(String userId, ProfileDtos.PreferencesRequest request) {
        String dietType = request.dietType() == null ? "BALANCED" : request.dietType();
        requireEnum(dietType, DIET_TYPES, "dietType");
        ensureProfile(userId);
        jdbc.update("DELETE FROM dietary_preferences WHERE user_id = ?", userId);
        jdbc.update("""
                INSERT INTO dietary_preferences (user_id, diet_type, allergies, avoid_foods)
                VALUES (?, ?, ?, ?)
                """, userId, dietType, request.allergies(), request.avoidFoods());
        jdbc.update("UPDATE health_profiles SET current_step = CASE WHEN current_step < 4 THEN 4 ELSE current_step END WHERE user_id = ?", userId);
    }

    @Transactional
    public ProfileDtos.RiskResponse saveRisk(String userId, ProfileDtos.RiskRequest request) {
        ensureProfile(userId);
        Map<String, Object> profile = jdbc.queryForMap(
                "SELECT completed, risk_blocked FROM health_profiles WHERE user_id = ?", userId);
        LocalDate birthDate = jdbc.queryForObject(
                "SELECT birth_date FROM health_profiles WHERE user_id = ?", LocalDate.class, userId);
        boolean minor = birthDate != null && Period.between(birthDate, LocalDate.now()).getYears() < 18;
        boolean blocked = minor || request.pregnant() || request.breastfeeding()
                || request.eatingDisorderRisk() || request.seriousChronicDisease() || request.unsafeTarget();
        jdbc.update("""
                INSERT INTO health_risk_answers
                (id, user_id, pregnant, breastfeeding, eating_disorder_risk,
                 serious_chronic_disease, unsafe_target, risk_blocked)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, UUID.randomUUID().toString(), userId, request.pregnant(), request.breastfeeding(),
                request.eatingDisorderRisk(), request.seriousChronicDisease(), request.unsafeTarget(), blocked);
        jdbc.update("UPDATE health_profiles SET risk_blocked = ?, current_step = 6 WHERE user_id = ?", blocked, userId);
        if (Boolean.TRUE.equals(profile.get("completed"))
                && blocked != Boolean.TRUE.equals(profile.get("risk_blocked"))) {
            jdbc.update("""
                    UPDATE health_profiles
                    SET plan_needs_recalculation = TRUE, version = version + 1, updated_at = ?
                    WHERE user_id = ?
                    """, Timestamp.from(Instant.now()), userId);
        }
        return new ProfileDtos.RiskResponse(
                blocked,
                blocked ? "当前情况不适合自动生成普通减脂计划，请咨询医生或注册营养师" : "未发现自动计划拦截项"
        );
    }

    public ProfileDtos.CompletenessResponse completeness(String userId) {
        ensureProfile(userId);
        Map<String, Object> profile = jdbc.queryForMap("""
                SELECT current_step, completed, birth_date, sex, metabolic_basis,
                       risk_blocked, plan_needs_recalculation
                FROM health_profiles WHERE user_id = ?
                """, userId);
        int step = ((Number) profile.get("current_step")).intValue();
        String sex = (String) profile.get("sex");
        String metabolicBasis = (String) profile.get("metabolic_basis");
        boolean complete = Boolean.TRUE.equals(profile.get("completed"))
                && metabolicBasis != null;
        boolean metabolicBasisRequired = "OTHER".equals(sex) && metabolicBasis == null && step > 0;
        return new ProfileDtos.CompletenessResponse(
                metabolicBasisRequired ? 0 : step,
                complete ? 100 : metabolicBasisRequired ? 99 : Math.min(99, step * 100 / 7),
                complete,
                Boolean.TRUE.equals(profile.get("risk_blocked")),
                Boolean.TRUE.equals(profile.get("plan_needs_recalculation")),
                metabolicBasisRequired,
                sex,
                metabolicBasis,
                toLocalDate(profile.get("birth_date"))
        );
    }

    public Map<String, Object> profile(String userId) {
        ensureProfile(userId);
        return jdbc.queryForMap("SELECT * FROM health_profiles WHERE user_id = ?", userId);
    }

    private void ensureProfile(String userId) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM health_profiles WHERE user_id = ?", Integer.class, userId);
        if (count != null && count == 0) {
            jdbc.update("INSERT INTO health_profiles (user_id) VALUES (?)", userId);
        }
    }

    private void validateComplete(String userId) {
        Integer profileReady = jdbc.queryForObject("""
                SELECT COUNT(*) FROM health_profiles
                WHERE user_id = ? AND birth_date IS NOT NULL AND sex IS NOT NULL
                  AND height_cm IS NOT NULL AND activity_level IS NOT NULL AND work_style IS NOT NULL
                  AND sleep_hours IS NOT NULL AND exercise_days IS NOT NULL AND metabolic_basis IS NOT NULL
                """, Integer.class, userId);
        Integer measurements = jdbc.queryForObject(
                "SELECT COUNT(*) FROM body_measurements WHERE user_id = ?", Integer.class, userId);
        Integer goals = jdbc.queryForObject(
                "SELECT COUNT(*) FROM health_goals WHERE user_id = ?", Integer.class, userId);
        Integer preferences = jdbc.queryForObject(
                "SELECT COUNT(*) FROM dietary_preferences WHERE user_id = ?", Integer.class, userId);
        Integer risks = jdbc.queryForObject(
                "SELECT COUNT(*) FROM health_risk_answers WHERE user_id = ?", Integer.class, userId);
        if (profileReady == null || profileReady == 0 || measurements == null || measurements == 0
                || goals == null || goals == 0 || preferences == null || preferences == 0
                || risks == null || risks == 0) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "PROFILE_INCOMPLETE", "请先完成全部健康档案步骤");
        }
    }

    private ProfileDtos.MeasurementResponse measurement(ResultSet resultSet) throws SQLException {
        return new ProfileDtos.MeasurementResponse(
                resultSet.getString("id"),
                resultSet.getBigDecimal("weight_kg"),
                resultSet.getBigDecimal("waist_cm"),
                resultSet.getBigDecimal("body_fat_percent"),
                resultSet.getTimestamp("measured_at").toInstant()
        );
    }

    private void requireEnum(String value, Set<String> values, String field) {
        if (!values.contains(value)) {
            throw invalid(field, "选项不受支持");
        }
    }

    private boolean changed(Object current, Object requested) {
        return requested != null && !requested.equals(current);
    }

    private boolean changedNumber(Object current, BigDecimal requested) {
        return requested != null && (current == null || ((BigDecimal) current).compareTo(requested) != 0);
    }

    private boolean changedDate(Object current, LocalDate requested) {
        return requested != null && !requested.equals(toLocalDate(current));
    }

    private LocalDate toLocalDate(Object value) {
        if (value == null) {
            return null;
        }
        return value instanceof LocalDate date ? date : ((java.sql.Date) value).toLocalDate();
    }

    private ApiException invalid(String field, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "INVALID_" + field.toUpperCase(), message);
    }
}
