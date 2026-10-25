package com.planblindbox.controller;

import com.planblindbox.common.Result;
import com.planblindbox.dto.request.ShopOpenRequest;
import com.planblindbox.dto.response.ShopBalanceResponse;
import com.planblindbox.dto.response.ShopBoxResponse;
import com.planblindbox.dto.response.ShopOpenResponse;
import com.planblindbox.service.ShopService;
import jakarta.validation.Valid;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/shop")
@RequiredArgsConstructor
public class ShopController {

    private final ShopService shopService;

    @GetMapping("/boxes")
    public Result<List<ShopBoxResponse>> boxes() {
        return Result.success(shopService.boxes());
    }

    @GetMapping("/balance")
    public Result<ShopBalanceResponse> balance(@RequestParam Long userId) {
        return Result.success(shopService.balance(userId));
    }

    @GetMapping("/opens")
    public Result<List<ShopOpenResponse>> history(
            @RequestParam Long userId,
            @RequestParam(defaultValue = "20") int limit) {
        return Result.success(shopService.history(userId, limit));
    }

    @PostMapping("/boxes/{boxId}/open")
    public Result<ShopOpenResponse> open(@PathVariable Long boxId,
                                         @RequestParam Long userId,
                                         @Valid @RequestBody ShopOpenRequest request) {
        return Result.success(shopService.open(userId, boxId, request.requestId()));
    }
}
