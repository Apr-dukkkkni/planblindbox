package com.planblindbox.service.impl;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.dto.response.HabitCheckInResponse;
import com.planblindbox.dto.response.HabitRewardResponse;
import com.planblindbox.entity.Habit;
import com.planblindbox.entity.HabitRecord;
import com.planblindbox.enums.HabitRecordStatus;
import com.planblindbox.enums.HabitStatus;
import com.planblindbox.mapper.HabitMapper;
import com.planblindbox.mapper.HabitRecordMapper;
import com.planblindbox.service.HabitCheckInService;
import com.planblindbox.service.RewardService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.Set;

@Service
@RequiredArgsConstructor
public class HabitCheckInServiceImpl implements HabitCheckInService {
    private final HabitMapper habitMapper;
    private final HabitRecordMapper habitRecordMapper;
    private final RewardService rewardService;
    private final ObjectMapper objectMapper;

    /** 习惯行锁串行化同一习惯的当日重复请求；与奖励入账在同一事务。 */
    @Override
    @Transactional
    public HabitCheckInResponse checkIn(Long userId, Long habitId) {
        Habit habit = habitMapper.selectByIdForUpdate(habitId, userId);
        if (habit == null) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Habit不存在");
        if (habit.getStatus() != HabitStatus.ACTIVE) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "仅 ACTIVE 习惯可打卡");
        }

        LocalDate today = LocalDate.now();
        JsonNode rule = parseRule(habit);
        if (!isScheduled(habit, today, rule)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "今天不是此习惯的执行日");
        }
        if (habitRecordMapper.selectByHabitIdAndDate(habitId, today) != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "今天已经打过卡了");
        }

        HabitRecord record = new HabitRecord();
        record.setHabitId(habitId);
        record.setRecordDate(today);
        record.setStatus(HabitRecordStatus.COMPLETED);
        record.setActualCount(1);
        record.setFinishTime(LocalDateTime.now());
        if (habitRecordMapper.insert(record) != 1) {
            throw new IllegalStateException("保存习惯打卡记录失败");
        }
        // 返回的一次性奖励流水 source_id 指向具体的 habit_record_id，而不是 habit_id。
        HabitRewardResponse reward = rewardService.rewardHabitCheckIn(userId, record.getHabitRecordId());
        HabitCheckInResponse result = buildStatus(habit, today);
        result.setReward(reward);
        return result;
    }

    @Override
    public HabitCheckInResponse getTodayStatus(Long userId, Long habitId) {
        Habit habit = habitMapper.selectById(habitId, userId);
        if (habit == null) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Habit不存在");
        return buildStatus(habit, LocalDate.now());
    }

    private HabitCheckInResponse buildStatus(Habit habit, LocalDate today) {
        Set<LocalDate> completed = new HashSet<>(habitRecordMapper.selectCompletedDates(habit.getHabitId()));
        JsonNode rule = parseRule(habit);
        HabitCheckInResponse result = new HabitCheckInResponse();
        result.setHabitId(habit.getHabitId());
        result.setRecordDate(today);
        result.setCheckedInToday(completed.contains(today));
        result.setTotalCheckInDays(completed.size());
        result.setCurrentStreak(calculateStreak(habit, completed, today, rule));
        return result;
    }

    /**
     * 当前日尚未打卡，不立即清空昨日的 streak，直到有一个更早的应打卡日漏打。
     * WEEKLY 规则自动跳过非执行日（例如周一、三、五）。
     */
    private int calculateStreak(Habit habit, Set<LocalDate> completed, LocalDate today, JsonNode rule) {
        LocalDate day = today;
        if (!completed.contains(today)) day = day.minusDays(1);
        int streak = 0;
        while (!day.isBefore(habit.getStartDate())) {
            if (isScheduled(habit, day, rule)) {
                if (!completed.contains(day)) break;
                streak++;
            }
            day = day.minusDays(1);
        }
        return streak;
    }

    private JsonNode parseRule(Habit habit) {
        try {
            return objectMapper.readTree(habit.getRepeatRule());
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("habit.repeat_rule 不是有效 JSON", e);
        }
    }

    private boolean isScheduled(Habit habit, LocalDate date, JsonNode rule) {
        if (date.isBefore(habit.getStartDate())
                || (habit.getEndDate() != null && date.isAfter(habit.getEndDate()))) return false;
        String type = rule.path("type").asText();
        if ("DAILY".equals(type)) return true;
        if ("WEEKLY".equals(type)) {
            int weekday = date.getDayOfWeek().getValue(); // 1=周一, 7=周日
            for (JsonNode candidate : rule.path("daysOfWeek")) {
                if (candidate.asInt() == weekday) return true;
            }
            return false;
        }
        throw new IllegalStateException("数据库中的 repeat_rule 类型不受支持: " + type);
    }
}
