
package com.planblindbox;

import com.planblindbox.dto.response.DailySignInResponse;
import com.planblindbox.service.DailySignInService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.sql.Statement;
import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Objects;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;


@SpringBootTest
@Transactional
class DailySignInIntegrationTest {

    private static final ZoneId ZONE =
            ZoneId.of("Asia/Shanghai");

    @Autowired
    private DailySignInService dailySignInService;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private MutableClock clock;
    private void setNow(LocalDateTime time) {
        clock.setInstant(time.atZone(ZONE).toInstant());
    }



    @Test
    void firstSignInGrantsFiveWaterAndDuplicateDoesNotGrantAgain() {
        setNow(LocalDateTime.of(2026, 10, 28, 12, 0));

        long userId = newUser();

        DailySignInResponse first =
                dailySignInService.signIn(userId);

        assertTrue(first.isGranted());
        assertEquals(LocalDate.of(2026, 10, 28),
                first.getBusinessDate());
        assertEquals(1, first.getStreakDay());
        assertEquals(5, first.getTotalWater());
        assertEquals(5, first.getWaterBalance());

        DailySignInResponse second =
                dailySignInService.signIn(userId);

        assertFalse(second.isGranted());
        assertEquals(5, second.getWaterBalance());

        assertEquals(1, jdbc.queryForObject(
                "SELECT COUNT(*) FROM daily_sign_in WHERE user_id=?",
                Integer.class, userId));

        assertEquals(1, countSignInLedgers(userId));
    }

    @Test
    void seventhFourteenthAndTwentyFirstDayGrantCorrectBonus() {
        setNow(LocalDateTime.of(2026, 10, 28, 12, 0));

        LocalDate today = LocalDate.of(2026, 10, 28);

        // 连续天数、额外奖励、当日总奖励
        int[][] cases = {
                {7, 10, 15},
                {14, 15, 20},
                {21, 30, 35}
        };

        for (int[] item : cases) {
            int streakDay = item[0];
            int expectedBonus = item[1];
            int expectedTotal = item[2];

            long userId = newUser();

            // 构造前一个业务日的签到记录。
            seedPreviousSignIn(
                    userId,
                    today.minusDays(1),
                    streakDay - 1
            );

            DailySignInResponse response =
                    dailySignInService.signIn(userId);

            assertTrue(response.isGranted());
            assertEquals(streakDay, response.getStreakDay());
            assertEquals(expectedBonus, response.getBonusWater());
            assertEquals(expectedTotal, response.getTotalWater());

            assertEquals(expectedTotal, jdbc.queryForObject(
                    "SELECT water FROM user_asset WHERE user_id=?",
                    Integer.class, userId));
        }
    }

    @Test
    void firstDayOfMonthResetsStreakAndGrantsOnlyFiveWater() {
        setNow(LocalDateTime.of(2026, 11, 1, 12, 0));

        long userId = newUser();

        // 上个月最后一天仍有连续签到记录。
        seedPreviousSignIn(
                userId,
                LocalDate.of(2026, 10, 31),
                20
        );

        DailySignInResponse response =
                dailySignInService.signIn(userId);

        assertTrue(response.isGranted());
        assertEquals(LocalDate.of(2026, 11, 1),
                response.getBusinessDate());
        assertEquals(1, response.getStreakDay());
        assertEquals(0, response.getBonusWater());
        assertEquals(5, response.getTotalWater());
        assertEquals(5, response.getWaterBalance());
    }

    @Test
    void twentySecondDayReturnsToFiveWater() {
        setNow(LocalDateTime.of(2026, 10, 28, 12, 0));

        long userId = newUser();

        seedPreviousSignIn(
                userId,
                LocalDate.of(2026, 10, 27),
                21
        );

        DailySignInResponse response =
                dailySignInService.signIn(userId);

        assertTrue(response.isGranted());
        assertEquals(22, response.getStreakDay());
        assertEquals(0, response.getBonusWater());
        assertEquals(5, response.getTotalWater());
    }

    private void seedPreviousSignIn(
            long userId,
            LocalDate date,
            int streakDay
    ) {
        jdbc.update("""
                INSERT INTO daily_sign_in (
                    user_id, business_date, streak_day,
                    base_water, bonus_water, total_water
                )
                VALUES (?, ?, ?, 5, 0, 5)
                """, userId, date, streakDay);
    }

    private int countSignInLedgers(long userId) {
        return jdbc.queryForObject("""
                SELECT COUNT(*)
                FROM asset_record
                WHERE user_id = ?
                  AND action = 'DAILY_SIGN_IN'
                  AND asset_type = 'WATER'
                """, Integer.class, userId);
    }

    private long newUser() {
        GeneratedKeyHolder keys = new GeneratedKeyHolder();

        jdbc.update(connection -> {
            var ps = connection.prepareStatement("""
                    INSERT INTO app_user (username, email, password)
                    VALUES (?, ?, ?)
                    """, Statement.RETURN_GENERATED_KEYS);

            ps.setString(1, "daily-sign-test");
            ps.setString(2,
                    "ds-" + UUID.randomUUID() + "@example.com");
            ps.setString(3, "not-a-real-password");

            return ps;
        }, keys);

        return Objects.requireNonNull(keys.getKey()).longValue();
    }

    @TestConfiguration
    static class TestClockConfig {

        @Bean
        @Primary
        MutableClock testClock() {
            return new MutableClock(
                    Instant.parse("2026-10-28T04:00:00Z"),
                    ZoneId.of("Asia/Shanghai")
            );
        }
    }

    static class MutableClock extends Clock {

        private volatile Instant instant;
        private final ZoneId zone;

        MutableClock(Instant instant, ZoneId zone) {
            this.instant = instant;
            this.zone = zone;
        }

        void setInstant(Instant instant) {
            this.instant = instant;
        }

        @Override
        public ZoneId getZone() {
            return zone;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return new MutableClock(instant, zone);
        }

        @Override
        public Instant instant() {
            return instant;
        }
    }
}
