package com.planblindbox.service;

import com.planblindbox.dto.response.StatsResponse;
import com.planblindbox.entity.UserAsset;
import com.planblindbox.mapper.AppUserMapper;
import com.planblindbox.mapper.StatsMapper;
import com.planblindbox.mapper.UserAssetMapper;
import com.planblindbox.util.BusinessTime;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
public class StatsService {
    private final StatsMapper statsMapper;
    private final AppUserMapper appUserMapper;
    private final UserAssetMapper userAssetMapper;

    @Transactional(readOnly = true)
    public StatsResponse getStats(Long userId, int days) {
        return getStatsAt(userId, days, LocalDateTime.now());
    }

    /** 包级可见，测试能固定时间以验证 05:00 边界，无需等待到凌晨。 */
    StatsResponse getStatsAt(Long userId, int days, LocalDateTime now) {
        if (userId == null || userId <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "userId 必须为正整数");
        }
        if (days != 7 && days != 30) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "days 仅支持 7 或 30");
        }
        if (appUserMapper.selectById(userId) == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "用户不存在");
        }

        LocalDate endDate = BusinessTime.businessDate(now);
        LocalDate startDate = endDate.minusDays(days - 1L);
        LocalDateTime startAt = startDate.atTime(5, 0);
        LocalDateTime endExclusive = endDate.plusDays(1).atTime(5, 0);

        Map<LocalDate, Long> tasksByDay = new HashMap<>();
        for (StatsMapper.DailyCount row : statsMapper.completedTasks(userId, startDate, endDate)) {
            tasksByDay.put(row.getDay(), value(row.getCompletedCount()));
        }
        Map<LocalDate, Long> habitsByDay = new HashMap<>();
        for (StatsMapper.DailyCount row : statsMapper.completedHabits(userId, startDate, endDate)) {
            habitsByDay.put(row.getDay(), value(row.getCompletedCount()));
        }
        Map<LocalDate, StatsMapper.DailyAssets> assetsByDay = new HashMap<>();
        for (StatsMapper.DailyAssets row : statsMapper.dailyAssets(userId, startAt, endExclusive)) {
            assetsByDay.put(row.getDay(), row);
        }

        UserAsset balance = userAssetMapper.selectByUserId(userId);
        long coinBalance = balance == null ? 0 : value(balance.getCoin());
        long expBalance = balance == null ? 0 : value(balance.getExp());
        long waterBalance = balance == null ? 0 : value(balance.getWater());

        // 用当前余额向前回推每天期末余额，而不是错误地把期间收入等同于全部历史资产。
        // 要求所有资产增减都写入 asset_record；商店 V1 已使用正负流水。
        List<StatsResponse.DailyPoint> reversed = new ArrayList<>(days);
        long completedTasks = 0, habitCheckIns = 0, coinEarned = 0, coinSpent = 0, expEarned = 0;
        long runningCoin = coinBalance;
        long runningExp = expBalance;
        for (int i = days - 1; i >= 0; i--) {
            LocalDate date = startDate.plusDays(i);
            long taskCount = tasksByDay.getOrDefault(date, 0L);
            long habitCount = habitsByDay.getOrDefault(date, 0L);
            StatsMapper.DailyAssets a = assetsByDay.get(date);
            long earnedCoin = a == null ? 0 : value(a.getCoinEarned());
            long spentCoin = a == null ? 0 : value(a.getCoinSpent());
            long earnedExp = a == null ? 0 : value(a.getExpEarned());
            long netCoin = a == null ? 0 : value(a.getCoinNet());
            long netExp = a == null ? 0 : value(a.getExpNet());

            completedTasks += taskCount;
            habitCheckIns += habitCount;
            coinEarned += earnedCoin;
            coinSpent += spentCoin;
            expEarned += earnedExp;
            reversed.add(new StatsResponse.DailyPoint(date, taskCount, habitCount,
                    earnedCoin, spentCoin, earnedExp, runningCoin, runningExp));
            runningCoin -= netCoin;
            runningExp -= netExp;
        }
        java.util.Collections.reverse(reversed);
        return new StatsResponse(days, startDate, endDate,
                new StatsResponse.Summary(completedTasks, habitCheckIns, coinEarned,
                        coinSpent, expEarned, coinBalance, expBalance, waterBalance),
                reversed);
    }

    private static long value(Number n) {
        return n == null ? 0 : n.longValue();
    }
}
