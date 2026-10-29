package com.planblindbox.util;

import java.util.Map;

public final class DailySignInRewardCalculator {

    private DailySignInRewardCalculator() {
    }

    private static final int BASE_WATER = 5;

    // 连续签到天数 -> 额外奖励水滴
    private static final Map<Integer, Integer> BONUS_RULES = Map.of(
            7, 10,
            14, 15,
            21, 30
    );

    public record SignInReward(
            int baseWater,
            int bonusWater,
            int totalWater) {
    }

    public static SignInReward calculate(int streakDay) {
        if (streakDay < 1) {
            throw new IllegalArgumentException(
                    "连续签到天数必须大于 0");
        }

        int bonusWater = BONUS_RULES.getOrDefault(
                streakDay, 0);

        return new SignInReward(
                BASE_WATER,
                bonusWater,
                BASE_WATER + bonusWater
        );
    }
}