package com.planblindbox.mod.sync;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class SyncEntitlementService {
    private final JdbcTemplate jdbc;
    public SyncEntitlementService(JdbcTemplate jdbc) { this.jdbc = jdbc; }
    public boolean active(long userId) {
        Integer count = jdbc.queryForObject(
            "SELECT COUNT(*) FROM user_sync_entitlement WHERE user_id=? AND expires_at>CURRENT_TIMESTAMP",
            Integer.class,userId);
        return count!=null && count>0;
    }
    public void require(long userId) {
        if (!active(userId)) throw new ResponseStatusException(HttpStatus.FORBIDDEN,"需要有效的云同步订阅");
    }
}
