package com.planblindbox.mod.water;

import java.sql.Date;
import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 服务器水滴的唯一写入口；身份来自已经验证的 JWT subject，绝不接受客户端余额。 */
@Service
public class WaterService {
    public record Status(long waterBalance, int streakDay, int longestStreakDay,
                         int totalSignInDays, String businessDate) {}
    public record Claim(boolean granted, long waterBalance, int streakDay,
                        int longestStreakDay, int totalSignInDays, int totalWater,
                        String businessDate) {}
    public record CheckIn(String businessDate,int streakDay,int totalWater) {}
    public record Transaction(long ledgerId, long delta, long balanceAfter,
                              String sourceType, String occurredAt) {}

    private final JdbcTemplate jdbc;
    private final Clock clock;
    public WaterService(JdbcTemplate jdbc,
            @Value("${plan.water.zone-id:Asia/Shanghai}") String zone) {
        this.jdbc = jdbc;
        this.clock = Clock.system(ZoneId.of(zone));
    }

    private LocalDate businessDate() {
        return WaterRewardPolicy.businessDate(clock);
    }

    private void ensureWallet(long userId) {
        // 并发首次登录不会插入两条钱包；事务行锁保证奖励串行。
        jdbc.update("INSERT INTO user_water_wallet(user_id) VALUES (?) ON DUPLICATE KEY UPDATE user_id=user_id",userId);
    }

    private Wallet lockWallet(long userId) {
        return jdbc.queryForObject("SELECT balance,current_streak,longest_streak,total_check_in_days,last_sign_in_date " +
                "FROM user_water_wallet WHERE user_id=? FOR UPDATE", (rs,n) -> new Wallet(
            rs.getLong(1),rs.getInt(2),rs.getInt(3),rs.getInt(4),
            rs.getDate(5)==null ? null : rs.getDate(5).toLocalDate()),userId);
    }
    private record Wallet(long balance,int streak,int longest,int total,LocalDate lastDate) {}

    @Transactional(readOnly=true)
    public Status status(long userId) {
        LocalDate today=businessDate();
        List<Wallet> rows=jdbc.query("SELECT balance,current_streak,longest_streak,total_check_in_days,last_sign_in_date " +
                "FROM user_water_wallet WHERE user_id=?", (rs,n) -> new Wallet(
                rs.getLong(1),rs.getInt(2),rs.getInt(3),rs.getInt(4),
                rs.getDate(5)==null?null:rs.getDate(5).toLocalDate()), userId);
        if(rows.isEmpty()) return new Status(0,0,0,0,today.toString());
        Wallet w=rows.get(0);
        int active=w.lastDate()!=null && (w.lastDate().equals(today) || w.lastDate().equals(today.minusDays(1)))
                ? w.streak() : 0;
        return new Status(w.balance(),active,w.longest(),w.total(),today.toString());
    }

    @Transactional
    public Claim claim(long userId) {
        ensureWallet(userId);
        Wallet w=lockWallet(userId);
        LocalDate today=businessDate();
        if(today.equals(w.lastDate())) {
            Integer amount=jdbc.queryForObject("SELECT water_awarded FROM user_water_checkin WHERE user_id=? AND business_date=?",
                    Integer.class,userId,Date.valueOf(today));
            return new Claim(false,w.balance(),w.streak(),w.longest(),w.total(),amount,today.toString());
        }
        int streak = today.minusDays(1).equals(w.lastDate()) ? w.streak()+1 : 1;
        int reward = WaterRewardPolicy.reward(streak);
        long newBalance=Math.addExact(w.balance(),reward);
        jdbc.update("INSERT INTO user_water_checkin(user_id,business_date,streak_day,water_awarded) VALUES (?,?,?,?)",
                    userId,Date.valueOf(today),streak,reward);
        long checkinId=jdbc.queryForObject("SELECT checkin_id FROM user_water_checkin WHERE user_id=? AND business_date=?",
                    Long.class,userId,Date.valueOf(today));
        jdbc.update("UPDATE user_water_wallet SET balance=?,current_streak=?,longest_streak=?,total_check_in_days=?,last_sign_in_date=? WHERE user_id=?",
                newBalance,streak,Math.max(w.longest(),streak),w.total()+1,Date.valueOf(today),userId);
        jdbc.update("INSERT INTO user_water_ledger(user_id,change_amount,balance_after,source_type,source_id) VALUES (?,?,?,?,?)",
                    userId,reward,newBalance,"DAILY_CHECKIN",checkinId);
        return new Claim(true,newBalance,streak,Math.max(w.longest(),streak),w.total()+1,reward,today.toString());
    }

    @Transactional(readOnly=true)
    public List<Transaction> transactions(long userId, int limit) {
        int safeLimit=Math.max(1,Math.min(limit,100));
        return jdbc.query("SELECT ledger_id,change_amount,balance_after,source_type,created_at " +
            "FROM user_water_ledger WHERE user_id=? ORDER BY ledger_id DESC LIMIT ?",
            (rs,n) -> new Transaction(rs.getLong(1),rs.getLong(2),rs.getLong(3),
                        rs.getString(4),rs.getTimestamp(5).toInstant().toString()),userId,safeLimit);
    }

    @Transactional(readOnly=true)
    public List<CheckIn> month(long userId,int year,int month) {
        LocalDate first=LocalDate.of(year,month,1);
        LocalDate next=first.plusMonths(1);
        return jdbc.query("SELECT business_date,streak_day,water_awarded FROM user_water_checkin " +
            "WHERE user_id=? AND business_date>=? AND business_date<? ORDER BY business_date",
            (rs,n) -> new CheckIn(rs.getDate(1).toLocalDate().toString(),rs.getInt(2),rs.getInt(3)),
            userId,Date.valueOf(first),Date.valueOf(next));
    }
}
