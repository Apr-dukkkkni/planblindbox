package com.planblindbox.mapper;

import com.planblindbox.entity.DailySignIn;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Options;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import java.util.List;

import java.time.LocalDate;

public interface DailySignInMapper {

    @Select("""
        SELECT
            sign_in_id AS signInId,
            user_id AS userId,
            business_date AS businessDate,
            streak_day AS streakDay,
            base_water AS baseWater,
            bonus_water AS bonusWater,
            total_water AS totalWater,
            create_time AS createTime
        FROM daily_sign_in
        WHERE user_id = #{userId}
          AND business_date >= #{startDate}
          AND business_date < #{endDateExclusive}
        ORDER BY business_date ASC
        """)
    List<DailySignIn> selectByDateRange(
            @Param("userId") Long userId,
            @Param("startDate") LocalDate startDate,
            @Param("endDateExclusive") LocalDate endDateExclusive
    );

    @Select("""
            SELECT
                sign_in_id AS signInId,
                user_id AS userId,
                business_date AS businessDate,
                streak_day AS streakDay,
                base_water AS baseWater,
                bonus_water AS bonusWater,
                total_water AS totalWater,
                create_time AS createTime
            FROM daily_sign_in
            WHERE user_id = #{userId}
              AND business_date = #{businessDate}
            """)
    DailySignIn selectByBusinessDate(
            @Param("userId") Long userId,
            @Param("businessDate") LocalDate businessDate
    );

    // 发生并发重复签到时，使用当前读获取已提交的记录。
    @Select("""
            SELECT
                sign_in_id AS signInId,
                user_id AS userId,
                business_date AS businessDate,
                streak_day AS streakDay,
                base_water AS baseWater,
                bonus_water AS bonusWater,
                total_water AS totalWater,
                create_time AS createTime
            FROM daily_sign_in
            WHERE user_id = #{userId}
              AND business_date = #{businessDate}
            FOR UPDATE
            """)
    DailySignIn selectByBusinessDateForUpdate(
            @Param("userId") Long userId,
            @Param("businessDate") LocalDate businessDate
    );

    // INSERT IGNORE 配合数据库唯一索引，避免并发重复签到。
    @Insert("""
            INSERT IGNORE INTO daily_sign_in (
                user_id,
                business_date,
                streak_day,
                base_water,
                bonus_water,
                total_water
            )
            VALUES (
                #{userId},
                #{businessDate},
                #{streakDay},
                #{baseWater},
                #{bonusWater},
                #{totalWater}
            )
            """)
    @Options(useGeneratedKeys = true,
            keyProperty = "signInId",
            keyColumn = "sign_in_id")
    int insertIfAbsent(DailySignIn signIn);
}