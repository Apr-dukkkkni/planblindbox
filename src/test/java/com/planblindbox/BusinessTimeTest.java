package com.planblindbox;

import com.planblindbox.util.BusinessTime;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;

class BusinessTimeTest {

    @Test
    void explicitCustomDeadlineIsPreserved() {
        LocalDateTime customEnd = LocalDateTime.of(2026, 11, 9, 18, 30);
        LocalDateTime start = LocalDateTime.of(2026, 10, 26, 10, 0);
        LocalDateTime created = LocalDateTime.of(2026, 10, 26, 10, 1);

        assertEquals(customEnd, BusinessTime.effectiveDeadline(customEnd, start, created));
    }

    @Test
    void missingDeadlineDefaultsToNextFiveAmReset() {
        LocalDateTime start = LocalDateTime.of(2026, 10, 26, 10, 0);
        LocalDateTime created = LocalDateTime.of(2026, 10, 26, 10, 1);

        assertEquals(LocalDateTime.of(2026, 10, 27, 5, 0),
                BusinessTime.effectiveDeadline(null, start, created));
    }

    @Test
    void taskStartedBeforeFiveAmEndsAtCurrentCalendarDayFiveAm() {
        LocalDateTime start = LocalDateTime.of(2026, 10, 27, 3, 30);

        assertEquals(LocalDateTime.of(2026, 10, 27, 5, 0),
                BusinessTime.effectiveDeadline(null, start, start));
        assertEquals(LocalDate.of(2026, 10, 26), BusinessTime.businessDate(start));
    }
}
