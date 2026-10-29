package com.planblindbox.service.impl;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.dto.request.TaskCompleteRequest;
import com.planblindbox.dto.response.TaskCompleteResponse;
import com.planblindbox.dto.response.TaskRewardResponse;
import com.planblindbox.dto.request.TaskCreateRequest;
import com.planblindbox.dto.request.TaskUpdateRequest;
import com.planblindbox.dto.response.TaskResponse;
import com.planblindbox.entity.Task;
import com.planblindbox.entity.TaskRecord;
import com.planblindbox.enums.TaskRecordStatus;
import com.planblindbox.enums.TaskStatus;
import com.planblindbox.mapper.TaskMapper;
import com.planblindbox.mapper.TaskCategoryMapper;
import com.planblindbox.entity.TaskCategory;
import com.planblindbox.mapper.TaskRecordMapper;
import com.planblindbox.service.TaskService;
import com.planblindbox.service.RewardService;
import com.planblindbox.service.rule.TaskPriorityCalculator;
import com.planblindbox.util.BusinessTime;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class TaskServiceImpl implements TaskService {

    private final TaskMapper taskMapper;
    private final TaskCategoryMapper taskCategoryMapper;
    private final TaskRecordMapper taskRecordMapper;
    private final RewardService rewardService;
    private final ObjectMapper objectMapper;


    @Override
    public TaskResponse create(TaskCreateRequest request) {

        LocalDateTime now = LocalDateTime.now();

        LocalDateTime effectiveStart =
                request.getStartTime() != null
                        ? request.getStartTime()
                        : now;

        // 未指定截止时间时，默认截止于开始时间之后的下一个业务日切换点（凌晨 12 点）。
        // 如果用户明确设置了截止时间（例如长期任务），则保留用户指定的时间。
        LocalDateTime effectiveEnd = request.getEndTime() != null
                ? request.getEndTime()
                : BusinessTime.nextReset(effectiveStart);

        checkTime(effectiveStart, effectiveEnd);

        if (!effectiveEnd.isAfter(now)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "截止时间必须晚于当前时间"
            );
        }

        Task task = new Task();

        task.setUserId(request.getUserId());
        task.setTitle(request.getTitle());
        task.setNote(request.getNote());
        task.setStartTime(effectiveStart);
        task.setEndTime(effectiveEnd);
        task.setTargetCount(request.getTargetCount());
        task.setCategoryId(resolveCategoryId(request.getUserId(), request.getCategoryId()));
        task.setRecordRule(
                validateAndSerializeRecordRule(request.getRecordRule())
        );
        task.setStatus(TaskStatus.PENDING);
        task.setUrgency(request.getUrgency());
        task.setEstimatedMinutes(request.getEstimatedMinutes());


        int importance = request.getImportance() == null
                ? 3 : request.getImportance();

        int difficulty = request.getDifficulty() == null
                ? 3 : request.getDifficulty();

        task.setImportance(importance);
        task.setUrgency(request.getUrgency());
        task.setDifficulty(difficulty);
        task.setEstimatedMinutes(request.getEstimatedMinutes());

        task.setPriorityScore(
                TaskPriorityCalculator.calculate(importance, difficulty)
        );


        taskMapper.insert(task);

        Task savedTask = taskMapper.selectById(
                task.getTaskId(),
                task.getUserId()
        );

        return toResponse(savedTask);
    }


    @Override
    public TaskResponse getById(Long userId, Long taskId) {

        Task task = getEntity(userId, taskId);

        return toResponse(task);
    }


    private String validateAndSerializeRecordRule(JsonNode rule) {

        // 1. 没有传规则，兼容旧任务，返回 null
        if (rule == null || rule.isNull()) {
            return null;
        }

        // 2. 必须是 JSON 对象
        if (!rule.isObject()) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "recordRule 必须是 JSON 对象"
            );
        }

        // 3. 必须包含字符串类型的 mode
        JsonNode modeNode = rule.get("mode");

        if (modeNode == null || !modeNode.isTextual()) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "recordRule 必须包含字符串类型的 mode"
            );
        }

        String mode = modeNode.asText();

        // 4. 根据不同模式校验规则
        switch (mode) {

            case "DEFAULT":
            case "MANUAL":
                // 这两种模式只允许 mode 字段
                if (rule.size() != 1) {
                    throw new ResponseStatusException(
                            HttpStatus.BAD_REQUEST,
                            mode + " 模式只允许 mode 字段"
                    );
                }
                break;

            case "FIXED":
                JsonNode countNode = rule.get("count");

                // 必须包含 mode、count 两个字段
                if (rule.size() != 2
                        || countNode == null
                        || !countNode.isIntegralNumber()
                        || !countNode.canConvertToInt()
                        || countNode.intValue() <= 0) {

                    throw new ResponseStatusException(
                            HttpStatus.BAD_REQUEST,
                            "FIXED 模式必须提供正整数 count"
                    );
                }
                break;

            default:
                throw new ResponseStatusException(
                        HttpStatus.BAD_REQUEST,
                        "不支持的记录模式：" + mode
                );
        }

        // 5. 校验成功，将 JSON 转换成字符串
        try {
            return objectMapper.writeValueAsString(rule);

        } catch (JsonProcessingException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "recordRule 无法序列化",
                    e
            );
        }
    }


    @Override
    public List<TaskResponse> list(Long userId) {

        List<Task> taskList =
                taskMapper.selectByUserId(userId);

        return taskList.stream()
                .map(this::toResponse)
                .toList();
    }


    @Override
    @Transactional
    public TaskResponse update(
            Long userId,
            Long taskId,
            TaskUpdateRequest request
    ) {

        // 注意：这里不能调用 getById()
        // 因为 getById() 返回的是 TaskResponse
        // 更新与完成使用同一把 Task 行锁，避免两种操作并发覆盖状态。
        Task task = taskMapper.selectByIdForUpdate(taskId, userId);
        if (task == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Task不存在");
        }

        // COMPLETED 必须由 /complete 生成执行记录后自动设置，不能由 PUT 绕过。
        if (request.getStatus() == TaskStatus.COMPLETED) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "请通过 /complete 完成任务");
        }
        // 已完成任务不允许通过 PUT 改回进行中状态。
        if (task.getStatus() == TaskStatus.COMPLETED && request.getStatus() != null
                && request.getStatus() != TaskStatus.COMPLETED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "已完成的任务不能通过 PUT 改变状态");
        }
        // 防止历史进度超出修改后的目标，或已完成任务变得不再完成。
        if (request.getTargetCount() != null) {
            long finished = taskRecordMapper.sumActualCount(taskId);
            if (request.getTargetCount() < finished
                    || (task.getStatus() == TaskStatus.COMPLETED
                        && !request.getTargetCount().equals(task.getTargetCount()))) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "新目标不能小于已完成数量；已完成任务不能修改目标");
            }
            // 已有进度的任务不能通过修改目标直接达到完成条件，必须通过 /complete。
            if (finished > 0 && request.getTargetCount() == finished
                    && task.getStatus() != TaskStatus.COMPLETED) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "新目标须大于已有进度，请通过 /complete 完成任务");
            }
        }

        if (request.getTitle() != null) {
            task.setTitle(request.getTitle());
        }

        if (request.getNote() != null) {
            task.setNote(request.getNote());
        }

        if (request.getStartTime() != null) {
            task.setStartTime(request.getStartTime());
        }

        // 只有请求明确传入截止时间时才覆盖；未传入时保留数据库中的原截止时间。
        // 仅对历史数据中截止时间缺失的任务补上默认业务日截止点。
        if (request.getEndTime() != null) {
            task.setEndTime(request.getEndTime());
        } else if (task.getEndTime() == null) {
            task.setEndTime(BusinessTime.effectiveDeadline(
                    null, task.getStartTime(), task.getCreateTime()));
        }


        // 分类 ID 为 0 表示主动清除分类；null 表示编辑请求未修改分类。
        // 已停用分类可以继续保留在原任务上，但不能重新分配给其他任务。
        if (request.getCategoryId() != null) {
            Long requestedCategoryId = request.getCategoryId();
            if (requestedCategoryId == 0L) {
                task.setCategoryId(null);
            } else if (!requestedCategoryId.equals(task.getCategoryId())) {
                task.setCategoryId(resolveCategoryId(userId, requestedCategoryId));
            }
        }

        // 修改任务目标数量
        if (request.getTargetCount() != null) {
            task.setTargetCount(request.getTargetCount());
        }

// 修改任务记录规则
        if (request.getRecordRule() != null) {
            task.setRecordRule(
                    validateAndSerializeRecordRule(request.getRecordRule())
            );
        }

        if (request.getStatus() != null) {
            task.setStatus(request.getStatus());
        }

        if (request.getImportance() != null) {
            task.setImportance(request.getImportance());
        }

        if (request.getUrgency() != null) {
            task.setUrgency(request.getUrgency());
        }

        if (request.getDifficulty() != null) {
            task.setDifficulty(request.getDifficulty());
        }

        if (task.getImportance() == null){
            task.setImportance(3);
        }

        if(task.getDifficulty() == null ){
            task.setDifficulty(3);
        }

        if (task.getImportance() == null) {
            task.setImportance(3);
        }

        if (task.getDifficulty() == null) {
            task.setDifficulty(3);
        }

        task.setPriorityScore(
                TaskPriorityCalculator.calculate(
                        task.getImportance(),
                        task.getDifficulty()
                )
        );

        task.setPriorityScore(BigDecimal.valueOf(task.getImportance()+ task.getDifficulty()));

        if (request.getEstimatedMinutes() != null) {
            task.setEstimatedMinutes(
                    request.getEstimatedMinutes()
            );
        }

        checkTime(
                task.getStartTime(),
                task.getEndTime()
        );

        taskMapper.update(task);

        Task updatedTask =
                getEntity(userId, taskId);

        return toResponse(updatedTask);
    }


    /**
     * 追加本次执行数量；同一 Task 的所有完成请求按行锁顺序串行执行。
     * 达到目标后调用 RewardService，奖励结算与任务进度处于同一个事务。
     */
    @Override
    @Transactional
    public TaskCompleteResponse complete(Long userId, Long taskId, TaskCompleteRequest request) {
        if (request == null || request.getActualCount() == null || request.getActualCount() <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "actualCount 必须为正整数");
        }

        Task task = taskMapper.selectByIdForUpdate(taskId, userId);
        if (task == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Task不存在");
        }
        if (task.getStatus() != TaskStatus.PENDING && task.getStatus() != TaskStatus.IN_PROGRESS) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "当前任务状态不允许继续完成");
        }
        if (task.getTargetCount() == null || task.getTargetCount() <= 0) {
            throw new IllegalStateException("Task 目标数量不合法");
        }

        LocalDateTime now = LocalDateTime.now();

        LocalDateTime deadline = BusinessTime.effectiveDeadline(
                task.getEndTime(),
                task.getStartTime(),
                task.getCreateTime()
        );

        if (deadline != null && !now.isBefore(deadline)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "任务已经过期，请重新安排任务"
            );
        }

        LocalDate today = BusinessTime.businessDate(now);

        int requested = request.getActualCount();
        int total = task.getTargetCount();
        long totalBefore = taskRecordMapper.sumActualCount(taskId);
// ① 检查是否已经达到目标
        if (totalBefore >= total) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "历史数量已达到目标，请检查任务状态"
            );
        }
// ② 计算剩余数量
        long remaining = total - totalBefore;
// ③ 取请求数量与剩余数量的较小值
        int increment = (int) Math.min(requested, remaining);
// ④ 计算实际累计数量
        long totalAfter = totalBefore + increment;


        boolean completed = totalAfter == task.getTargetCount();
        TaskRecord record = taskRecordMapper.selectByTaskIdAndDate(taskId, today);
        int todayActualCount;
        if (record == null) {
            record = new TaskRecord();
            record.setTaskId(taskId);
            record.setRecordDate(today);
            record.setActualCount(increment);
            record.setStatus(completed ? TaskRecordStatus.COMPLETED : TaskRecordStatus.IN_PROGRESS);
            record.setFinishTime(completed ? now : null);
            if (taskRecordMapper.insert(record) != 1) {
                throw new IllegalStateException("新增任务执行记录失败");
            }
            todayActualCount = increment;
        } else {
            if (taskRecordMapper.incrementActualCount(record.getTaskRecordId(), increment) != 1) {
                throw new IllegalStateException("更新任务执行数量失败");
            }
            todayActualCount = Math.addExact(record.getActualCount(), increment);
            if (completed && taskRecordMapper.updateStatus(
                    record.getTaskRecordId(), TaskRecordStatus.COMPLETED, now) != 1) {
                throw new IllegalStateException("更新任务执行状态失败");
            }
        }

        TaskStatus status = completed ? TaskStatus.COMPLETED : TaskStatus.IN_PROGRESS;
        if (taskMapper.updateProgressStatus(taskId, userId, status) != 1) {
            throw new IllegalStateException("更新任务状态失败");
        }

        // 仅在首次达到目标时触发一次结算；任务行锁 + 已完成状态校验阻止重复发奖。
        // 任何奖励 SQL 出错，都会回滚 TaskRecord、Task 状态及已写入的资产数据。
        TaskRewardResponse reward = completed
                ? rewardService.rewardTaskCompletion(
                userId,
                taskId,
                task.getImportance(),
                task.getDifficulty()
        )
                : null;

        TaskCompleteResponse response = new TaskCompleteResponse();
        response.setTaskId(taskId);
        response.setRecordDate(today);
        response.setIncrementCount(increment);
        response.setTodayActualCount(todayActualCount);
        response.setTotalActualCount(totalAfter);
        response.setTargetCount(task.getTargetCount());
        response.setRemainingCount((int) (task.getTargetCount() - totalAfter));
        response.setStatus(status);
        response.setReward(reward);
        return response;
    }


    @Override
    public void delete(Long userId, Long taskId) {

        // 先确保任务存在
        getEntity(userId, taskId);

        taskMapper.archive(taskId, userId);
    }


    /**
     * Service内部使用。
     * 返回数据库实体，不暴露给Controller。
     */
    private Task getEntity(Long userId, Long taskId) {

        Task task =
                taskMapper.selectById(taskId, userId);

        if (task == null) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "Task不存在"
            );
        }

        return task;
    }


    /**
     * Entity -> Response
     */
    private TaskResponse toResponse(Task task) {

        TaskResponse response = new TaskResponse();

        response.setTaskId(task.getTaskId());
        response.setTitle(task.getTitle());
        response.setNote(task.getNote());
        response.setStartTime(task.getStartTime());
        response.setEndTime(BusinessTime.effectiveDeadline(
                task.getEndTime(), task.getStartTime(), task.getCreateTime()));
        response.setTargetCount(task.getTargetCount());
        response.setCategoryId(task.getCategoryId());
        String recordRule = task.getRecordRule();

        if (recordRule == null){
            response.setRecordRule(null);
        }else{
            try {
                //把数据库存的 JSON 字符串，解析成 Jackson 的`JsonNode`树形对象
                response.setRecordRule(
                        objectMapper.readTree(recordRule)
                );
            }catch (JsonProcessingException e) {
                throw new IllegalStateException(
                        "数据库 record_rule 不是合法 JSON", e
                );
            }
        }

        response.setStatus(task.getStatus());
        response.setImportance(task.getImportance());
        response.setUrgency(task.getUrgency());
        response.setDifficulty(task.getDifficulty());
        response.setPriorityScore(task.getPriorityScore());
        response.setEstimatedMinutes(task.getEstimatedMinutes());

        return response;
    }



    /**
     * 验证分类归属当前用户且处于启用状态。0/null 均表示未分类。
     */
    private Long resolveCategoryId(Long userId, Long categoryId) {
        if (categoryId == null || categoryId == 0L) {
            return null;
        }
        TaskCategory category = taskCategoryMapper.selectById(userId, categoryId);
        if (category == null) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "任务分类不存在或不属于当前用户"
            );
        }
        if (!Boolean.TRUE.equals(category.getEnabled())) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "该任务分类已停用，不能用于新任务或修改任务分类"
            );
        }
        return categoryId;
    }

    private void checkTime(
            LocalDateTime start,
            LocalDateTime end
    ) {

        if (start != null
                && end != null
                && end.isBefore(start)) {

            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "结束时间不能早于开始时间"
            );
        }
    }
}