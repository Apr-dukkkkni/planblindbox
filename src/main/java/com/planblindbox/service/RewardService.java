package com.planblindbox.service;

import com.planblindbox.dto.response.HabitRewardResponse;
import com.planblindbox.dto.response.TaskRewardResponse;
import com.planblindbox.entity.AssetRecord;
import com.planblindbox.entity.RewardConfig;
import com.planblindbox.entity.UserAsset;
import com.planblindbox.mapper.AssetRecordMapper;
import com.planblindbox.mapper.RewardConfigMapper;
import com.planblindbox.mapper.UserAssetMapper;
import com.planblindbox.util.RewardCalculator;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/** 两种奖励都加入调用方事务，不单独提交资产。 */
@Service
@RequiredArgsConstructor
public class RewardService {
    public static final String TASK_COMPLETE = "TASK_COMPLETE";
    public static final String HABIT_CHECK_IN = "HABIT_CHECK_IN";

    private final RewardConfigMapper rewardConfigMapper;
    private final UserAssetMapper userAssetMapper;
    private final AssetRecordMapper assetRecordMapper;

    @Transactional(propagation = Propagation.MANDATORY)
    public TaskRewardResponse rewardTaskCompletion(
            Long userId,
            Long taskId,
            Integer importance,
            Integer difficulty
    ) {
        RewardConfig config = rewardConfigMapper.selectByType(TASK_COMPLETE);

        if (config == null) {
            throw new IllegalStateException(
                    "缺少 " + TASK_COMPLETE + " 奖励配置，请先执行对应 Step SQL");
        }

        if (Boolean.FALSE.equals(config.getEnabled())) {
            return emptyReward();
        }

        if (!Boolean.TRUE.equals(config.getEnabled())
                || config.getCoin() == null
                || config.getExp() == null
                || config.getWater() == null
                || config.getCoin() < 0
                || config.getExp() < 0
                || config.getWater() < 0) {
            throw new IllegalStateException(TASK_COMPLETE + " 奖励配置不合法");
        }

        RewardCalculator.TaskRewardAmounts amounts =
                RewardCalculator.calculateTaskCompletion(
                        importance, difficulty);

        int coin = amounts.coin();
        long exp = amounts.exp();

        // 水滴不再作为任务完成奖励
        return grantAmounts(
                userId, TASK_COMPLETE, "TASK", taskId,
                coin, exp, 0
        );
    }


    private int validateLevel(Integer level, String field) {
        int value = level == null ? 3 : level;

        if (value < 1 || value > 5) {
            throw new IllegalStateException(field + "必须在 1～5 之间");
        }

        return value;
    }

    private int coinForLevel(int level) {
        return switch (level) {
            case 1 -> 1;
            case 2 -> 2;
            case 3 -> 4;
            case 4 -> 8;
            case 5 -> 16;
            default -> throw new IllegalArgumentException("等级必须为 1～5");
        };
    }

    private long expForLevel(int level) {
        return switch (level) {
            case 1 -> 10;
            case 2 -> 20;
            case 3 -> 40;
            case 4 -> 80;
            case 5 -> 160;
            default -> throw new IllegalArgumentException("等级必须为 1～5");
        };
    }


    private TaskRewardResponse grantAmounts(
            Long userId,
            String type,
            String source,
            Long sourceId,
            int coin,
            long exp,
            int water
    ) {
        if (coin == 0 && exp == 0 && water == 0) {
            return emptyReward();
        }

        if (userAssetMapper.addAssets(userId, coin, exp, water) < 1) {
            throw new IllegalStateException(type + " 奖励资产入账失败");
        }

        recordIfPositive(userId, type, source, sourceId, "COIN", coin);
        recordIfPositive(userId, type, source, sourceId, "EXP", exp);
        recordIfPositive(userId, type, source, sourceId, "WATER", water);

        UserAsset balance = userAssetMapper.selectByUserId(userId);
        if (balance == null) {
            throw new IllegalStateException(type + " 奖励资产查询失败");
        }

        TaskRewardResponse result = new TaskRewardResponse();
        result.setGranted(true);
        result.setCoin(coin);
        result.setExp(exp);
        result.setWater(water);
        result.setCoinBalance(balance.getCoin());
        result.setExpBalance(balance.getExp());
        result.setWaterBalance(balance.getWater());

        return result;
    }

    @Transactional(propagation = Propagation.MANDATORY)
    public HabitRewardResponse rewardHabitCheckIn(Long userId, Long habitRecordId) {
        TaskRewardResponse granted = grant(userId, HABIT_CHECK_IN, "HABIT_RECORD", habitRecordId);
        HabitRewardResponse result = new HabitRewardResponse();
        result.setGranted(granted.getGranted());
        result.setCoin(granted.getCoin());
        result.setExp(granted.getExp());
        result.setWater(granted.getWater());
        result.setCoinBalance(granted.getCoinBalance());
        result.setExpBalance(granted.getExpBalance());
        result.setWaterBalance(granted.getWaterBalance());
        return result;
    }

    private TaskRewardResponse grant(Long userId, String type, String source, Long sourceId) {
        RewardConfig config = rewardConfigMapper.selectByType(type);
        if (config == null) {
            // 如果缺配置，回滚打卡/任务完成，不能悄悄丢奖励。
            throw new IllegalStateException("缺少 " + type + " 奖励配置，请先执行对应 Step SQL");
        }
        if (Boolean.FALSE.equals(config.getEnabled())) return emptyReward();
        if (!Boolean.TRUE.equals(config.getEnabled())
                || config.getCoin() == null || config.getExp() == null || config.getWater() == null
                || config.getCoin() < 0 || config.getExp() < 0 || config.getWater() < 0) {
            throw new IllegalStateException(type + " 奖励配置不合法");
        }

        int coin = config.getCoin();
        long exp = config.getExp();

// 水滴只通过每日签到发放，习惯打卡不再奖励水滴。
        int water = 0;

        return grantAmounts(
                userId, type, source, sourceId, coin, exp, water
        );
    }

    private void recordIfPositive(Long userId, String action, String source, Long sourceId,
                                  String assetType, long amount) {
        if (amount <= 0) return;
        AssetRecord record = new AssetRecord();
        record.setUserId(userId);
        record.setAction(action);
        record.setAssetType(assetType);
        record.setAmount(amount);
        record.setSource(source);
        record.setSourceId(sourceId);
        if (assetRecordMapper.insert(record) != 1) {
            throw new IllegalStateException(action + " 奖励流水写入失败: " + assetType);
        }
    }

    private TaskRewardResponse emptyReward() {
        TaskRewardResponse result = new TaskRewardResponse();
        result.setGranted(false);
        result.setCoin(0);
        result.setExp(0L);
        result.setWater(0);
        return result;
    }
}
