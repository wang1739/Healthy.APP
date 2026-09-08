package com.lightbite.healthy.nutrition;

import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/foods")
public class FoodController {

    private final FoodService service;

    public FoodController(FoodService service) {
        this.service = service;
    }

    @GetMapping
    List<NutritionDtos.FoodResponse> search(
            Authentication authentication,
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "ALL") String scope,
            @RequestParam(defaultValue = "20") int limit
    ) {
        return service.search(authentication.getName(), query, scope, limit);
    }

    @GetMapping("/suggestions")
    NutritionDtos.FoodSuggestionsResponse suggestions(
            Authentication authentication,
            @RequestParam(defaultValue = "8") int limit
    ) {
        return service.suggestions(authentication.getName(), limit);
    }

    @PostMapping("/custom")
    @ResponseStatus(HttpStatus.CREATED)
    NutritionDtos.FoodResponse create(
            Authentication authentication,
            @RequestBody NutritionDtos.CustomFoodRequest request
    ) {
        return service.createCustom(authentication.getName(), request);
    }
}
