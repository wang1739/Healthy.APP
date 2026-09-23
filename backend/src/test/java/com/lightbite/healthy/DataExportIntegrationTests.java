package com.lightbite.healthy;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import com.lightbite.healthy.datarights.DataExportService;
import com.lightbite.healthy.plan.PlanDtos;
import com.lightbite.healthy.plan.PlanService;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Timestamp;
import java.time.Instant;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.encryption.InvalidPasswordException;
import org.apache.pdfbox.text.PDFTextStripper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import com.lightbite.healthy.common.api.ApiException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;

@SpringBootTest
@ActiveProfiles("test")
class DataExportIntegrationTests {
    private static final String PHONE = "13600003001";
    private static final String PASSWORD = "Healthy-导出-2026";
    @Autowired WebApplicationContext context;
    @Autowired DataExportService exports;
    @Autowired JdbcTemplate jdbc;
    @Autowired PlanService plans;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(context).apply(springSecurity()).build();
        jdbc.queryForList("SELECT id FROM users WHERE phone=?", String.class, PHONE).forEach(userId -> {
            exports.deleteFiles(userId);
            jdbc.update("DELETE FROM data_export_jobs WHERE user_id=?", userId);
        });
        jdbc.update("DELETE FROM meal_entries WHERE id='export-meal'");
        jdbc.update("DELETE FROM hydration_entries WHERE id='export-water'");
        jdbc.update("DELETE FROM verification_codes WHERE phone=?", PHONE);
    }

    @Test
    void createsChineseEncryptedPdfWithMaskedPhoneAndOwnedDownload() throws Exception {
        String token = register();
        String userId = userIdForToken(token);
        jdbc.update("UPDATE users SET display_name='小轻' WHERE id=?", userId);
        jdbc.update("INSERT INTO health_profiles (user_id,birth_date,sex,metabolic_basis,height_cm,activity_level,work_style,"
                + "sleep_hours,exercise_days,current_step,completed,risk_blocked,version) "
                + "VALUES (?,'1995-06-18','FEMALE','FEMALE',165,'LIGHT','SEDENTARY',7.5,2,7,TRUE,FALSE,4)", userId);
        jdbc.update("INSERT INTO body_measurements (id,user_id,weight_kg,waist_cm,body_fat_percent) "
                + "VALUES ('export-measurement',?,62.5,72,24)", userId);
        jdbc.update("INSERT INTO health_goals (user_id,goal_type,target_weight_kg,target_date) "
                + "VALUES (?,'FAT_LOSS',55,'2027-03-01')", userId);
        jdbc.update("INSERT INTO dietary_preferences (user_id,diet_type,allergies,avoid_foods) "
                + "VALUES (?,'BALANCED','花生','香菜')", userId);
        jdbc.update("INSERT INTO health_risk_answers (id,user_id,risk_blocked) VALUES ('export-risk',?,FALSE)", userId);
        plans.create(userId, null);
        String planId = jdbc.queryForObject("SELECT id FROM health_plans WHERE user_id=?", String.class, userId);
        plans.recalculate(userId, planId, new PlanDtos.RecalculateRequest(1));
        jdbc.update("INSERT INTO meal_entries (id,user_id,entry_date,meal_type,food_name_snapshot,grams,"
                        + "calories_snapshot,protein_snapshot,carbs_snapshot,fat_snapshot,idempotency_key) "
                        + "VALUES ('export-meal',?,CURRENT_DATE,'BREAKFAST','燕麦粥',180,210,8,36,4,'export-meal')", userId);
        jdbc.update("INSERT INTO hydration_entries (id,user_id,amount_ml,occurred_at,timezone,source,idempotency_key) "
                        + "VALUES ('export-water',?,350,CURRENT_TIMESTAMP,'Asia/Shanghai','CUSTOM','export-water')", userId);
        String code = sendCode("DATA_EXPORT");
        String response = mockMvc.perform(post("/api/v1/data-exports").header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"code\":\"%s\",\"password\":\"%s\"}".formatted(code, PASSWORD)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("READY"))
                .andExpect(jsonPath("$.expiresAt").isNotEmpty())
                .andReturn().getResponse().getContentAsString();
        String id = JsonPath.read(response, "$.id");
        byte[] bytes = Files.readAllBytes(exports.download(userIdForToken(token), id));
        assertThat(new String(bytes, java.nio.charset.StandardCharsets.ISO_8859_1)).doesNotContain(PHONE);
        assertThatThrownBy(() -> Loader.loadPDF(bytes)).isInstanceOf(InvalidPasswordException.class);
        try (PDDocument document = Loader.loadPDF(bytes, PASSWORD)) {
            assertThat(document.isEncrypted()).isTrue();
            assertThat(document.getNumberOfPages()).isPositive();
            String text = new PDFTextStripper().getText(document);
            assertThat(text).contains("小轻", "身高：165", "计划版本 1（当前版本，计划状态：进行中", "燕麦粥", "180 克", "350 毫升")
                    .doesNotContain(PHONE, "计划版本 2", "export-meal", "export-water", "user_id", "password",
                            "token", "验证码");
        }
        mockMvc.perform(get("/api/v1/data-exports/" + id + "/download")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }

    @Test
    void expiredDownloadPhysicallyDeletesFileAndTracksExpiredStatus() throws Exception {
        String token = register();
        String response = mockMvc.perform(post("/api/v1/data-exports").header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"code\":\"%s\",\"password\":\"%s\"}".formatted(sendCode("DATA_EXPORT"), PASSWORD)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String id = JsonPath.read(response, "$.id");
        String userId = userIdForToken(token);
        Path file = exports.download(userId, id);
        jdbc.update("UPDATE data_export_jobs SET expires_at=? WHERE id=?", Timestamp.from(Instant.now().minusSeconds(1)), id);

        assertThatThrownBy(() -> exports.download(userId, id))
                .isInstanceOf(ApiException.class).extracting("code").isEqualTo("DATA_EXPORT_EXPIRED");
        assertThat(file).doesNotExist();
        assertThat(jdbc.queryForObject("SELECT status FROM data_export_jobs WHERE id=?", String.class, id))
                .isEqualTo("EXPIRED");
    }

    private String register() throws Exception {
        String code = sendCode("LOGIN");
        String body = mockMvc.perform(post("/api/v1/auth/sms/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"code\":\"%s\",\"deviceName\":\"导出测试手机\",\"password\":\"Healthy123\",\"acceptedTerms\":true}"
                                .formatted(PHONE, code)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.accessToken");
    }

    private String sendCode(String purpose) throws Exception {
        String body = mockMvc.perform(post("/api/v1/auth/sms/send").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"%s\",\"purpose\":\"%s\"}".formatted(PHONE, purpose)))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.debugCode");
    }

    private String userIdForToken(String token) {
        return ((com.lightbite.healthy.auth.AuthService) context.getBean(com.lightbite.healthy.auth.AuthService.class))
                .validateAccessToken(token).userId();
    }
}
