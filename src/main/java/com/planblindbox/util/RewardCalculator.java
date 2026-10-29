package com.planblindbox.util;

public final class RewardCalculator {

    private RewardCalculator() {
    }

    public record TaskRewardAmounts(int coin, long exp) {
    }

    /**
     * 根据重要程度和困难程度计算任务完成奖励。
     * 空值按 3 级处理。
     */
    public static TaskRewardAmounts calculateTaskCompletion(
            Integer importance, Integer difficulty) {

        int importanceLevel = validateLevel(importance, "重要程度");
        int difficultyLevel = validateLevel(difficulty, "困难程度");

        int coin = coinForLevel(importanceLevel)
                + coinForLevel(difficultyLevel);

        long exp = expForLevel(importanceLevel)
                + expForLevel(difficultyLevel);

        return new TaskRewardAmounts(coin, exp);
    }

    private static int validateLevel(Integer level, String field) {
        int value = level == null ? 3 : level;

        if (value < 1 || value > 5) {
            throw new IllegalStateException(
                    field + "必须在 1～5 之间");
        }

        return value;
    }

    private static int coinForLevel(int level) {
        return switch (level) {
            case 1 -> 1;
            case 2 -> 2;
            case 3 -> 4;
            case 4 -> 8;
            case 5 -> 16;
            default -> throw new IllegalArgumentException(
                    "等级必须为 1～5");
        };
    }

    private static long expForLevel(int level) {
        return switch (level) {
            case 1 -> 10;
            case 2 -> 20;
            case 3 -> 40;
            case 4 -> 80;
            case 5 -> 160;
            default -> throw new IllegalArgumentException(
                    "等级必须为 1～5");
        };
    }
}