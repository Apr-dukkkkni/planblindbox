package com.planblindbox.mod.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;

/** 可选的 Redis 原子计数限流。仅针对来源 IP + Mod 的请求频率，不代替身份认证/反作弊。 */
@Component
public class DownloadRateLimiter {
    private static final Logger log = LoggerFactory.getLogger(DownloadRateLimiter.class);
    private static final DefaultRedisScript<Long> HIT = new DefaultRedisScript<>(
        "local n=redis.call('INCR',KEYS[1]); " +
        "if n==1 then redis.call('EXPIRE',KEYS[1],ARGV[1]); end; return n", Long.class);
    private final StringRedisTemplate redis;
    private final boolean enabled;
    private final int limit;

    public DownloadRateLimiter(ObjectProvider<StringRedisTemplate> redis,
                               @Value("${mod.download-rate-limit.enabled:false}") boolean enabled,
                               @Value("${mod.download-rate-limit.max-per-minute:120}") int limit) {
        this.redis = redis.getIfAvailable();
        this.enabled = enabled;
        this.limit = limit;
        if (enabled && limit < 1) throw new IllegalArgumentException("下载限流阈值必须大于 0");
    }

    public void check(String modId, String remoteAddress) {
        if (!enabled) return;
        if (redis == null) {
            log.warn("下载限流已开启但没有 Redis，按可用性优先策略放行");
            return;
        }
        // 不信任客户端提供的 X-Forwarded-For；反向代理部署应先配置可信代理。
        String ip = (remoteAddress == null || remoteAddress.isBlank()) ? "unknown" : remoteAddress;
        long window = Instant.now().getEpochSecond() / 60;
        String key = "plan:mod:rate:v1:" + digest(ip + "|" + modId) + ":" + window;
        try {
            Long count = redis.execute(HIT, List.of(key), "120");
            if (count != null && count > limit) {
                throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "下载请求过于频繁，请稍后再试");
            }
        } catch (ResponseStatusException tooMany) {
            throw tooMany;
        } catch (Exception error) {
            // 保持 V2.3 的 Redis 故障降级能力；这不是强安全边界。
            log.warn("Redis 下载限流不可用，放行并等待恢复：{}", error.toString());
        }
    }

    private String digest(String raw) {
        try {
            byte[] bytes = MessageDigest.getInstance("SHA-256").digest(raw.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(bytes);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("JDK 不支持 SHA-256", e);
        }
    }
}
