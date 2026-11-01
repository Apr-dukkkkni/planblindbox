package com.planblindbox.mod.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** 排名缓存只包含 MySQL 中下载计数的投影；MySQL 仍为权威来源。 */
@Service
public class RankingService {
    private static final Logger log = LoggerFactory.getLogger(RankingService.class);
    private static final String KEY = "plan:mod:downloads:all";
    private static final String SQL_LEADERBOARD = """
        SELECT p.mod_id AS id, p.name, p.description, p.latest_version AS latestVersion,
               COUNT(e.id) AS downloads
          FROM mod_packages p LEFT JOIN mod_download_events e ON e.mod_id = p.mod_id
         WHERE p.enabled = TRUE
         GROUP BY p.mod_id, p.name, p.description, p.latest_version
         ORDER BY downloads DESC, p.mod_id ASC LIMIT ?
        """;
    private static final DefaultRedisScript<Long> SET_MAX = new DefaultRedisScript<>(
        "local old=redis.call('ZSCORE',KEYS[1],ARGV[1]); " +
        "if (not old) or (tonumber(ARGV[2])>tonumber(old)) then " +
        "redis.call('ZADD',KEYS[1],ARGV[2],ARGV[1]); return 1; end; return 0", Long.class);

    private final JdbcTemplate jdbc;
    private final StringRedisTemplate redis;
    private final boolean enabled;

    public RankingService(JdbcTemplate jdbc,
                          org.springframework.beans.factory.ObjectProvider<StringRedisTemplate> redis,
                          @Value("${mod.ranking.enabled:false}") boolean enabled) {
        this.jdbc = jdbc;
        this.redis = redis.getIfAvailable();
        this.enabled = enabled;
    }

    public List<Map<String, Object>> top(int limit) {
        if (limit < 1 || limit > 50) throw new com.planblindbox.mod.domain.BadRequest("limit 必须在 1～50 之间");
        if (!enabled || redis == null) return mysqlTop(limit);
        try {
            Set<org.springframework.data.redis.core.ZSetOperations.TypedTuple<String>> entries =
                redis.opsForZSet().reverseRangeWithScores(KEY, 0, Math.max(200, limit * 5));
            if (entries == null || entries.isEmpty()) return mysqlTop(limit);
            List<Map<String, Object>> result = new ArrayList<>();
            for (var entry : entries) {
                String modId = entry.getValue();
                if (modId == null) continue;
                var rows = jdbc.queryForList(
                    "SELECT mod_id AS id,name,description,latest_version AS latestVersion FROM mod_packages WHERE mod_id=? AND enabled=TRUE", modId);
                if (rows.isEmpty()) continue;
                Map<String, Object> mod = new LinkedHashMap<>(rows.get(0));
                mod.put("downloads", entry.getScore() == null ? 0L : entry.getScore().longValue());
                result.add(mod);
                if (result.size() >= limit) break;
            }
            return result.isEmpty() ? mysqlTop(limit) : result;
        } catch (Exception e) {
            log.warn("Redis 排名不可用，回退 MySQL：{}", e.toString());
            return mysqlTop(limit);
        }
    }

    private List<Map<String, Object>> mysqlTop(int limit) {
        return jdbc.queryForList(SQL_LEADERBOARD, limit);
    }

    public void refreshOne(String modId) {
        if (!enabled || redis == null) return;
        Long count = jdbc.queryForObject(
            "SELECT COUNT(*) FROM mod_download_events WHERE mod_id=?", Long.class, modId);
        // 允许 0 次下载时初始化排名：即使从未下载也可按其他规则查询。
        redis.execute(SET_MAX, List.of(KEY), modId, Long.toString(count == null ? 0 : count));
    }

    /** 周期性从 MySQL 对账；Redis 刷新失败不会影响下载 API。 */
    @Scheduled(initialDelayString = "${mod.ranking.reconcile-initial-delay-ms:10000}",
               fixedDelayString = "${mod.ranking.reconcile-interval-ms:60000}")
    @ConditionalOnProperty(name = "mod.ranking.enabled", havingValue = "true")
    public void reconcile() {
        if (redis == null) return;
        try {
            var rows = jdbc.queryForList("""
                SELECT p.mod_id AS id, COUNT(e.id) AS downloads
                FROM mod_packages p LEFT JOIN mod_download_events e ON e.mod_id=p.mod_id
                GROUP BY p.mod_id
                """);
            for (var row : rows) {
                redis.execute(SET_MAX, List.of(KEY),
                    (String) row.get("id"), String.valueOf(((Number) row.get("downloads")).longValue()));
            }
        } catch (Exception e) {
            log.warn("排行榜对账失败，将在下周期重试：{}", e.toString());
        }
    }
}
