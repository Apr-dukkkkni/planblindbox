package com.planblindbox.mod.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.server.ResponseStatusException;

@Service
public class PasswordResetService {
    public record ChallengeResult(String challengeId,String message) {}
    private enum ResetOutcome {SUCCESS,INVALID,LOCKED}
    private record SendState(boolean shouldSend,String challengeId) {}
    private final byte[] key;
    private final JdbcTemplate jdbc;
    private final UserRepository users;
    private final TransactionTemplate tx;
    private final PasswordEncoder encoder;
    private final PasswordMailService mail;
    private final SecureRandom random=new SecureRandom();
    public PasswordResetService(JdbcTemplate jdbc,UserRepository users,
            org.springframework.transaction.PlatformTransactionManager manager,
            PasswordEncoder encoder,PasswordMailService mail,
            @Value("${auth.reset.hmac-secret-base64:}") String raw) {
        this.jdbc=jdbc;this.users=users;this.encoder=encoder;this.mail=mail;
        this.tx=new TransactionTemplate(manager);
        try {
            key=Base64.getDecoder().decode(raw);
            if(key.length<32)throw new IllegalArgumentException("too short");
        } catch(IllegalArgumentException e) {throw new IllegalStateException("请配置 PASSWORD_RESET_HMAC_SECRET_BASE64（至少32随机字节，独立于JWT）",e);}
    }
    private String mac(String value){
        try {
            Mac h=Mac.getInstance("HmacSHA256");h.init(new SecretKeySpec(key,"HmacSHA256"));
            return HexFormat.of().formatHex(h.doFinal(value.getBytes(StandardCharsets.UTF_8)));
        } catch(Exception e){throw new IllegalStateException("HMAC不可用",e);}
    }
    private String rateKey(String label,String value){return mac(label+":"+value);}
    private boolean hit(String label,String value,long seconds,int max){
        long bucket=(Instant.now().getEpochSecond()/seconds)*seconds;
        String k=rateKey(label,value);
        jdbc.update("INSERT INTO password_reset_rate(rate_key,bucket_start,hits) VALUES(?,?,1) ON DUPLICATE KEY UPDATE hits=hits+1",k,bucket);
        int current=jdbc.queryForObject("SELECT hits FROM password_reset_rate WHERE rate_key=? AND bucket_start=?",Integer.class,k,bucket);
        return current<=max;
    }
    private boolean cooldown(String email){
        String k=rateKey("emailCooldown",email);
        jdbc.update("INSERT IGNORE INTO password_reset_cooldown(rate_key,next_allowed_at) VALUES(?,DATE_SUB(NOW(),INTERVAL 1 SECOND))",k);
        return jdbc.update("UPDATE password_reset_cooldown SET next_allowed_at=DATE_ADD(NOW(),INTERVAL 60 SECOND) WHERE rate_key=? AND next_allowed_at<=NOW()",k)==1;
    }
    public ChallengeResult forgot(String rawEmail,String ip){
        String email=PasswordRules.email(rawEmail);
        if(!mail.configured())throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"邮件服务尚未配置，请联系维护者");
        // Response shape is identical for unknown email and rate-limited requests.
        String fake=UUID.randomUUID().toString();
        final String[] codeHolder=new String[1];
        SendState result=tx.execute(status->{
            boolean okay=cooldown(email)
                & hit("emailHour",email,3600,5)
                & hit("ipHour",ip==null?"unknown":ip,3600,30);
            if(!okay)return new SendState(false,fake);
            UserRepository.User u=users.lockEmail(email);
            if(u==null || !"ACTIVE".equals(u.status()))return new SendState(false,fake);
            String challenge=UUID.randomUUID().toString();
            String code=String.format(java.util.Locale.ROOT,"%06d",random.nextInt(1000000));
            jdbc.update("UPDATE password_reset_challenge SET consumed_at=CURRENT_TIMESTAMP WHERE user_id=? AND consumed_at IS NULL",u.id());
            jdbc.update("INSERT INTO password_reset_challenge(challenge_id,user_id,code_mac,expires_at) VALUES(?,?,?,DATE_ADD(NOW(), INTERVAL 10 MINUTE))",
                challenge,u.id(),mac(challenge+":"+code));
            codeHolder[0]=code;
            return new SendState(true,challenge);
        });
        if(result!=null && result.shouldSend())mail.sendCode(email,codeHolder[0]);
        return new ChallengeResult(result==null?fake:result.challengeId(),"如果邮箱已注册，验证码将发送至该邮箱");
    }
    public void reset(String rawEmail,String challenge,String code,String rawPassword){
        String email=PasswordRules.email(rawEmail);
        PasswordRules.password(rawPassword);
        if(challenge==null || !challenge.matches("[0-9a-f-]{36}") || code==null || !code.matches("[0-9]{6}"))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"验证码无效或已过期");
        // Hash outside DB transaction so BCrypt does not hold row locks.
        String hash=encoder.encode(rawPassword);
        ResetOutcome outcome=tx.execute(status->{
            UserRepository.User u=users.lockEmail(email);
            if(u==null)return ResetOutcome.INVALID;
            jdbc.update("INSERT IGNORE INTO password_reset_budget(user_id,attempts,window_start) VALUES(?,0,CURRENT_TIMESTAMP)",u.id());
            var budget=jdbc.queryForMap("SELECT attempts,window_start FROM password_reset_budget WHERE user_id=? FOR UPDATE",u.id());
            int attempts=((Number)budget.get("attempts")).intValue();
            java.sql.Timestamp since=(java.sql.Timestamp)budget.get("window_start");
            if(since.toInstant().isBefore(Instant.now().minusSeconds(3600))){
                jdbc.update("UPDATE password_reset_budget SET attempts=0,window_start=CURRENT_TIMESTAMP WHERE user_id=?",u.id());
                attempts=0;
            }
            if(attempts>=5)return ResetOutcome.LOCKED;
            var rows=jdbc.query("SELECT code_mac,attempts,expires_at,consumed_at FROM password_reset_challenge WHERE user_id=? AND challenge_id=? FOR UPDATE",
                (rs,n)->new Object[]{rs.getString(1),rs.getInt(2),rs.getTimestamp(3),rs.getTimestamp(4)},u.id(),challenge);
            if(rows.isEmpty()){
                jdbc.update("UPDATE password_reset_budget SET attempts=attempts+1 WHERE user_id=?",u.id());
                return ResetOutcome.INVALID;
            }
            Object[] row=rows.get(0);
            boolean valid=row[3]==null && ((Integer)row[1])<5 && ((java.sql.Timestamp)row[2]).toInstant().isAfter(Instant.now())
                && MessageDigest.isEqual(((String)row[0]).getBytes(StandardCharsets.US_ASCII),mac(challenge+":"+code).getBytes(StandardCharsets.US_ASCII));
            if(!valid){
                jdbc.update("UPDATE password_reset_challenge SET attempts=attempts+1 WHERE challenge_id=?",challenge);
                jdbc.update("UPDATE password_reset_budget SET attempts=attempts+1 WHERE user_id=?",u.id());
                return ResetOutcome.INVALID;
            }
            users.passwordAndRevoke(u.id(),hash);
            jdbc.update("UPDATE password_reset_challenge SET consumed_at=CURRENT_TIMESTAMP WHERE user_id=? AND consumed_at IS NULL",u.id());
            jdbc.update("UPDATE password_reset_budget SET attempts=0,window_start=CURRENT_TIMESTAMP WHERE user_id=?",u.id());
            return ResetOutcome.SUCCESS;
        });
        if(outcome==ResetOutcome.SUCCESS){mail.changed(email);return;}
        if(outcome==ResetOutcome.LOCKED)throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,"尝试次数过多，请一小时后再试");
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"验证码无效或已过期");
    }
}
