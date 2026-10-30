package com.planblindbox.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.dto.response.CalendarDayResponse;
import com.planblindbox.dto.response.CalendarMonthResponse;
import com.planblindbox.dto.response.TimeRecordResponse;
import com.planblindbox.entity.Habit;
import com.planblindbox.entity.HabitRecord;
import com.planblindbox.entity.Task;
import com.planblindbox.entity.TaskRecord;
import com.planblindbox.entity.TimeRecord;
import com.planblindbox.enums.TaskStatus;
import com.planblindbox.mapper.AppUserMapper;
import com.planblindbox.mapper.HabitMapper;
import com.planblindbox.mapper.HabitRecordMapper;
import com.planblindbox.mapper.StatsMapper;
import com.planblindbox.mapper.TaskMapper;
import com.planblindbox.mapper.TaskRecordMapper;
import com.planblindbox.mapper.TimeRecordMapper;
import com.planblindbox.util.BusinessTime;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** 复用任务、习惯、时间块及其记录，为统计页提供月历和日期详情。 */
@Service
@RequiredArgsConstructor
public class CalendarService {
    private final AppUserMapper appUserMapper;
    private final StatsMapper statsMapper;
    private final TaskMapper taskMapper;
    private final TaskRecordMapper taskRecordMapper;
    private final HabitMapper habitMapper;
    private final HabitRecordMapper habitRecordMapper;
    private final TimeRecordMapper timeRecordMapper;
    private final ObjectMapper objectMapper;

    @Transactional(readOnly = true)
    public CalendarMonthResponse getMonth(Long userId, YearMonth month) {
        validateUser(userId);

        if (month == null) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "month 不能为空"
            );
        }

        LocalDate start = month.atDay(1);
        LocalDate end = month.atEndOfMonth();

        // 1. 获取每天已经完成的任务数
        Map<LocalDate, Long> taskCounts = countsByDate(
                statsMapper.completedTasks(userId, start, end)
        );

        // 2. 获取每天已经打卡的习惯数
        Map<LocalDate, Long> habitCounts = countsByDate(
                statsMapper.completedHabits(userId, start, end)
        );

        // 3. 获取时间记录统计（仅展示，不参与完成度）
        Map<LocalDate, TimeRecordMapper.DailySummary> timeByDate =
                new HashMap<>();

        for (TimeRecordMapper.DailySummary summary :
                timeRecordMapper.selectDailySummaries(userId, start, end)) {

            if (summary.getDay() != null) {
                timeByDate.put(summary.getDay(), summary);
            }
        }

        // 4. 获取用户全部任务和习惯
        List<Task> tasks =
                taskMapper.selectAllByUserIdForCalendar(userId);

        List<Habit> habits =
                habitMapper.selectAllByUserIdForCalendar(userId);

        // 5. 批量获取日期范围内的执行记录，避免逐日查询
        Map<LocalDate, java.util.Set<Long>> taskRecordsByDate =
                taskRecordIdsByDate(
                        taskRecordMapper.selectByUserIdAndDateRange(
                                userId, start, end
                        )
                );

        Map<LocalDate, java.util.Set<Long>> habitRecordsByDate =
                habitRecordIdsByDate(
                        habitRecordMapper.selectByUserIdAndDateRange(
                                userId, start, end
                        )
                );

        List<CalendarMonthResponse.DaySummary> days =
                new ArrayList<>(month.lengthOfMonth());

        // 6. 逐日计算完成度
        for (LocalDate date = start;
             !date.isAfter(end);
             date = date.plusDays(1)) {

            java.util.Set<Long> taskIds =
                    taskRecordsByDate.getOrDefault(
                            date, java.util.Collections.emptySet()
                    );

            java.util.Set<Long> habitIds =
                    habitRecordsByDate.getOrDefault(
                            date, java.util.Collections.emptySet()
                    );

            // 已有执行记录的任务，无论当前是否归档，都纳入当天统计。
            long totalTasks = taskIds.size();

            LocalDateTime dayStart = date.atTime(5, 0);
            LocalDateTime dayEnd = date.plusDays(1).atTime(5, 0);

            // 没有执行记录，但当天确实安排执行的活动任务。
            for (Task task : tasks) {
                if (task.getTaskId() != null
                        && !taskIds.contains(task.getTaskId())
                        && isScheduledForBusinessDay(
                        task, dayStart, dayEnd)) {
                    totalTasks++;
                }
            }

            // 已打卡的习惯计入总数，包括已经归档但保留历史记录的习惯。
            long totalHabits = habitIds.size();

            // 没有打卡记录，但当天应该执行的活动习惯。
            for (Habit habit : habits) {
                if (habit.getHabitId() != null
                        && !habitIds.contains(habit.getHabitId())
                        && isScheduled(habit, date)) {
                    totalHabits++;
                }
            }

            // 已完成数量
            long completedTasks =
                    taskCounts.getOrDefault(date, 0L);

            long habitCheckIns =
                    habitCounts.getOrDefault(date, 0L);

            // 完成度：任务 + 习惯
            long totalCount = totalTasks + totalHabits;
            long completedCount = completedTasks + habitCheckIns;

            double completionRate = totalCount == 0
                    ? 0.0
                    : (double) completedCount / totalCount;

            // 时间记录单独统计
            TimeRecordMapper.DailySummary time =
                    timeByDate.get(date);

            long timeRecordCount =
                    time == null || time.getRecordCount() == null
                            ? 0L : time.getRecordCount();

            long timeMinutes =
                    time == null || time.getTotalMinutes() == null
                            ? 0L : time.getTotalMinutes();

            days.add(new CalendarMonthResponse.DaySummary(
                    date,
                    completedTasks,
                    habitCheckIns,
                    totalTasks,
                    totalHabits,
                    completionRate,
                    timeRecordCount,
                    timeMinutes
            ));
        }

        return new CalendarMonthResponse(
                month.toString(),
                days
        );
    }



    private static Map<LocalDate, java.util.Set<Long>>
    taskRecordIdsByDate(List<TaskRecord> records) {

        Map<LocalDate, java.util.Set<Long>> result =
                new HashMap<>();

        for (TaskRecord record : records) {
            if (record.getRecordDate() == null
                    || record.getTaskId() == null) {
                continue;
            }

            result.computeIfAbsent(
                    record.getRecordDate(),
                    key -> new java.util.HashSet<>()
            ).add(record.getTaskId());
        }

        return result;
    }


    private static Map<LocalDate, java.util.Set<Long>>
    habitRecordIdsByDate(List<HabitRecord> records) {

        Map<LocalDate, java.util.Set<Long>> result =
                new HashMap<>();

        for (HabitRecord record : records) {
            if (record.getRecordDate() == null
                    || record.getHabitId() == null) {
                continue;
            }

            result.computeIfAbsent(
                    record.getRecordDate(),
                    key -> new java.util.HashSet<>()
            ).add(record.getHabitId());
        }

        return result;
    }

    @Transactional(readOnly = true)
    public CalendarDayResponse getDay(Long userId, LocalDate date) {
        validateUser(userId);
        if (date == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "date 不能为空");
        }

        Map<Long, TaskRecord> taskRecords = new HashMap<>();
        for (TaskRecord record : taskRecordMapper.selectByUserIdAndDate(userId, date)) {
            taskRecords.put(record.getTaskId(), record);
        }

        LocalDateTime dayStart = date.atTime(5, 0);
        LocalDateTime dayEnd = date.plusDays(1).atTime(5, 0);
        List<CalendarDayResponse.TaskItem> tasks = new ArrayList<>();
        for (Task task : taskMapper.selectAllByUserIdForCalendar(userId)) {
            TaskRecord record = taskRecords.get(task.getTaskId());

            // 有当天执行记录的任务保留用于历史回顾。
            // 没有当天记录时，只展示当天开始或当天到期的活动任务；
            // 任务有效期覆盖当天，并不代表它每天都被安排执行。
            if (record == null && !isScheduledForBusinessDay(task, dayStart, dayEnd)) {
                continue;
            }

            String status = record != null && record.getStatus() != null
                    ? record.getStatus().name()
                    : task.getStatus() == null ? "PENDING" : task.getStatus().name();

            LocalDateTime deadline = BusinessTime.effectiveDeadline(
                    task.getEndTime(), task.getStartTime(), task.getCreateTime());
            boolean terminal = task.getStatus() == TaskStatus.COMPLETED
                    || task.getStatus() == TaskStatus.CANCELLED
                    || task.getStatus() == TaskStatus.ARCHIVED;
            boolean overdue = !terminal
                    && deadline != null
                    && !deadline.isAfter(LocalDateTime.now());

            tasks.add(new CalendarDayResponse.TaskItem(
                    task.getTaskId(),
                    task.getTitle(),
                    status,
                    overdue,
                    record == null || record.getActualCount() == null ? 0 : record.getActualCount(),
                    task.getTargetCount() == null ? 1 : task.getTargetCount(),
                    record == null ? null : record.getFinishTime()));
        }

        Map<Long, HabitRecord> habitRecords = new HashMap<>();
        for (HabitRecord record : habitRecordMapper.selectByUserIdAndDate(userId, date)) {
            habitRecords.put(record.getHabitId(), record);
        }
        List<CalendarDayResponse.HabitItem> habits = new ArrayList<>();
        for (Habit habit : habitMapper.selectAllByUserIdForCalendar(userId)) {
            HabitRecord record = habitRecords.get(habit.getHabitId());
            boolean archived = habit.getStatus() != null && "ARCHIVED".equals(habit.getStatus().name());
            if (record == null && (archived || !isScheduled(habit, date))) {
                continue;
            }
            habits.add(new CalendarDayResponse.HabitItem(
                    habit.getHabitId(),
                    habit.getName(),
                    record != null && record.getStatus() != null
                            && "COMPLETED".equals(record.getStatus().name()),
                    record == null || record.getActualCount() == null ? 0 : record.getActualCount()));
        }

        tasks.sort(Comparator.comparing(CalendarDayResponse.TaskItem::status)
                .thenComparing(CalendarDayResponse.TaskItem::title,
                        Comparator.nullsLast(String.CASE_INSENSITIVE_ORDER)));
        habits.sort(Comparator.comparing(CalendarDayResponse.HabitItem::name,
                Comparator.nullsLast(String.CASE_INSENSITIVE_ORDER)));
        List<TimeRecordResponse> timeRecords = timeRecordMapper.selectByUserIdAndDate(userId, date)
                .stream().map(record -> new TimeRecordResponse(
                        record.getTimeRecordId(), record.getTaskId(), record.getTitle(), record.getCategory(),
                        record.getStartTime(), record.getEndTime(), record.getDurationMinutes(),
                        record.getRecordDate(), record.getNote()))
                .toList();
        return new CalendarDayResponse(date, tasks, habits, timeRecords);
    }

    private void validateUser(Long userId) {
        if (userId == null || userId <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "userId 必须为正整数");
        }
        if (appUserMapper.selectById(userId) == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "用户不存在");
        }
    }

    private static Map<LocalDate, Long> countsByDate(List<StatsMapper.DailyCount> rows) {
        Map<LocalDate, Long> result = new HashMap<>();
        for (StatsMapper.DailyCount row : rows) {
            if (row.getDay() != null) {
                result.put(row.getDay(), row.getCompletedCount() == null ? 0L : row.getCompletedCount());
            }
        }
        return result;
    }

    private static boolean isScheduledForBusinessDay(Task task,
                                                     LocalDateTime dayStart,
                                                     LocalDateTime dayEnd) {
        // 已完成、已取消、已归档任务只有当天存在执行记录时才展示。
        if (task.getStatus() != null
                && task.getStatus() != TaskStatus.PENDING
                && task.getStatus() != TaskStatus.IN_PROGRESS) {
            return false;
        }

        LocalDateTime start = task.getStartTime() != null
                ? task.getStartTime() : task.getCreateTime();
        LocalDateTime deadline = BusinessTime.effectiveDeadline(
                task.getEndTime(), task.getStartTime(), task.getCreateTime());

        // 业务日采用 [当天 05:00, 次日 05:00)。
        boolean startsOnBusinessDay = start != null
                && !start.isBefore(dayStart)
                && start.isBefore(dayEnd);

        // 截止时间恰好在次日 05:00，归属于当前业务日。
        boolean dueOnBusinessDay = deadline != null
                && deadline.isAfter(dayStart)
                && !deadline.isAfter(dayEnd);

        return startsOnBusinessDay || dueOnBusinessDay;
    }

    private boolean isScheduled(Habit habit, LocalDate date) {
        if (habit.getStartDate() == null || date.isBefore(habit.getStartDate())
                || (habit.getEndDate() != null && date.isAfter(habit.getEndDate()))) {
            return false;
        }
        if (habit.getStatus() == null || !"ACTIVE".equals(habit.getStatus().name())) {
            return false;
        }
        try {
            JsonNode rule = objectMapper.readTree(habit.getRepeatRule());
            String type = rule.path("type").asText();
            if ("DAILY".equals(type)) return true;
            if ("WEEKLY".equals(type)) {
                DayOfWeek weekday = date.getDayOfWeek();
                for (JsonNode candidate : rule.path("daysOfWeek")) {
                    if (candidate.asInt() == weekday.getValue()) return true;
                }
                return false;
            }
            return false;
        } catch (JsonProcessingException | IllegalArgumentException exception) {
            throw new IllegalStateException("habit.repeat_rule 不是有效的习惯周期 JSON", exception);
        }
    }
}
