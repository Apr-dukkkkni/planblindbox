package com.planblindbox.mapper;

import com.planblindbox.entity.HabitRecord;
import org.apache.ibatis.annotations.*;

import java.time.LocalDate;
import java.util.List;

/** 习惯记录只由 HabitCheckInService 创建，不提供任意写入接口。 */
public interface HabitRecordMapper {
    @Insert("""
            INSERT INTO habit_record (habit_id, record_date, status, finish_time, actual_count)
            VALUES (#{habitId}, #{recordDate}, #{status}, #{finishTime}, #{actualCount})
            """)
    @Options(useGeneratedKeys = true, keyProperty = "habitRecordId", keyColumn = "habit_record_id")
    int insert(HabitRecord record);

    @Select("""
            SELECT * FROM habit_record
            WHERE habit_id = #{habitId} AND record_date = #{recordDate}
            """)
    HabitRecord selectByHabitIdAndDate(@Param("habitId") Long habitId,
                                      @Param("recordDate") LocalDate recordDate);

    @Select("""
            SELECT record_date FROM habit_record
            WHERE habit_id = #{habitId} AND status = 'COMPLETED'
            ORDER BY record_date DESC
            """)
    List<LocalDate> selectCompletedDates(@Param("habitId") Long habitId);
}
