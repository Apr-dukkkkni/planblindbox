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


    /**
     * 查询用户指定日期范围内的全部习惯打卡记录。
     */
    @Select("""
        SELECT hr.*
        FROM habit_record hr
        JOIN habit h ON h.habit_id = hr.habit_id
        WHERE h.user_id = #{userId}
          AND hr.record_date BETWEEN #{startDate} AND #{endDate}
        """)
    List<HabitRecord> selectByUserIdAndDateRange(
            @Param("userId") Long userId,
            @Param("startDate") LocalDate startDate,
            @Param("endDate") LocalDate endDate
    );

    @Select("""
            SELECT hr.*
            FROM habit_record hr
            JOIN habit h ON h.habit_id = hr.habit_id
            WHERE h.user_id = #{userId}
              AND hr.record_date = #{recordDate}
            """)
    List<HabitRecord> selectByUserIdAndDate(@Param("userId") Long userId,
                                            @Param("recordDate") LocalDate recordDate);


    @Select("""
            SELECT record_date FROM habit_record
            WHERE habit_id = #{habitId} AND status = 'COMPLETED'
            ORDER BY record_date DESC
            """)
    List<LocalDate> selectCompletedDates(@Param("habitId") Long habitId);
}
