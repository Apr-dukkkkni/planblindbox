
package com.planblindbox.service.rule;

import java.math.BigDecimal;

/**
 * 任务优先级计算规则。
 * 只负责计算分数，不处理数据库和任务业务流程。
 */
public final class TaskPriorityCalculator {

    private TaskPriorityCalculator() {
    }

    /**
     * 优先级 = 重要程度 × 困难程度。
     * 未设置时默认等级为 3，与现有奖励计算规则保持一致。
     */
    public static BigDecimal calculate(
            Integer importance,
            Integer difficulty
    ) {
        int importanceLevel = normalize(importance, "重要程度");
        int difficultyLevel = normalize(difficulty, "困难程度");

        return BigDecimal.valueOf(importanceLevel)
                .multiply(BigDecimal.valueOf(difficultyLevel));
    }

    private static int normalize(Integer level, String field) {
        int value = level == null ? 3 : level;

        if (value < 1 || value > 5) {
            throw new IllegalArgumentException(
                    field + "必须在 1～5 之间"
            );
        }

        return value;
    }
}
