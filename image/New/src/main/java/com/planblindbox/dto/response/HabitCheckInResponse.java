package com.planblindbox.dto.response;

import lombok.Data;

import java.time.LocalDate;

@Data
public class HabitCheckInResponse {
    private Long habitId;
    /** 服务端当前日期；暂时使用服务端默认时区。 */
    private LocalDate recordDate;
    private Boolean checkedInToday;
    /** 按约定执行日连续打卡的次数，不是简单连续自然日。 */
    private Integer currentStreak;
    private Integer totalCheckInDays;
    /** 仅 POST 当次打卡成功才有奖励信息；GET 状态接口为 null。 */
    private HabitRewardResponse reward;
}
