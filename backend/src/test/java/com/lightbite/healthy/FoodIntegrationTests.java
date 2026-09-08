package com.lightbite.healthy;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

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

@SpringBootTest
@ActiveProfiles("test")
class FoodIntegrationTests {

    @Autowired WebApplicationContext applicationContext;
    @Autowired JdbcTemplate jdbc;
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.webAppContextSetup(applicationContext).apply(springSecurity()).build();
        jdbc.update("DELETE FROM meal_entries");
        jdbc.update("DELETE FROM food_portions WHERE food_id IN (SELECT id FROM foods WHERE owner_user_id IS NOT NULL)");
        jdbc.update("DELETE FROM foods WHERE owner_user_id IS NOT NULL");
        jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES ('food-api-a','13000000111','ACTIVE')");
        jdbc.update("MERGE INTO users (id,phone,status) KEY(id) VALUES ('food-api-b','13000000112','ACTIVE')");
    }

    @Test
    void requiresAuthenticationAndSearchesChineseFoods() throws Exception {
        mockMvc.perform(get("/api/v1/foods")).andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/v1/foods?query=鸡&scope=SYSTEM&limit=10").with(user("food-api-a")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[*].name").value(org.hamcrest.Matchers.hasItem("鸡蛋")))
                .andExpect(jsonPath("$[0].portions").isArray());
    }

    @Test
    void createsPrivateCustomFoodAndRejectsBadValues() throws Exception {
        String body = """
                {"name":"自制饭团","category":"CUSTOM","baseGrams":200,"calories":310,
                 "protein":8.4,"carbs":61.2,"fat":3.2}
                """;
        mockMvc.perform(post("/api/v1/foods/custom").with(user("food-api-a"))
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.name").value("自制饭团"))
                .andExpect(jsonPath("$.caloriesPer100g").value(155));

        mockMvc.perform(get("/api/v1/foods?query=饭团&scope=MINE").with(user("food-api-b")))
                .andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());

        mockMvc.perform(post("/api/v1/foods/custom").with(user("food-api-a"))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"坏数据\",\"baseGrams\":0}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void returnsRecentAndFrequentSuggestionsWithoutDuplicates() throws Exception {
        jdbc.update("INSERT INTO meal_entries (id,user_id,entry_date,meal_type,food_id,food_name_snapshot,grams,"
                + "calories_snapshot,protein_snapshot,carbs_snapshot,fat_snapshot,idempotency_key,created_at) "
                + "VALUES ('m1','food-api-a','2026-09-07','LUNCH','sys-rice','米饭',100,116,2.6,25.9,.3,'s1','2026-09-07 12:00:00')");
        jdbc.update("INSERT INTO meal_entries (id,user_id,entry_date,meal_type,food_id,food_name_snapshot,grams,"
                + "calories_snapshot,protein_snapshot,carbs_snapshot,fat_snapshot,idempotency_key,created_at) "
                + "VALUES ('m2','food-api-a','2026-09-08','LUNCH','sys-rice','米饭',150,174,3.9,38.85,.45,'s2','2026-09-08 12:00:00')");

        mockMvc.perform(get("/api/v1/foods/suggestions?limit=8").with(user("food-api-a")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.recent.length()").value(1))
                .andExpect(jsonPath("$.recent[0].name").value("米饭"))
                .andExpect(jsonPath("$.frequent[0].name").value("米饭"));
    }
}
