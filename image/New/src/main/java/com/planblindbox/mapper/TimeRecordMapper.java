package com.planblindbox.mapper;

import com.planblindbox.entity.TimeRecord;
import lombok.Data;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Options;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.time.LocalDate;
import java.util.List;

public interface TimeRecordMapper {

    @Data
    class DailySummary {
        private LocalDate day;
        private Long recordCount;
        private Long totalMinutes;
    }

    @Insert("""
            INSERT INTO time_record (
                user_id, task_id, title, category, start_time, end_time,
                duration_minutes, record_date, note
            ) VALUES (
                #{userId}, #{taskId}, #{title}, #{category}, #{startTime}, #{endTime},
                #{durationMinutes}, #{recordDate}, #{note}
            )
            """)
    @Options(useGeneratedKeys = true, keyProperty = "timeRecordId", keyColumn = "time_record_id")
    int insert(TimeRecord record);

    @Select("""
            SELECT * FROM time_record
            WHERE time_record_id = #{recordId} AND user_id = #{userId}
            """)
    TimeRecord selectByIdAndUserId(@Param("recordId") Long recordId,
                                   @Param("userId") Long userId);

    @Select("""
            SELECT * FROM time_record
            WHERE user_id = #{userId} AND record_date = #{recordDate}
            ORDER BY start_time, time_record_id
            """)
    List<TimeRecord> selectByUserIdAndDate(@Param("userId") Long userId,
                                           @Param("recordDate") LocalDate recordDate);

    @Select("""
            SELECT record_date AS day,
                   COUNT(*) AS record_count,
                   COALESCE(SUM(duration_minutes), 0) AS total_minutes
            FROM time_record
            WHERE user_id = #{userId}
              AND record_date BETWEEN #{startDate} AND #{endDate}
            GROUP BY record_date
            ORDER BY record_date
            """)
    List<DailySummary> selectDailySummaries(@Param("userId") Long userId,
                                            @Param("startDate") LocalDate startDate,
                                            @Param("endDate") LocalDate endDate);

    @Update("""
            UPDATE time_record
            SET task_id = #{taskId}, title = #{title}, category = #{category},
                start_time = #{startTime}, end_time = #{endTime},
                duration_minutes = #{durationMinutes}, record_date = #{recordDate}, note = #{note}
            WHERE time_record_id = #{timeRecordId} AND user_id = #{userId}
            """)
    int update(TimeRecord record);

    @Delete("""
            DELETE FROM time_record
            WHERE time_record_id = #{recordId} AND user_id = #{userId}
            """)
    int delete(@Param("recordId") Long recordId, @Param("userId") Long userId);
}
