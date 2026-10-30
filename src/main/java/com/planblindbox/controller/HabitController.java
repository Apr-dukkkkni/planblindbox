package com.planblindbox.controller;

import com.planblindbox.common.Result;
import com.planblindbox.dto.request.HabitCreateRequest;
import com.planblindbox.dto.request.HabitUpdateRequest;
import com.planblindbox.dto.response.HabitResponse;
import com.planblindbox.dto.response.HabitCheckInResponse;
import com.planblindbox.service.HabitService;
import com.planblindbox.service.HabitCheckInService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/habits")
@RequiredArgsConstructor
public class HabitController {
    private final HabitService habitService;
    private final HabitCheckInService habitCheckInService;

    @PostMapping
    public Result<HabitResponse> create(@Valid @RequestBody HabitCreateRequest request) {
        return Result.success(habitService.create(request));
    }

    @GetMapping("/{habitId}")
    public Result<HabitResponse> getById(@PathVariable Long habitId, @RequestParam Long userId) {
        return Result.success(habitService.getById(userId, habitId));
    }

    @GetMapping
    public Result<List<HabitResponse>> list(@RequestParam Long userId) {
        return Result.success(habitService.list(userId));
    }

    @PutMapping("/{habitId}")
    public Result<HabitResponse> update(@PathVariable Long habitId,
                                        @RequestParam Long userId,
                                        @Valid @RequestBody HabitUpdateRequest request) {
        return Result.success(habitService.update(userId, habitId, request));
    }


    @GetMapping("/archived")
    public Result<List<HabitResponse>> getArchived(
            @RequestParam Long userId
    ) {
        return Result.success(
                habitService.getArchived(userId)
        );
    }

    @PutMapping("/{habitId}/restore")
    public Result<HabitResponse> restore(
            @PathVariable Long habitId,
            @RequestParam Long userId
    ) {
        return Result.success(
                habitService.restore(userId, habitId)
        );
    }

    @DeleteMapping("/{habitId}")
    public Result<Void> archive(@PathVariable Long habitId, @RequestParam Long userId) {
        habitService.archive(userId, habitId);
        return Result.success();
    }
    /** 同一个用户/习惯/日期只允许一次打卡。 */
    @PostMapping("/{habitId}/check-in")
    public Result<HabitCheckInResponse> checkIn(@PathVariable Long habitId, @RequestParam Long userId) {
        return Result.success(habitCheckInService.checkIn(userId, habitId));
    }

    @GetMapping("/{habitId}/check-in-status")
    public Result<HabitCheckInResponse> checkInStatus(@PathVariable Long habitId, @RequestParam Long userId) {
        return Result.success(habitCheckInService.getTodayStatus(userId, habitId));
    }
}
