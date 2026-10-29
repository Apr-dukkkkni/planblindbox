package com.planblindbox.service.impl;

import com.planblindbox.dto.response.DailySignInResponse;
import com.planblindbox.entity.AssetRecord;
import com.planblindbox.entity.DailySignIn;
import com.planblindbox.entity.UserAsset;
import com.planblindbox.mapper.AssetRecordMapper;
import com.planblindbox.mapper.DailySignInMapper;
import com.planblindbox.mapper.UserAssetMapper;
import com.planblindbox.service.DailySignInService;
import com.planblindbox.util.BusinessTime;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalDateTime;
import com.planblindbox.util.DailySignInRewardCalculator;
import com.planblindbox.dto.response.DailySignInRecordResponse;

import java.time.YearMonth;
import java.util.List;

@Service
@RequiredArgsConstructor
public class DailySignInServiceImpl implements DailySignInService {


    private static final String ACTION = "DAILY_SIGN_IN";

    private final DailySignInMapper dailySignInMapper;
    private final UserAssetMapper userAssetMapper;
    private final AssetRecordMapper assetRecordMapper;
    private final Clock clock;

    @Override
    @Transactional
    public DailySignInResponse signIn(Long userId) {

        // 使用现有的 05:00 业务日规则
        LocalDate businessDate =
                BusinessTime.businessDate(LocalDateTime.now(clock));

        // 已经签到：不再发放奖励
        DailySignIn existing =
                dailySignInMapper.selectByBusinessDate(
                        userId, businessDate);

        if (existing != null) {
            return toResponse(existing, false, getWaterBalance(userId));
        }

        // 每月 1 日重新开始计算连续签到天数；
        // 其他日期必须在前一个业务日签到，连续天数才递增。
        int streakDay = 1;

        if (businessDate.getDayOfMonth() != 1) {
            DailySignIn previous =
                    dailySignInMapper.selectByBusinessDate(
                            userId, businessDate.minusDays(1));

            if (previous != null && previous.getStreakDay() != null) {
                streakDay = previous.getStreakDay() + 1;
            }
        }

        DailySignInRewardCalculator.SignInReward reward =
                DailySignInRewardCalculator.calculate(streakDay);

        int bonusWater = reward.bonusWater();
        int totalWater = reward.totalWater();

        DailySignIn signIn = new DailySignIn();
        signIn.setUserId(userId);
        signIn.setBusinessDate(businessDate);
        signIn.setStreakDay(streakDay);
        signIn.setBaseWater(reward.baseWater());
        signIn.setBonusWater(bonusWater);
        signIn.setTotalWater(totalWater);

        // 数据库唯一索引是并发防重的最终保障。
        if (dailySignInMapper.insertIfAbsent(signIn) != 1) {

            DailySignIn duplicate =
                    dailySignInMapper.selectByBusinessDateForUpdate(
                            userId, businessDate);

            if (duplicate == null) {
                throw new IllegalStateException("签到记录写入后无法查询");
            }

            return toResponse(
                    duplicate, false, getWaterBalance(userId));
        }

        // 更新资产余额
        if (userAssetMapper.addAssets(
                userId, 0, 0L, totalWater) < 1) {
            throw new IllegalStateException("签到水滴入账失败");
        }

        // 写入水滴流水
        AssetRecord record = new AssetRecord();
        record.setUserId(userId);
        record.setAction(ACTION);
        record.setAssetType("WATER");
        record.setAmount((long) totalWater);
        record.setSource(ACTION);
        record.setSourceId(signIn.getSignInId());

        if (assetRecordMapper.insert(record) != 1) {
            throw new IllegalStateException("签到水滴流水写入失败");
        }

        // 查询发奖后的余额
        UserAsset balance = userAssetMapper.selectByUserId(userId);

        if (balance == null) {
            throw new IllegalStateException("签到后无法查询用户资产");
        }

        return toResponse(
                signIn,
                true,
                balance.getWater() == null ? 0 : balance.getWater()
        );
    }

    private int getWaterBalance(Long userId) {
        UserAsset balance = userAssetMapper.selectByUserId(userId);

        return balance == null || balance.getWater() == null
                ? 0 : balance.getWater();
    }

    @Override
    @Transactional(readOnly = true)
    public List<DailySignInRecordResponse> getMonthlyRecords(
            Long userId, int year, int month) {

        if (userId == null || userId <= 0) {
            throw new IllegalArgumentException("用户 ID 不合法");
        }

        YearMonth yearMonth = YearMonth.of(year, month);

        LocalDate startDate = yearMonth.atDay(1);
        LocalDate endDateExclusive =
                yearMonth.plusMonths(1).atDay(1);

        return dailySignInMapper.selectByDateRange(
                        userId, startDate, endDateExclusive)
                .stream()
                .map(this::toRecordResponse)
                .toList();
    }

    private DailySignInRecordResponse toRecordResponse(
            DailySignIn signIn) {

        DailySignInRecordResponse response =
                new DailySignInRecordResponse();

        response.setBusinessDate(signIn.getBusinessDate());
        response.setStreakDay(signIn.getStreakDay());
        response.setBaseWater(signIn.getBaseWater());
        response.setBonusWater(signIn.getBonusWater());
        response.setTotalWater(signIn.getTotalWater());

        return response;
    }

    private DailySignInResponse toResponse(
            DailySignIn signIn,
            boolean granted,
            int waterBalance
    ) {
        DailySignInResponse response = new DailySignInResponse();
        response.setGranted(granted);
        response.setBusinessDate(signIn.getBusinessDate());
        response.setStreakDay(signIn.getStreakDay());
        response.setBaseWater(signIn.getBaseWater());
        response.setBonusWater(signIn.getBonusWater());
        response.setTotalWater(signIn.getTotalWater());
        response.setWaterBalance(waterBalance);
        return response;
    }
}