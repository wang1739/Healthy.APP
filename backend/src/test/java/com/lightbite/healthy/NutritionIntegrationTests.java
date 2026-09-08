package com.lightbite.healthy;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.LocalDate;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.http.HttpHeaders;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

@SpringBootTest
@ActiveProfiles("test")
class NutritionIntegrationTests {

    @Autowired WebApplicationContext applicationContext;
    @Autowired JdbcTemplate jdbc;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext).apply(springSecurity()).build();
        jdbc.update("DELETE FROM meal_entries");
        createUser("nutrition-api-a", "13000000211");
        createUser("nutrition-api-b", "13000000212");
    }

    @Test
    void requiresAuthenticationAndIdempotencyKey() throws Exception {
        mockMvc.perform(get("/api/v1/nutrition/days/" + LocalDate.now()))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(post("/api/v1/nutrition/entries").with(user("nutrition-api-a"))
                        .contentType(MediaType.APPLICATION_JSON).content(entryBody()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("IDEMPOTENCY_KEY_REQUIRED"));
    }

    @Test
    void corsAllowsIdempotencyKey() throws Exception {
        mockMvc.perform(options("/api/v1/nutrition/entries")
                        .header(HttpHeaders.ORIGIN, "http://localhost:4173")
                        .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "POST")
                        .header(HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS, "Idempotency-Key"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_HEADERS, "Idempotency-Key"));
    }

    @Test
    void performsCrudAndReturnsWholeDay() throws Exception {
        String response = mockMvc.perform(post("/api/v1/nutrition/entries").with(user("nutrition-api-a"))
                        .header("Idempotency-Key", "api-create-1")
                        .contentType(MediaType.APPLICATION_JSON).content(entryBody()))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.status").value("READY"))
                .andExpect(jsonPath("$.total.calories").value(116))
                .andReturn().getResponse().getContentAsString();
        String id = com.jayway.jsonpath.JsonPath.read(response, "$.meals[1].entries[0].id");

        mockMvc.perform(put("/api/v1/nutrition/entries/{id}", id).with(user("nutrition-api-a"))
                        .contentType(MediaType.APPLICATION_JSON).content(entryBody().replace("sys-rice", "sys-egg")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.meals[1].entries[0].foodName").value("鸡蛋"));

        mockMvc.perform(delete("/api/v1/nutrition/entries/{id}", id).with(user("nutrition-api-b")))
                .andExpect(status().isNotFound());
        mockMvc.perform(delete("/api/v1/nutrition/entries/{id}", id).with(user("nutrition-api-a")))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("EMPTY"));
    }

    @Test
    void rejectsFutureDateAndUntrustedCustomNutrition() throws Exception {
        String future = entryBody().replace(LocalDate.now().toString(), LocalDate.now().plusDays(1).toString());
        mockMvc.perform(post("/api/v1/nutrition/entries").with(user("nutrition-api-a"))
                        .header("Idempotency-Key", "future-api")
                        .contentType(MediaType.APPLICATION_JSON).content(future))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("未来日期不能记录饮食"));

        mockMvc.perform(post("/api/v1/nutrition/entries").with(user("nutrition-api-a"))
                        .header("Idempotency-Key", "bad-custom")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"date\":\"" + LocalDate.now() + "\",\"mealType\":\"SNACK\","
                                + "\"foodName\":\"坏数据\",\"grams\":10,\"baseGrams\":100,\"calories\":-1,"
                                + "\"protein\":0,\"carbs\":0,\"fat\":0}"))
                .andExpect(status().isBadRequest());
    }

    private String entryBody() {
        return "{\"date\":\"" + LocalDate.now()
                + "\",\"mealType\":\"LUNCH\",\"foodId\":\"sys-rice\",\"grams\":100}";
    }

    private void createUser(String id, String phone) {
        jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES (?,?,'ACTIVE')", id, phone);
        jdbc.update("DELETE FROM health_profiles WHERE user_id=?", id);
        jdbc.update("INSERT INTO health_profiles (user_id,current_step,completed,risk_blocked) VALUES (?,7,TRUE,FALSE)", id);
    }
}
