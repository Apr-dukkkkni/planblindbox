package com.planblindbox.mod.sync;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.mod.domain.BadRequest;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.List;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController @RequestMapping("/api/v1/me/progress")
public class ProgressController {
    public record Save(long expectedRevision,int schemaVersion,JsonNode payload) {}
    private final JdbcTemplate jdbc;private final ObjectMapper mapper;
    private final SyncEntitlementService entitlement;
    public ProgressController(JdbcTemplate jdbc,ObjectMapper mapper,SyncEntitlementService entitlement){this.jdbc=jdbc;this.mapper=mapper;this.entitlement=entitlement;}
    private long id(Jwt jwt){return Long.parseLong(jwt.getSubject());}
    @GetMapping Map<String,Object> get(@AuthenticationPrincipal Jwt jwt) {
        // Keep legacy backups readable after a subscription expires.
        var rows=jdbc.query("SELECT revision,schema_version,payload,updated_at FROM user_progress_snapshot WHERE user_id=?",(rs,n)->Map.<String,Object>of(
            "revision",rs.getLong(1),"schemaVersion",rs.getInt(2),"payload",parse(rs.getString(3)),
            "updatedAt",rs.getTimestamp(4).toInstant().toString()),id(jwt));
        if(rows.isEmpty())throw new ResponseStatusException(HttpStatus.NOT_FOUND,"尚未上传云端进度");
        return rows.get(0);
    }
    private JsonNode parse(String text) {try{return mapper.readTree(text);}catch(Exception e){throw new IllegalStateException("进度数据损坏");}}
    @PutMapping Map<String,Long> save(@AuthenticationPrincipal Jwt jwt,@RequestBody Save r) {
        entitlement.require(id(jwt));
        // Legacy snapshots are retained for migration only, never for new sensitive data.
        if (r.payload()!=null && r.payload().path("tables").isObject()) {
            var tables = r.payload().path("tables");
            if (tables.path("wellbeing_entries").size()>0 || tables.path("wellbeing_moods").size()>0) {
                throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "敏感记录必须走加密同步，不允许上传明文整库快照");
            }
        }
        if(r.schemaVersion()!=1 || r.expectedRevision()<0 || r.payload()==null || !r.payload().isObject()
            || !"planblindbox-local-backup".equals(r.payload().path("format").asText())
            || r.payload().path("formatVersion").asInt()!=1 || !r.payload().path("tables").isObject())
            throw new BadRequest("快照格式或版本无效");
        String json=r.payload().toString();
        if(json.getBytes(StandardCharsets.UTF_8).length>5*1024*1024)
            throw new ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE,"快照不能超过5MiB");
        long uid=id(jwt);
        if (r.payload().path("backupUserId").asLong(Long.MIN_VALUE) != -1000000L-uid) {
            throw new BadRequest("备份账号标识与当前登录用户不一致");
        }
        if(r.expectedRevision()==0) {
            try {
                jdbc.update("INSERT INTO user_progress_snapshot(user_id,revision,schema_version,payload) VALUES(?,1,?,?)",uid,r.schemaVersion(),json);
                return Map.of("revision",1L);
            } catch(DuplicateKeyException ex) {throw new ResponseStatusException(HttpStatus.CONFLICT,"云端已存在快照，请先读取");}
        }
        int updated=jdbc.update("UPDATE user_progress_snapshot SET payload=?,schema_version=?,revision=revision+1 WHERE user_id=? AND revision=?",
            json,r.schemaVersion(),uid,r.expectedRevision());
        if(updated!=1)throw new ResponseStatusException(HttpStatus.CONFLICT,"云端进度已变化，请重新读取后再确认");
        return Map.of("revision",r.expectedRevision()+1);
    }
}
