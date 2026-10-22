package com.planblindbox.service;

import com.planblindbox.dto.response.TaskRewardResponse;
import com.planblindbox.entity.AssetRecord;
import com.planblindbox.entity.RewardConfig;
import com.planblindbox.entity.UserAsset;
import com.planblindbox.mapper.AssetRecordMapper;
import com.planblindbox.mapper.RewardConfigMapper;
import com.planblindbox.mapper.UserAssetMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 奖励结算只允许在外部事务内调用。
 * TaskServiceImpl.complete 已持有 task FOR UPDATE 行锁，保证同一任务不会重复结算。
 */
@Service
@RequiredArgsConstructor
public class RewardService {
    public static final String TASK_COMPLETE = "TASK_COMPLETE";

    private final RewardConfigMapper rewardConfigMapper;
    private final UserAssetMapper userAssetMapper;
    private final AssetRecordMapper assetRecordMapper;

    @Transactional(propagation = Propagation.MANDATORY)
    public TaskRewardResponse rewardTaskCompletion(Long userId, Long taskId) {
        RewardConfig config = rewardConfigMapper.selectByType(TASK_COMPLETE);
        if (config == null) {
            // 不允许没有配置时悄悄完成任务却丢失本该发放的奖励。
            throw new IllegalStateException("缺少 TASK_COMPLETE 奖励配置，请先执行 Step3 SQL");
        }
        if (Boolean.FALSE.equals(config.getEnabled())) {
            return emptyReward();
        }
        if (!Boolean.TRUE.equals(config.getEnabled())
                || config.getCoin() == null || config.getExp() == null || config.getWater() == null
                || config.getCoin() < 0 || config.getExp() < 0 || config.getWater() < 0) {
            throw new IllegalStateException("TASK_COMPLETE 奖励配置不合法");
        }

        int coin = config.getCoin();
        long exp = config.getExp();
        int water = config.getWater();
        if (coin == 0 && exp == 0 && water == 0) {
            return emptyReward();
        }

        int changed = userAssetMapper.addAssets(userId, coin, exp, water);
        // MySQL 更新行和插入行的返回值可能是 1 / 2；只要有影响就是成功。
        if (changed < 1) {
            throw new IllegalStateException("任务奖励资产入账失败");
        }
        recordIfPositive(userId, taskId, "COIN", coin);
        recordIfPositive(userId, taskId, "EXP", exp);
        recordIfPositive(userId, taskId, "WATER", water);

        UserAsset balance = userAssetMapper.selectByUserId(userId);
        if (balance == null) {
            throw new IllegalStateException("任务奖励资产查询失败");
        }
        TaskRewardResponse response = new TaskRewardResponse();
        response.setGranted(true);
        response.setCoin(coin);
        response.setExp(exp);
        response.setWater(water);
        response.setCoinBalance(balance.getCoin());
        response.setExpBalance(balance.getExp());
        response.setWaterBalance(balance.getWater());
        return response;
    }

    private void recordIfPositive(Long userId, Long taskId, String assetType, long amount) {
        if (amount <= 0) {
            return;
        }
        AssetRecord record = new AssetRecord();
        record.setUserId(userId);
        record.setAction(TASK_COMPLETE);
        record.setAssetType(assetType);
        record.setAmount(amount);
        record.setSource("TASK");
        record.setSourceId(taskId);
        if (assetRecordMapper.insert(record) != 1) {
            throw new IllegalStateException("任务奖励流水写入失败：" + assetType);
        }
    }

    private TaskRewardResponse emptyReward() {
        TaskRewardResponse response = new TaskRewardResponse();
        response.setGranted(false);
        response.setCoin(0);
        response.setExp(0L);
        response.setWater(0);
        return response;
    }
}
