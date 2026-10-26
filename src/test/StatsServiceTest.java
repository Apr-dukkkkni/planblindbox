package com.planblindbox.service;

import com.planblindbox.dto.response.StatsResponse;
import com.planblindbox.entity.AppUser;
import com.planblindbox.entity.UserAsset;
import com.planblindbox.mapper.AppUserMapper;
import com.planblindbox.mapper.StatsMapper;
import com.planblindbox.mapper.UserAssetMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class StatsServiceTest {
    @Mock StatsMapper statsMapper;
    @Mock AppUserMapper appUserMapper;
    @Mock UserAssetMapper userAssetMapper;
    @InjectMocks StatsService service;

    private void emptyQueries() {
        when(appUserMapper.selectById(1L)).thenReturn(new AppUser());
        when(statsMapper.completedTasks(eq(1L), any(), any())).thenReturn(List.of());
        when(statsMapper.completedHabits(eq(1L), any(), any())).thenReturn(List.of());
        when(statsMapper.dailyAssets(eq(1L), any(), any())).thenReturn(List.of());
    }

    @Test
    void zeroFillsSevenDaysAndUsesBusinessDateBeforeFive() {
        emptyQueries();
        StatsResponse result = service.getStatsAt(1L, 7,
                LocalDateTime.of(2026, 10, 26, 4, 59));
        assertEquals(LocalDate.of(2026, 10, 25), result.endDate());
        assertEquals(LocalDate.of(2026, 10, 19), result.startDate());
        assertEquals(7, result.daily().size());
        assertEquals(0, result.summary().completedTasks());
        assertEquals(0, result.summary().coinBalance());
        verify(statsMapper).dailyAssets(eq(1L),
                eq(LocalDateTime.of(2026, 10, 19, 5, 0)),
                eq(LocalDateTime.of(2026, 10, 26, 5, 0)));
    }

    @Test
    void atExactlyFiveDateChangesAndThirtyDaysAreReturned() {
        emptyQueries();
        StatsResponse result = service.getStatsAt(1L, 30,
                LocalDateTime.of(2026, 10, 26, 5, 0));
        assertEquals(LocalDate.of(2026, 10, 26), result.endDate());
        assertEquals(30, result.daily().size());
        assertEquals(LocalDate.of(2026, 9, 27), result.startDate());
    }

    @Test
    void aggregatesAndBackCalculatesDailyBalances() {
        when(appUserMapper.selectById(1L)).thenReturn(new AppUser());
        LocalDate today = LocalDate.of(2026, 10, 25);
        LocalDate yesterday = today.minusDays(1);
        StatsMapper.DailyCount done = new StatsMapper.DailyCount();
        done.setDay(today);
        done.setCompletedCount(2L);
        when(statsMapper.completedTasks(eq(1L), any(), any())).thenReturn(List.of(done));
        StatsMapper.DailyCount habit = new StatsMapper.DailyCount();
        habit.setDay(yesterday);
        habit.setCompletedCount(3L);
        when(statsMapper.completedHabits(eq(1L), any(), any())).thenReturn(List.of(habit));

        StatsMapper.DailyAssets prev = new StatsMapper.DailyAssets();
        prev.setDay(yesterday);
        prev.setCoinEarned(50L);
        prev.setCoinSpent(0L);
        prev.setCoinNet(50L);
        prev.setExpEarned(30L);
        prev.setExpNet(30L);
        StatsMapper.DailyAssets current = new StatsMapper.DailyAssets();
        current.setDay(today);
        current.setCoinEarned(10L);
        current.setCoinSpent(20L);
        current.setCoinNet(-10L);
        current.setExpEarned(15L);
        current.setExpNet(15L);
        when(statsMapper.dailyAssets(eq(1L), any(), any()))
                .thenReturn(List.of(prev, current));

        UserAsset assets = new UserAsset();
        assets.setCoin(100);
        assets.setExp(500L);
        assets.setWater(12);
        when(userAssetMapper.selectByUserId(1L)).thenReturn(assets);

        StatsResponse result = service.getStatsAt(1L, 7,
                LocalDateTime.of(2026, 10, 25, 20, 0));
        assertEquals(2, result.summary().completedTasks());
        assertEquals(3, result.summary().habitCheckIns());
        assertEquals(60, result.summary().coinEarned());
        assertEquals(20, result.summary().coinSpent());
        assertEquals(45, result.summary().expEarned());
        assertEquals(100, result.summary().coinBalance());
        assertEquals(500, result.summary().expBalance());
        assertEquals(12, result.summary().waterBalance());
        assertEquals(110, result.daily().get(5).coinBalance()); // 昨日末
        assertEquals(100, result.daily().get(6).coinBalance()); // 今日当前
        assertEquals(485, result.daily().get(5).expBalance());
        assertEquals(500, result.daily().get(6).expBalance());
    }

    @Test
    void invalidArgumentsAreRejectedBeforeAnyQueries() {
        ResponseStatusException invalidDays = assertThrows(ResponseStatusException.class,
                () -> service.getStatsAt(1L, 14, LocalDateTime.of(2026, 10, 25, 12, 0)));
        assertEquals(HttpStatus.BAD_REQUEST, invalidDays.getStatusCode());
        ResponseStatusException invalidUser = assertThrows(ResponseStatusException.class,
                () -> service.getStatsAt(0L, 7, LocalDateTime.of(2026, 10, 25, 12, 0)));
        assertEquals(HttpStatus.BAD_REQUEST, invalidUser.getStatusCode());
        verifyNoInteractions(statsMapper, appUserMapper, userAssetMapper);
    }

    @Test
    void missingUserIsRejected() {
        ResponseStatusException missing = assertThrows(ResponseStatusException.class,
                () -> service.getStatsAt(42L, 7, LocalDateTime.of(2026, 10, 25, 12, 0)));
        assertEquals(HttpStatus.NOT_FOUND, missing.getStatusCode());
        verify(appUserMapper).selectById(42L);
        verifyNoInteractions(statsMapper, userAssetMapper);
    }
}
