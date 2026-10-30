package com.planblindbox.service.impl;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.dto.request.HabitCreateRequest;
import com.planblindbox.dto.request.HabitUpdateRequest;
import com.planblindbox.dto.response.HabitResponse;
import com.planblindbox.entity.Habit;
import com.planblindbox.enums.HabitStatus;
import com.planblindbox.mapper.HabitMapper;
import com.planblindbox.service.HabitService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

@Service
@RequiredArgsConstructor
public class HabitServiceImpl implements HabitService {

    private final HabitMapper habitMapper;
    private final ObjectMapper objectMapper;

    // ===========================
    // 1. 创建习惯
    // ===========================

    @Override
    @Transactional
    public HabitResponse create(HabitCreateRequest request) {

        validateDates(
                request.getStartDate(),
                request.getEndDate()
        );

        String rule = validateAndSerializeRule(
                request.getRepeatRule()
        );

        Habit habit = new Habit();

        habit.setUserId(request.getUserId());
        habit.setName(request.getName().trim());
        habit.setNote(request.getNote());
        habit.setRepeatRule(rule);
        habit.setStatus(HabitStatus.ACTIVE);

        habit.setStartDate((request.getStartDate()));
        habit.setEndDate(request.getEndDate());

        habit.setImportance(
                request.getImportance() != null ? request.getImportance() : 3
        );
        habit.setDifficulty(
                request.getDifficulty() != null ? request.getDifficulty() : 3
        );
        habit.setRepeatRule(rule);

        if (habitMapper.insert(habit) != 1) {
            throw new IllegalStateException("创建 Habit 失败");
        }

        return toResponse(
                habitMapper.selectById(
                        habit.getHabitId(),
                        habit.getUserId()
                )
        );
    }

    // ===========================
    // 2. 查询单个习惯
    // ===========================

    @Override
    public HabitResponse getById(Long userId, Long habitId) {

        return toResponse(
                getEntity(userId, habitId)
        );
    }


    @Override
    @Transactional(readOnly = true)
    public List<HabitResponse> getArchived(Long userId) {

        if (userId == null || userId <= 0) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "userId 不合法"
            );
        }

        return habitMapper.selectArchivedByUserId(userId)
                .stream()
                .map(this::toResponse)
                .toList();
    }


    @Override
    @Transactional
    public HabitResponse restore(Long userId, Long habitId) {

        Habit habit = habitMapper.selectByIdForUpdate(
                habitId,
                userId
        );

        if (habit == null) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "Habit不存在"
            );
        }

        if (habit.getStatus() != HabitStatus.ARCHIVED) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "该习惯未归档，无需恢复"
            );
        }

        if (habitMapper.restore(habitId, userId) != 1) {
            throw new IllegalStateException("恢复 Habit 失败");
        }

        Habit restored = habitMapper.selectById(
                habitId,
                userId
        );

        if (restored == null) {
            throw new IllegalStateException(
                    "恢复 Habit 后无法读取数据"
            );
        }

        return toResponse(restored);
    }

    // ===========================
    // 3. 查询习惯列表
    // ===========================

    @Override
    public List<HabitResponse> list(Long userId) {

        return habitMapper.selectByUserId(userId)
                .stream()
                .map(this::toResponse)
                .toList();
    }

    // ===========================
    // 4. 修改习惯
    // ===========================

    @Override
    @Transactional
    public HabitResponse update(
            Long userId,
            Long habitId,
            HabitUpdateRequest request
    ) {

        Habit habit = getEntityForUpdate(userId, habitId);

        if (habit.getStatus() == HabitStatus.ARCHIVED) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "已归档习惯不能修改"
            );
        }

        if (request.getStatus() == HabitStatus.ARCHIVED) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "请通过 DELETE 接口归档习惯"
            );
        }

        if (request.getName() != null) {

            if (request.getName().isBlank()) {
                throw new ResponseStatusException(
                        HttpStatus.BAD_REQUEST,
                        "习惯名称不能为空"
                );
            }

            habit.setName(request.getName().trim());
        }

        if (request.getNote() != null) {
            habit.setNote(request.getNote());
        }

        if (request.getStartDate() != null) {
            habit.setStartDate(request.getStartDate());
        }

        if (request.getEndDate() != null) {
            habit.setEndDate(request.getEndDate());
        }

        if (request.getRepeatRule() != null) {
            habit.setRepeatRule(
                    validateAndSerializeRule(
                            request.getRepeatRule()
                    )
            );
        }

        if (request.getImportance() != null){
            habit.setImportance((request.getImportance()));
        }
        if (request.getDifficulty() != null){
            habit.setDifficulty(request.getDifficulty());
        }

        if (request.getStatus() != null) {
            habit.setStatus(request.getStatus());
        }

        validateDates(
                habit.getStartDate(),
                habit.getEndDate()
        );

        if (habitMapper.update(habit) != 1) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "习惯可能已被归档，请重新查询"
            );
        }

        return toResponse(
                habitMapper.selectById(habitId, userId)
        );
    }

    // ===========================
    // 5. 归档习惯
    // ===========================

    @Override
    @Transactional
    public void archive(Long userId, Long habitId) {

        Habit habit = getEntityForUpdate(userId, habitId);

        if (habit.getStatus() == HabitStatus.ARCHIVED) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "习惯已经归档"
            );
        }

        if (habitMapper.archive(habitId, userId) != 1) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT,
                    "习惯已经归档"
            );
        }
    }

    // ===========================
    // 6. 查询实体（加行锁）
    // ===========================

    private Habit getEntityForUpdate(
            Long userId,
            Long habitId
    ) {

        Habit habit = habitMapper.selectByIdForUpdate(
                habitId,
                userId
        );

        if (habit == null) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "Habit不存在"
            );
        }

        return habit;
    }

    // ===========================
    // 7. 查询实体
    // ===========================

    private Habit getEntity(
            Long userId,
            Long habitId
    ) {

        Habit habit = habitMapper.selectById(
                habitId,
                userId
        );

        if (habit == null) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND,
                    "Habit不存在"
            );
        }

        return habit;
    }

    // ===========================
    // 8. 校验重复规则
    // ===========================

    private String validateAndSerializeRule(JsonNode rule) {

        if (rule == null
                || !rule.isObject()
                || !rule.has("type")
                || !rule.get("type").isTextual()) {

            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "repeatRule 必须包含 type"
            );
        }

        String type = rule.get("type").asText();

        if ("DAILY".equals(type)) {

            if (rule.size() != 1) {
                throw new ResponseStatusException(
                        HttpStatus.BAD_REQUEST,
                        "DAILY 规则只允许 type 字段"
                );
            }

        } else if ("WEEKLY".equals(type)) {

            JsonNode days = rule.get("daysOfWeek");

            if (rule.size() != 2
                    || days == null
                    || !days.isArray()
                    || days.isEmpty()) {

                throw new ResponseStatusException(
                        HttpStatus.BAD_REQUEST,
                        "WEEKLY 必须提供非空 daysOfWeek 数组"
                );
            }

            Set<Integer> unique = new HashSet<>();

            for (JsonNode day : days) {

                if (!day.isIntegralNumber()
                        || !day.canConvertToInt()
                        || day.intValue() < 1
                        || day.intValue() > 7
                        || !unique.add(day.intValue())) {

                    throw new ResponseStatusException(
                            HttpStatus.BAD_REQUEST,
                            "daysOfWeek 只能是不重复的 1~7（周一到周日）"
                    );
                }
            }

        } else {

            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "当前仅支持 DAILY、WEEKLY 两种 repeatRule 类型"
            );
        }

        try {
            return objectMapper.writeValueAsString(rule);

        } catch (JsonProcessingException e) {

            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "repeatRule 无法序列化",
                    e
            );
        }
    }

    // ===========================
    // 9. 校验日期
    // ===========================

    private void validateDates(
            LocalDate start,
            LocalDate end
    ) {

        if (start == null
                || (end != null && end.isBefore(start))) {

            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "startDate 必填，且 endDate 不能早于 startDate"
            );
        }
    }

    // ===========================
    // 10. Entity 转 Response
    // ===========================

    private HabitResponse toResponse(Habit habit) {

        if (habit == null) {
            throw new IllegalStateException(
                    "Habit 写入后未查询到记录"
            );
        }

        HabitResponse response = new HabitResponse();

        response.setHabitId(habit.getHabitId());
        response.setName(habit.getName());
        response.setNote(habit.getNote());
        response.setStartDate(habit.getStartDate());
        response.setEndDate(habit.getEndDate());
        response.setStartDate(habit.getStartDate());
        response.setEndDate(habit.getEndDate());
        response.setImportance(habit.getImportance());
        response.setDifficulty(habit.getDifficulty());
        response.setStatus(habit.getStatus());

        try {
            response.setRepeatRule(
                    objectMapper.readTree(
                            habit.getRepeatRule()
                    )
            );

        } catch (JsonProcessingException e) {

            throw new IllegalStateException(
                    "数据库 repeat_rule 不是合法 JSON",
                    e
            );
        }

        return response;
    }
}