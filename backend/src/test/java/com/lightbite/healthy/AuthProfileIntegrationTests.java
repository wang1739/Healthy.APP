package com.lightbite.healthy;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;

import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;

@SpringBootTest
@ActiveProfiles("test")
class AuthProfileIntegrationTests {

    @Autowired
    private WebApplicationContext applicationContext;

    @Autowired
    private JdbcTemplate jdbc;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext)
                .apply(springSecurity())
                .build();
    }

    @Test
    void newUserCanLoginCompleteProfileAndRefreshSession() throws Exception {
        String sendBody = mockMvc.perform(post("/api/v1/auth/sms/send")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"phone":"13800138000","purpose":"LOGIN"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.debugCode").isNotEmpty())
                .andReturn().getResponse().getContentAsString();
        String code = JsonPath.read(sendBody, "$.debugCode");

        String loginBody = mockMvc.perform(post("/api/v1/auth/sms/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"phone":"13800138000","code":"%s","deviceName":"测试手机",
                                 "password":"Healthy123","acceptedTerms":true}
                                """.formatted(code)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").isNotEmpty())
                .andExpect(jsonPath("$.refreshToken").isNotEmpty())
                .andExpect(jsonPath("$.profileComplete").value(false))
                .andReturn().getResponse().getContentAsString();
        String accessToken = JsonPath.read(loginBody, "$.accessToken");
        String refreshToken = JsonPath.read(loginBody, "$.refreshToken");

        mockMvc.perform(post("/api/v1/auth/password/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"phone":"13800138000","password":"Healthy123","deviceName":"备用设备"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").isNotEmpty());

        mockMvc.perform(get("/api/v1/account").header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.phone").value("13800138000"));

        mockMvc.perform(put("/api/v1/profile")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"birthDate":"1995-06-18","sex":"FEMALE","heightCm":165,
                                 "activityLevel":"LIGHT","workStyle":"SEDENTARY","sleepHours":7.5,
                                 "exerciseDays":3,"goalType":"FAT_LOSS","targetWeightKg":55,
                                 "targetDate":"2027-01-01","currentStep":5}
                                """))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/v1/profile/measurements")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"weightKg":62.5,"waistCm":72,"bodyFatPercent":25.2}
                                """))
                .andExpect(status().isCreated());

        mockMvc.perform(put("/api/v1/profile/preferences")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"dietType":"BALANCED","allergies":"花生","avoidFoods":"香菜"}
                                """))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/v1/profile/risk-assessment")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"pregnant":false,"breastfeeding":false,"eatingDisorderRisk":false,
                                 "seriousChronicDisease":false,"unsafeTarget":false}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.riskBlocked").value(false));

        mockMvc.perform(put("/api/v1/profile")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{" + "\"currentStep\":7,\"completed\":true}"))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/v1/profile/completeness")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.complete").value(true))
                .andExpect(jsonPath("$.percentage").value(100));

        mockMvc.perform(post("/api/v1/auth/token/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"refreshToken\":\"" + refreshToken + "\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").isNotEmpty())
                .andExpect(jsonPath("$.refreshToken").isNotEmpty());
    }

    @Test
    void wrongVerificationCodeIsRejected() throws Exception {
        mockMvc.perform(post("/api/v1/auth/sms/send")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"13900139000\",\"purpose\":\"LOGIN\"}"))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/v1/auth/sms/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"phone":"13900139000","code":"000000","deviceName":"测试手机",
                                 "acceptedTerms":true}
                                """))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("INVALID_VERIFICATION_CODE"));
    }

    @Test
    void migratedCompletedOtherProfileReturnsToBasicsUntilBasisIsSelected() throws Exception {
        String userId = "legacy-other-profile";
        jdbc.update("MERGE INTO users (id, phone, status) KEY(id) VALUES (?, ?, 'ACTIVE')",
                userId, "13700137000");
        jdbc.update("DELETE FROM health_profiles WHERE user_id=?", userId);
        jdbc.update("""
                INSERT INTO health_profiles
                (user_id,birth_date,sex,metabolic_basis,height_cm,activity_level,work_style,sleep_hours,
                 exercise_days,current_step,completed,risk_blocked)
                VALUES (?,'1990-05-06','OTHER',NULL,170,'LIGHT','SEDENTARY',8,3,7,TRUE,FALSE)
                """, userId);

        mockMvc.perform(get("/api/v1/profile/completeness").with(user(userId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.complete").value(false))
                .andExpect(jsonPath("$.currentStep").value(0))
                .andExpect(jsonPath("$.percentage").value(99))
                .andExpect(jsonPath("$.metabolicBasisRequired").value(true))
                .andExpect(jsonPath("$.sex").value("OTHER"))
                .andExpect(jsonPath("$.birthDate").value("1990-05-06"));
        mockMvc.perform(get("/api/v1/account").with(user(userId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.profileComplete").value(false));

        mockMvc.perform(put("/api/v1/profile").with(user(userId))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"metabolicBasis\":\"FEMALE\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.complete").value(true))
                .andExpect(jsonPath("$.currentStep").value(7));
        mockMvc.perform(get("/api/v1/account").with(user(userId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.profileComplete").value(true));
    }
}
