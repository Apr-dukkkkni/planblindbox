package com.planblindbox.mod;

import com.planblindbox.mod.service.DownloadRateLimiter;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class DownloadRateLimiterTest {
    @SuppressWarnings("unchecked")
    private ObjectProvider<StringRedisTemplate> provider(StringRedisTemplate redis) {
        ObjectProvider<StringRedisTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(redis);
        return provider;
    }

    @Test void refusesRequestsAboveLimit() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(org.springframework.data.redis.core.script.RedisScript.class), anyList(), eq("120")))
            .thenReturn(1L).thenReturn(2L).thenReturn(3L);
        var limiter = new DownloadRateLimiter(provider(redis), true, 2);
        limiter.check("com.example.safe", "127.0.0.1");
        limiter.check("com.example.safe", "127.0.0.1");
        assertThatThrownBy(() -> limiter.check("com.example.safe", "127.0.0.1"))
            .isInstanceOfSatisfying(ResponseStatusException.class,
                e -> assertThat(e.getStatusCode()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS));
    }

    @Test void disabledLimiterNeverTouchesRedis() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        new DownloadRateLimiter(provider(redis), false, 2).check("com.example.safe", "127.0.0.1");
        verifyNoInteractions(redis);
    }

    @Test void redisFailureDoesNotBreakDownload() {
        StringRedisTemplate redis = mock(StringRedisTemplate.class);
        when(redis.execute(any(org.springframework.data.redis.core.script.RedisScript.class), anyList(), eq("120")))
            .thenThrow(new IllegalStateException("redis down"));
        new DownloadRateLimiter(provider(redis), true, 2).check("com.example.safe", "127.0.0.1");
    }
}
