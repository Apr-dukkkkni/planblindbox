package com.planblindbox.enums;

/**
 * 任务计划类型。
 *
 * ONCE：一次性任务，沿用原有的累计完成与一次性奖励逻辑。
 * REPEAT：按间隔天数或指定星期重复执行。
 * ACCUMULATE：在自定义长度的周期内累计完成指定次数。
 */
public enum TaskRecurrenceType {
    ONCE,
    REPEAT,
    ACCUMULATE
}
