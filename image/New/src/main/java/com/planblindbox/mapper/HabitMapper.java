package com.planblindbox.mapper;

import com.planblindbox.entity.Habit;
import org.apache.ibatis.annotations.*;

import java.util.List;

/** 注解 SQL，与现有 TaskMapper 风格保持一致。 */
public interface HabitMapper {

    @Insert("""
            INSERT INTO habit (user_id, name, note, start_date, end_date, repeat_rule, status)
            VALUES (#{userId}, #{name}, #{note}, #{startDate}, #{endDate}, CAST(#{repeatRule} AS JSON), #{status})
            """)
    @Options(useGeneratedKeys = true, keyProperty = "habitId", keyColumn = "habit_id")
    int insert(Habit habit);

    @Select("""
            SELECT * FROM habit
            WHERE habit_id = #{habitId} AND user_id = #{userId}
            """)
    Habit selectById(@Param("habitId") Long habitId, @Param("userId") Long userId);

    /** check-in / update / archive 都用习惯行锁，避免周期变更与打卡交错。 */
    @Select("""
            SELECT * FROM habit
            WHERE habit_id = #{habitId} AND user_id = #{userId}
            FOR UPDATE
            """)
    Habit selectByIdForUpdate(@Param("habitId") Long habitId, @Param("userId") Long userId);

    @Select("""
            SELECT * FROM habit
            WHERE user_id = #{userId} AND status <> 'ARCHIVED'
            ORDER BY create_time DESC, habit_id DESC
            """)
    List<Habit> selectByUserId(@Param("userId") Long userId);

    /** 日历历史查询使用：包含已归档习惯，以便展示过去已有的打卡记录。 */
    @Select("""
            SELECT * FROM habit
            WHERE user_id = #{userId}
            ORDER BY name, habit_id
            """)
    List<Habit> selectAllByUserIdForCalendar(@Param("userId") Long userId);


    @Update("""
            UPDATE habit SET
                name = #{name},
                note = #{note},
                start_date = #{startDate},
                end_date = #{endDate},
                repeat_rule = CAST(#{repeatRule} AS JSON),
                status = #{status}
            WHERE habit_id = #{habitId} AND user_id = #{userId} AND status <> 'ARCHIVED'
            """)
    int update(Habit habit);

    @Update("""
            UPDATE habit SET status = 'ARCHIVED'
            WHERE habit_id = #{habitId} AND user_id = #{userId} AND status <> 'ARCHIVED'
            """)
    int archive(@Param("habitId") Long habitId, @Param("userId") Long userId);
}
