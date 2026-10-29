package com.planblindbox.dto.response;

import com.fasterxml.jackson.databind.JsonNode;
import com.planblindbox.enums.HabitStatus;
import lombok.Data;

import java.time.LocalDate;

@Data
public class HabitResponse {
    private Long habitId;
    private String name;
    private String note;
    private LocalDate startDate;
    private LocalDate endDate;
    private Integer importance;
    private Integer difficulty;
    private JsonNode repeatRule;
    private HabitStatus status;
}
