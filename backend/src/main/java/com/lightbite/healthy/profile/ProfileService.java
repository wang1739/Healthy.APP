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
        return saveProfile(userId, request, null);
    }

    private ProfileDtos.CompletenessResponse saveProfile(
            String userId, ProfileDtos.ProfileRequest request, Long expectedVersion
    ) {
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
            invalidatePlanPreviews(userId);
        }
        if (Boolean.TRUE.equals(request.completed())) {
            validateComplete(userId);
            jdbc.update("UPDATE health_profiles SET completed = TRUE, current_step = 7 WHERE user_id = ?", userId);
        }
        bumpProfileVersion(userId, expectedVersion);
        return completeness(userId);
    }

    @Transactional
    public ProfileDtos.MeasurementResponse addMeasurement(
            String userId,
            ProfileDtos.MeasurementRequest request
    ) {
        return addMeasurement(userId, request, true);
    }

    private ProfileDtos.MeasurementResponse addMeasurement(
            String userId, ProfileDtos.MeasurementRequest request, boolean incrementVersion
    ) {
        if (request.weightKg() == null) {
            throw invalid("weightKg", "请输入体重");
        }
        ensureProfile(userId);
        boolean wasComplete = Boolean.TRUE.equals(jdbc.queryForObject(
                "SELECT completed FROM health_profiles WHERE user_id = ?", Boolean.class, userId));
        List<BigDecimal> priorWeights = jdbc.query("""
                SELECT weight_kg FROM body_measurements WHERE user_id = ?
                ORDER BY measured_at DESC, id DESC LIMIT 1
                """, (resultSet, rowNum) -> resultSet.getBigDecimal("weight_kg"), userId);
        boolean weightChanged = priorWeights.isEmpty()
                || priorWeights.get(0).compareTo(request.weightKg()) != 0;
        String id = UUID.randomUUID().toString();
        Instant now = Instant.now();
        jdbc.update("""
                INSERT INTO body_measurements
                (id, user_id, weight_kg, waist_cm, body_fat_percent, measured_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, id, userId, request.weightKg(), request.waistCm(), request.bodyFatPercent(), Timestamp.from(now));
        jdbc.update("UPDATE health_profiles SET current_step = CASE WHEN current_step < 2 THEN 2 ELSE current_step END WHERE user_id = ?", userId);
        if (wasComplete && weightChanged) {
            if (incrementVersion) {
                jdbc.update("""
                        UPDATE health_profiles
                        SET plan_needs_recalculation = TRUE, version = version + 1, updated_at = ?
                        WHERE user_id = ?
                        """, Timestamp.from(Instant.now()), userId);
            } else {
                jdbc.update("UPDATE health_profiles SET plan_needs_recalculation = TRUE WHERE user_id = ?", userId);
            }
            invalidatePlanPreviews(userId);
        }
        return new ProfileDtos.MeasurementResponse(
                id, request.weightKg(), request.waistCm(), request.bodyFatPercent(), now);
    }

    public List<ProfileDtos.MeasurementResponse> measurements(String userId) {
        return jdbc.query("""
                SELECT id, weight_kg, waist_cm, body_fat_percent, measured_at
                FROM body_measurements WHERE user_id = ? ORDER BY measured_at DESC, id DESC
                """, (resultSet, rowNum) -> measurement(resultSet), userId);
    }

    @Transactional
    public void savePreferences(String userId, ProfileDtos.PreferencesRequest request) {
        writePreferences(userId, request);
    }

    private void writePreferences(String userId, ProfileDtos.PreferencesRequest request) {
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
        return saveRisk(userId, request, null);
    }

    private ProfileDtos.RiskResponse saveRisk(
            String userId, ProfileDtos.RiskRequest request, Long expectedVersion
    ) {
        ensureProfile(userId);
        boolean wasBlocked = Boolean.TRUE.equals(jdbc.queryForObject(
                "SELECT risk_blocked FROM health_profiles WHERE user_id = ?", Boolean.class, userId));
        LocalDate birthDate = jdbc.queryForObject(
                "SELECT birth_date FROM health_profiles WHERE user_id = ?", LocalDate.class, userId);
        boolean minor = birthDate != null && Period.between(birthDate, LocalDate.now()).getYears() < 18;
        boolean pregnant = Boolean.TRUE.equals(request.pregnant());
        boolean breastfeeding = Boolean.TRUE.equals(request.breastfeeding());
        boolean eatingDisorderRisk = Boolean.TRUE.equals(request.eatingDisorderRisk());
        boolean seriousChronicDisease = Boolean.TRUE.equals(request.seriousChronicDisease());
        boolean unsafeTarget = Boolean.TRUE.equals(request.unsafeTarget());
        boolean blocked = minor || pregnant || breastfeeding
                || eatingDisorderRisk || seriousChronicDisease || unsafeTarget;
        jdbc.update("""
                INSERT INTO health_risk_answers
                (id, user_id, pregnant, breastfeeding, eating_disorder_risk,
                 serious_chronic_disease, unsafe_target, risk_blocked)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, UUID.randomUUID().toString(), userId, pregnant, breastfeeding,
                eatingDisorderRisk, seriousChronicDisease, unsafeTarget, blocked);
        jdbc.update("UPDATE health_profiles SET risk_blocked = ?, current_step = 6 WHERE user_id = ?", blocked, userId);
        if (blocked != wasBlocked) {
            Instant now = Instant.now();
            invalidatePlanPreviews(userId);
            if (blocked) {
                jdbc.update("""
                        UPDATE health_plans SET status = 'PAUSED', paused_at = ?, updated_at = ?
                        WHERE user_id = ? AND status = 'ACTIVE'
                        """, Timestamp.from(now), Timestamp.from(now), userId);
            }
        }
        if (expectedVersion != null || blocked != wasBlocked) {
            bumpProfileVersion(userId, expectedVersion);
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

    @Transactional
    public ProfileDtos.ProfileSectionsResponse saveBasicInfo(String userId, ProfileDtos.BasicInfoRequest request) {
        requireAny("请至少修改一项基本信息",
                request.birthDate(), request.sex(), request.metabolicBasis());
        saveProfile(userId, new ProfileDtos.ProfileRequest(request.birthDate(), request.sex(),
                request.metabolicBasis(), null, null, null, null, null, null, null, null, null, null),
                request.expectedVersion());
        return sections(userId);
    }

    @Transactional
    public ProfileDtos.ProfileSectionsResponse saveBodyData(String userId, ProfileDtos.BodyDataRequest request) {
        requireAny("请至少修改一项身体数据",
                request.heightCm(), request.weightKg(), request.waistCm(), request.bodyFatPercent());
        saveProfile(userId, new ProfileDtos.ProfileRequest(null, null, null, request.heightCm(),
                null, null, null, null, null, null, null, null, null), request.expectedVersion());
        if (request.weightKg() != null || request.waistCm() != null || request.bodyFatPercent() != null) {
            List<ProfileDtos.MeasurementResponse> measurements = jdbc.query("""
                        SELECT id, weight_kg, waist_cm, body_fat_percent, measured_at
                        FROM body_measurements WHERE user_id = ?
                        ORDER BY measured_at DESC, id DESC LIMIT 1
                        """, (resultSet, rowNum) -> measurement(resultSet), userId);
            ProfileDtos.MeasurementResponse latest = measurements.isEmpty() ? null : measurements.get(0);
            addMeasurement(userId, new ProfileDtos.MeasurementRequest(
                    request.weightKg() != null ? request.weightKg() : latest == null ? null : latest.weightKg(),
                    request.waistCm() != null ? request.waistCm() : latest == null ? null : latest.waistCm(),
                    request.bodyFatPercent() != null
                            ? request.bodyFatPercent() : latest == null ? null : latest.bodyFatPercent()), false);
        }
        return sections(userId);
    }

    @Transactional
    public ProfileDtos.ProfileSectionsResponse saveLifestyle(String userId, ProfileDtos.LifestyleRequest request) {
        requireAny("请至少修改一项生活方式",
                request.activityLevel(), request.workStyle(), request.sleepHours(), request.exerciseDays());
        saveProfile(userId, new ProfileDtos.ProfileRequest(null, null, null, null, request.activityLevel(),
                request.workStyle(), request.sleepHours(), request.exerciseDays(), null, null, null, null, null),
                request.expectedVersion());
        return sections(userId);
    }

    @Transactional
    public ProfileDtos.ProfileSectionsResponse saveHealthGoal(String userId, ProfileDtos.HealthGoalRequest request) {
        requireAny("请至少修改一项健康目标",
                request.goalType(), request.targetWeightKg(), request.targetDate());
        if (request.goalType() != null && !"FAT_LOSS".equals(request.goalType())) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "PLAN_GOAL_UNSUPPORTED", "当前目标的个性计划尚未开放");
        }
        saveProfile(userId, new ProfileDtos.ProfileRequest(null, null, null, null, null, null, null, null,
                request.goalType(), request.targetWeightKg(), request.targetDate(), null, null),
                request.expectedVersion());
        return sections(userId);
    }

    @Transactional
    public ProfileDtos.ProfileSectionsResponse saveDietaryPreferences(
            String userId, ProfileDtos.PreferencesRequest request
    ) {
        long expectedVersion = requireExpectedVersion(request.expectedVersion());
        if (request.dietType() == null || request.dietType().isBlank()) {
            throw invalid("dietType", "请选择饮食方式");
        }
        writePreferences(userId, request);
        bumpProfileVersion(userId, expectedVersion);
        return sections(userId);
    }

    @Transactional
    public ProfileDtos.ProfileSectionsResponse saveRiskInfo(String userId, ProfileDtos.RiskRequest request) {
        saveRisk(userId, request, requireExpectedVersion(request.expectedVersion()));
        return sections(userId);
    }

    public ProfileDtos.ProfileSectionsResponse sections(String userId) {
        ensureProfile(userId);
        Map<String, Object> profile = jdbc.queryForMap("SELECT * FROM health_profiles WHERE user_id = ?", userId);
        List<ProfileDtos.MeasurementResponse> measurements = jdbc.query("""
                SELECT id, weight_kg, waist_cm, body_fat_percent, measured_at
                FROM body_measurements WHERE user_id = ? ORDER BY measured_at DESC, id DESC LIMIT 1
                """, (resultSet, rowNum) -> measurement(resultSet), userId);
        List<Map<String, Object>> preferences = jdbc.queryForList(
                "SELECT diet_type, allergies, avoid_foods FROM dietary_preferences WHERE user_id = ?", userId);
        List<Map<String, Object>> goals = jdbc.queryForList(
                "SELECT goal_type, target_weight_kg, target_date FROM health_goals WHERE user_id = ?", userId);
        List<Map<String, Object>> risks = jdbc.queryForList("""
                SELECT pregnant, breastfeeding, eating_disorder_risk, serious_chronic_disease,
                       unsafe_target, risk_blocked
                FROM health_risk_answers WHERE user_id = ? ORDER BY created_at DESC, id DESC LIMIT 1
                """, userId);
        Map<String, Object> preference = preferences.isEmpty() ? Map.of() : preferences.get(0);
        Map<String, Object> goal = goals.isEmpty() ? Map.of() : goals.get(0);
        Map<String, Object> risk = risks.isEmpty() ? Map.of() : risks.get(0);
        return new ProfileDtos.ProfileSectionsResponse(
                new ProfileDtos.BasicInfoResponse(toLocalDate(profile.get("birth_date")),
                        (String) profile.get("sex"), (String) profile.get("metabolic_basis")),
                new ProfileDtos.BodyDataResponse((BigDecimal) profile.get("height_cm"),
                        measurements.isEmpty() ? null : measurements.get(0)),
                new ProfileDtos.LifestyleResponse((String) profile.get("activity_level"),
                        (String) profile.get("work_style"), (BigDecimal) profile.get("sleep_hours"),
                        numberAsInteger(profile.get("exercise_days"))),
                new ProfileDtos.DietaryPreferencesResponse((String) preference.get("diet_type"),
                        (String) preference.get("allergies"), (String) preference.get("avoid_foods")),
                new ProfileDtos.HealthGoalResponse((String) goal.get("goal_type"),
                        (BigDecimal) goal.get("target_weight_kg"), toLocalDate(goal.get("target_date"))),
                new ProfileDtos.RiskInfoResponse(bool(risk.get("pregnant")), bool(risk.get("breastfeeding")),
                        bool(risk.get("eating_disorder_risk")), bool(risk.get("serious_chronic_disease")),
                        bool(risk.get("unsafe_target")), Boolean.TRUE.equals(profile.get("risk_blocked"))),
                Boolean.TRUE.equals(profile.get("completed")) && profile.get("metabolic_basis") != null,
                Boolean.TRUE.equals(profile.get("plan_needs_recalculation")),
                ((Number) profile.get("version")).longValue());
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

    private void invalidatePlanPreviews(String userId) {
        jdbc.update("""
                DELETE FROM health_plan_versions
                WHERE status='PREVIEW' AND plan_id IN (SELECT id FROM health_plans WHERE user_id=? )
                """, userId);
    }

    private Integer numberAsInteger(Object value) {
        return value == null ? null : ((Number) value).intValue();
    }

    private boolean bool(Object value) {
        return Boolean.TRUE.equals(value);
    }

    private void requireAny(String message, Object... values) {
        for (Object value : values) {
            if (value != null) {
                return;
            }
        }
        throw new ApiException(HttpStatus.BAD_REQUEST, "PROFILE_SECTION_EMPTY", message);
    }

    private long requireExpectedVersion(Long expectedVersion) {
        if (expectedVersion == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "PROFILE_VERSION_REQUIRED", "请刷新健康档案后重试");
        }
        return expectedVersion;
    }

    private void bumpProfileVersion(String userId, Long expectedVersion) {
        Timestamp now = Timestamp.from(Instant.now());
        int updated = expectedVersion == null
                ? jdbc.update("UPDATE health_profiles SET version = version + 1, updated_at = ? WHERE user_id = ?",
                        now, userId)
                : jdbc.update("""
                        UPDATE health_profiles SET version = version + 1, updated_at = ?
                        WHERE user_id = ? AND version = ?
                        """, now, userId, expectedVersion);
        if (updated == 0) {
            throw new ApiException(HttpStatus.CONFLICT,
                    "PROFILE_VERSION_CONFLICT", "健康档案已更新，请刷新后重试");
        }
    }

    private ApiException invalid(String field, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "INVALID_" + field.toUpperCase(), message);
    }
}
