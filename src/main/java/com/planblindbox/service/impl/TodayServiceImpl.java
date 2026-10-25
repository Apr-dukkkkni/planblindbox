package com.planblindbox.service.impl;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.dto.response.HabitCheckInResponse;
import com.planblindbox.dto.response.TodayResponse;
import com.planblindbox.entity.Habit;
import com.planblindbox.entity.Task;
import com.planblindbox.entity.TaskRecord;
import com.planblindbox.entity.UserAsset;
import com.planblindbox.enums.HabitStatus;
import com.planblindbox.enums.TaskRecordStatus;
import com.planblindbox.enums.TaskStatus;
import com.planblindbox.mapper.AppUserMapper;
import com.planblindbox.mapper.HabitMapper;
import com.planblindbox.mapper.TaskMapper;
import com.planblindbox.mapper.TaskRecordMapper;
import com.planblindbox.mapper.UserAssetMapper;
import com.planblindbox.service.HabitCheckInService;
import com.planblindbox.service.TodayService;
import com.planblindbox.util.BusinessTime;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Locale;
import java.util.List;

/** 只读聚合：不执行任务、不打卡、不结算奖励。 */
@Service
@RequiredArgsConstructor
public class TodayServiceImpl implements TodayService {
    private final AppUserMapper appUserMapper;
    private final TaskMapper taskMapper;
    private final TaskRecordMapper taskRecordMapper;
    private final HabitMapper habitMapper;
    private final HabitCheckInService habitCheckInService;
    private final UserAssetMapper userAssetMapper;
    private final ObjectMapper objectMapper;

    @Override
    @Transactional(readOnly = true)
    public TodayResponse getToday(Long userId) {
        return getToday(userId, "time");
    }

    @Override
    @Transactional(readOnly = true)
    public TodayResponse getToday(Long userId, String sort) {
        String sortMode = validateSort(sort);
        if (userId == null || userId <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "userId 必须为正整数");
        }
        if (appUserMapper.selectById(userId) == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "用户不存在");
        }

        // 与现有 Task Complete / Habit Check-in 一样，使用服务器默认时区的今天。
        LocalDateTime now = LocalDateTime.now();
        LocalDate today = BusinessTime.businessDate(now);
        List<TodayResponse.TaskItem> tasks = loadTasks(userId, today, now);
        sortTasks(tasks, sortMode);
        List<TodayResponse.HabitItem> habits = loadHabits(userId, today);

        TodayResponse response = new TodayResponse();
        response.setDate(today);
        response.setTasks(tasks);
        response.setHabits(habits);
        response.setAssets(loadAssets(userId));
        response.setSummary(buildSummary(tasks, habits));
        return response;
    }

    private List<TodayResponse.TaskItem> loadTasks(Long userId, LocalDate today, LocalDateTime now) {
        List<TodayResponse.TaskItem> result = new ArrayList<>();
        for (Task task : taskMapper.selectByUserId(userId)) {
            if (task.getStatus() == TaskStatus.CANCELLED || task.getStatus() == TaskStatus.ARCHIVED) {
                continue;
            }
            // 今天以后才开始的任务，不属于今日待办。
            // 判断任务是否真正到了开始时间
            if (task.getStartTime() != null
                    && task.getStartTime().isAfter(now)) {
                continue;
            }


            LocalDateTime deadline = BusinessTime.effectiveDeadline(
                    task.getEndTime(),
                    task.getStartTime(),
                    task.getCreateTime()
            );

            LocalDateTime businessDayStart =
                    today.atTime(5, 0);

// 到达新业务日后，移除上一周期已过期的任务
            if (deadline != null &&
                    !deadline.isAfter(businessDayStart)) {
                continue;
            }

            // 整体已完成的任务：只有当日存在完成记录，才继续在今日首页展示。
            TaskRecord todayRecord = taskRecordMapper.selectByTaskIdAndDate(task.getTaskId(), today);
            boolean completedToday = task.getStatus() == TaskStatus.COMPLETED
                    && todayRecord != null
                    && todayRecord.getStatus() == TaskRecordStatus.COMPLETED;
            if (task.getStatus() == TaskStatus.COMPLETED && !completedToday) {
                continue;
            }
            if (task.getStatus() != TaskStatus.PENDING
                    && task.getStatus() != TaskStatus.IN_PROGRESS
                    && task.getStatus() != TaskStatus.COMPLETED) {
                continue;
            }

            long total = taskRecordMapper.sumActualCount(task.getTaskId());
            int todayCount = todayRecord == null || todayRecord.getActualCount() == null
                    ? 0 : todayRecord.getActualCount();
            TodayResponse.TaskItem item = new TodayResponse.TaskItem();
            item.setTaskId(task.getTaskId());
            item.setTitle(task.getTitle());
            item.setNote(task.getNote());
            item.setStartTime(task.getStartTime());
            item.setEndTime(task.getEndTime());
            item.setPriorityScore(task.getPriorityScore());
            item.setImportance(task.getImportance());
            item.setDifficulty(task.getDifficulty());
            item.setStatus(task.getStatus());
            item.setTargetCount(task.getTargetCount());
            item.setTodayActualCount(todayCount);
            String recordRule = task.getRecordRule();

            if (recordRule == null) {
                item.setRecordRule(null);
            } else {
                try {
                    item.setRecordRule(
                            objectMapper.readTree(recordRule)
                    );
                } catch (JsonProcessingException e) {
                    throw new IllegalStateException(
                            "数据库 record_rule 不是合法 JSON", e
                    );
                }
            }
            item.setTotalActualCount(total);
            item.setRemainingCount(Math.max(0, (long) task.getTargetCount() - total));
            item.setCompletedToday(completedToday);
            item.setOverdue(
                    !completedToday
                            && deadline != null
                            && !now.isBefore(deadline)
            );
            result.add(item);
        }
        return result;
    }

    /**
     * 按时间：截止时间升序（未设置截止时间最后），同时间按重要程度降序。
     * 按重要程度：重要程度降序，同级按截止时间升序。
     * 两种模式均将今天已完成的任务排到最后，再用 taskId 保证稳定顺序。
     * importance 为 null 时仅排序按 3 处理，不回写数据库，也不改响应值。
     */
    private void sortTasks(List<TodayResponse.TaskItem> items, String sortMode) {
        Comparator<TodayResponse.TaskItem> byEndTime = Comparator.comparing(
                TodayResponse.TaskItem::getEndTime,
                Comparator.nullsLast(Comparator.naturalOrder()));
        Comparator<TodayResponse.TaskItem> byImportance = Comparator.comparingInt(
                (TodayResponse.TaskItem t) -> t.getImportance() == null ? 3 : t.getImportance()).reversed();
        Comparator<TodayResponse.TaskItem> main = "importance".equals(sortMode)
                ? byImportance.thenComparing(byEndTime)
                : byEndTime.thenComparing(byImportance);
        items.sort(Comparator.comparing(TodayResponse.TaskItem::isCompletedToday)
                .thenComparing(main)
                .thenComparing(TodayResponse.TaskItem::getTaskId,
                        Comparator.nullsLast(Comparator.naturalOrder())));
    }

    private String validateSort(String sort) {
        if (sort == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "sort 不能为空");
        }
        String normalized = sort.toLowerCase(Locale.ROOT);
        if (!"time".equals(normalized) && !"importance".equals(normalized)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "sort 仅支持 time 或 importance");
        }
        return normalized;
    }

    private List<TodayResponse.HabitItem> loadHabits(Long userId, LocalDate today) {
        List<TodayResponse.HabitItem> result = new ArrayList<>();
        for (Habit habit : habitMapper.selectByUserId(userId)) {
            if (habit.getStatus() != HabitStatus.ACTIVE || !isScheduled(habit, today)) {
                continue;
            }
            // 复用原有只读状态查询，尤其是 WEEKLY 跨自然日的连续打卡计算。
            HabitCheckInResponse status = habitCheckInService.getTodayStatus(userId, habit.getHabitId());
            TodayResponse.HabitItem item = new TodayResponse.HabitItem();
            item.setHabitId(habit.getHabitId());
            item.setName(habit.getName());
            item.setNote(habit.getNote());
            item.setCheckedInToday(Boolean.TRUE.equals(status.getCheckedInToday()));
            item.setCurrentStreak(status.getCurrentStreak());
            item.setTotalCheckInDays(status.getTotalCheckInDays());
            result.add(item);
        }
        return result;
    }

    private boolean isScheduled(Habit habit, LocalDate today) {
        if (today.isBefore(habit.getStartDate())
                || (habit.getEndDate() != null && today.isAfter(habit.getEndDate()))) {
            return false;
        }
        final JsonNode rule;
        try {
            rule = objectMapper.readTree(habit.getRepeatRule());
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("数据库中的 repeat_rule 不是有效 JSON", e);
        }
        String type = rule.path("type").asText();
        if ("DAILY".equals(type)) return true;
        if ("WEEKLY".equals(type)) {
            int todayWeekday = today.getDayOfWeek().getValue();
            for (JsonNode day : rule.path("daysOfWeek")) {
                if (day.asInt() == todayWeekday) return true;
            }
            return false;
        }
        throw new IllegalStateException("数据库中的 repeat_rule 类型不受支持: " + type);
    }

    private TodayResponse.Asset loadAssets(Long userId) {
        UserAsset saved = userAssetMapper.selectByUserId(userId);
        TodayResponse.Asset asset = new TodayResponse.Asset();
        if (saved != null) {
            asset.setCoin(saved.getCoin());
            asset.setExp(saved.getExp());
            asset.setWater(saved.getWater());
        }
        // 从未获得奖励的用户可以没有 user_asset 行，首页返回 0 而不是 null。
        return asset;
    }

    private TodayResponse.Summary buildSummary(List<TodayResponse.TaskItem> tasks,
                                               List<TodayResponse.HabitItem> habits) {
        TodayResponse.Summary summary = new TodayResponse.Summary();
        summary.setTaskTotal(tasks.size());
        summary.setTaskCompleted((int) tasks.stream().filter(TodayResponse.TaskItem::isCompletedToday).count());
        summary.setHabitTotal(habits.size());
        summary.setHabitCheckedIn((int) habits.stream().filter(TodayResponse.HabitItem::isCheckedInToday).count());
        int total = summary.getTaskTotal() + summary.getHabitTotal();
        int completed = summary.getTaskCompleted() + summary.getHabitCheckedIn();
        summary.setCompletionRate(total == 0 ? BigDecimal.ZERO
                : BigDecimal.valueOf(completed * 100L)
                .divide(BigDecimal.valueOf(total), 2, RoundingMode.HALF_UP));
        return summary;
    }
}
