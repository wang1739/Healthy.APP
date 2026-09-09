package com.lightbite.healthy.today;

import com.lightbite.healthy.activity.ActivityDtos;
import com.lightbite.healthy.activity.ActivityService;
import com.lightbite.healthy.plan.PlanDtos;
import com.lightbite.healthy.plan.PlanService;
import com.lightbite.healthy.nutrition.NutritionDtos;
import com.lightbite.healthy.nutrition.NutritionService;
import com.lightbite.healthy.profile.ProfileDtos;
import com.lightbite.healthy.profile.ProfileService;
import com.lightbite.healthy.hydration.HydrationDtos;
import com.lightbite.healthy.hydration.HydrationService;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class TodayService {

    private static final String LOAD_ERROR = "该项数据暂时无法加载";
    private static final TodayDtos.Module COMING_SOON =
            new TodayDtos.Module(TodayDtos.ModuleStatus.COMING_SOON, "记录功能待接入");

    private final PlanService plans;
    private final ProfileService profiles;
    private final NutritionService nutrition;
    private final HydrationService hydration;
    private final ActivityService activity;

    public TodayService(
            PlanService plans, ProfileService profiles, NutritionService nutrition, HydrationService hydration,
            ActivityService activity
    ) {
        this.plans = plans;
        this.profiles = profiles;
        this.nutrition = nutrition;
        this.hydration = hydration;
        this.activity = activity;
    }

    public TodayDtos.TodayResponse get(String userId, LocalDate date) {
        return get(userId, date, null);
    }

    public TodayDtos.TodayResponse get(String userId, LocalDate date, String timezone) {
        ProfileDtos.CompletenessResponse profile = profile(userId);
        TodayDtos.PlanModule plan = plan(userId);
        if (profile != null && !profile.complete()) {
            plan = hiddenPlan("PROFILE_INCOMPLETE");
        }
        TodayDtos.WeightModule weight = weight(userId);
        TodayDtos.HydrationModule hydrationModule = profile != null && !profile.complete()
                ? new TodayDtos.HydrationModule(TodayDtos.ModuleStatus.PROFILE_INCOMPLETE,
                        null, null, null, null, "请先完成健康档案")
                : hydration(userId, date, timezone);
        return new TodayDtos.TodayResponse(
                date, plan, weight, nutrition(userId, date), hydrationModule, activity(userId, date, timezone),
                COMING_SOON, COMING_SOON,
                nextAction(profile, plan));
    }

    private TodayDtos.ActivityModule activity(String userId, LocalDate date, String timezone) {
        try {
            String zone = timezone == null || timezone.isBlank()
                    ? ZoneId.systemDefault().getId() : timezone;
            ActivityDtos.TodaySummary summary = activity.todaySummary(userId, date, zone);
            ActivityDtos.DayResponse day = summary.day();
            ActivityDtos.WeekResponse week = summary.week();
            TodayDtos.ModuleStatus status = activityStatus(day.status(), week.planState());
            return new TodayDtos.ActivityModule(status, day.totalDurationMinutes(), day.totalKcal(),
                    day.recordCount(), week.exerciseDays(), week.durationMinutes(), week.targetExerciseDays(),
                    week.targetDurationMinutes(), null);
        } catch (RuntimeException exception) {
            return new TodayDtos.ActivityModule(TodayDtos.ModuleStatus.ERROR,
                    null, null, null, null, null, null, null, LOAD_ERROR);
        }
    }

    private TodayDtos.ModuleStatus activityStatus(String dayStatus, String planState) {
        if ("PROFILE_INCOMPLETE".equals(dayStatus)) return TodayDtos.ModuleStatus.PROFILE_INCOMPLETE;
        return switch (planState) {
            case "NO_PLAN" -> TodayDtos.ModuleStatus.NO_PLAN;
            case "PAUSED" -> TodayDtos.ModuleStatus.PAUSED;
            case "NEEDS_RECALCULATION" -> TodayDtos.ModuleStatus.NEEDS_RECALCULATION;
            case "RISK_BLOCKED" -> TodayDtos.ModuleStatus.RISK_BLOCKED;
            default -> "EMPTY".equals(dayStatus) ? TodayDtos.ModuleStatus.EMPTY : TodayDtos.ModuleStatus.READY;
        };
    }

    private TodayDtos.HydrationModule hydration(String userId, LocalDate date, String timezone) {
        try {
            String zone = timezone == null || timezone.isBlank()
                    ? ZoneId.systemDefault().getId() : timezone;
            HydrationDtos.DayResponse day = hydration.day(userId, date, zone);
            return new TodayDtos.HydrationModule(
                    "EMPTY".equals(day.status()) ? TodayDtos.ModuleStatus.EMPTY : TodayDtos.ModuleStatus.READY,
                    day.totalMl(), day.targetMl(), day.remainingMl(), day.progress(), null);
        } catch (RuntimeException exception) {
            return new TodayDtos.HydrationModule(
                    TodayDtos.ModuleStatus.ERROR, null, null, null, null, LOAD_ERROR);
        }
    }

    private TodayDtos.NutritionModule nutrition(String userId, LocalDate date) {
        try {
            NutritionDtos.DayResponse day = nutrition.day(userId, date);
            NutritionDtos.Nutrients total = day.total();
            NutritionDtos.TargetResponse target = day.target();
            return new TodayDtos.NutritionModule(
                    "EMPTY".equals(day.status()) ? TodayDtos.ModuleStatus.EMPTY : TodayDtos.ModuleStatus.READY,
                    total.calories().intValue(), target == null ? null : target.calories(),
                    total.protein(), total.carbs(), total.fat(), null);
        } catch (RuntimeException exception) {
            return new TodayDtos.NutritionModule(
                    TodayDtos.ModuleStatus.ERROR, null, null, null, null, null, LOAD_ERROR);
        }
    }

    private ProfileDtos.CompletenessResponse profile(String userId) {
        try {
            return profiles.completeness(userId);
        } catch (RuntimeException exception) {
            return null;
        }
    }

    private TodayDtos.PlanModule plan(String userId) {
        try {
            PlanDtos.CurrentResponse current = plans.current(userId);
            PlanDtos.PlanResultResponse target = current.plan();
            if (target == null) {
                TodayDtos.ModuleStatus status = "EMPTY".equals(current.state())
                        ? TodayDtos.ModuleStatus.EMPTY : TodayDtos.ModuleStatus.READY;
                return new TodayDtos.PlanModule(status, current.state(), current.currentWeek(),
                        null, null, null, null, null, null, null, null, null);
            }
            return new TodayDtos.PlanModule(
                    TodayDtos.ModuleStatus.READY, current.state(), current.currentWeek(), target.targetKcal(),
                    target.proteinG(), target.carbsG(), target.fatG(), target.waterMl(), target.exerciseDays(),
                    target.exerciseMinutes(), target.sleepHours(), null);
        } catch (RuntimeException exception) {
            return new TodayDtos.PlanModule(TodayDtos.ModuleStatus.ERROR, "ERROR", null,
                    null, null, null, null, null, null, null, null, LOAD_ERROR);
        }
    }

    private TodayDtos.WeightModule weight(String userId) {
        try {
            List<ProfileDtos.MeasurementResponse> values = profiles.measurements(userId);
            if (values.isEmpty()) {
                return new TodayDtos.WeightModule(TodayDtos.ModuleStatus.EMPTY, null, null, null);
            }
            ProfileDtos.MeasurementResponse latest = values.get(0);
            return new TodayDtos.WeightModule(
                    TodayDtos.ModuleStatus.READY, latest.weightKg(), latest.measuredAt(), null);
        } catch (RuntimeException exception) {
            return new TodayDtos.WeightModule(TodayDtos.ModuleStatus.ERROR, null, null, LOAD_ERROR);
        }
    }

    private TodayDtos.PlanModule hiddenPlan(String state) {
        return new TodayDtos.PlanModule(TodayDtos.ModuleStatus.EMPTY, state, null,
                null, null, null, null, null, null, null, null, null);
    }

    private TodayDtos.NextAction nextAction(
            ProfileDtos.CompletenessResponse profile,
            TodayDtos.PlanModule plan
    ) {
        if (profile != null && !profile.complete()) {
            return new TodayDtos.NextAction("COMPLETE_PROFILE", "完善健康档案");
        }
        if ((profile != null && profile.riskBlocked()) || "RISK_BLOCKED".equals(plan.state())) {
            return new TodayDtos.NextAction("VIEW_RISK_GUIDANCE", "查看健康建议");
        }
        if ("PAUSED".equals(plan.state())) {
            return new TodayDtos.NextAction("RESUME_PLAN", "查看暂停的计划");
        }
        if (plan.status() == TodayDtos.ModuleStatus.EMPTY) {
            return new TodayDtos.NextAction("CREATE_PLAN", "生成减脂计划");
        }
        return new TodayDtos.NextAction("VIEW_PLAN", "查看今日目标");
    }
}
