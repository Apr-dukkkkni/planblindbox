package com.planblindbox.service;

import com.planblindbox.dto.response.ShopBalanceResponse;
import com.planblindbox.dto.response.ShopBoxResponse;
import com.planblindbox.dto.response.ShopOpenResponse;
import com.planblindbox.entity.AssetRecord;
import com.planblindbox.entity.ShopBox;
import com.planblindbox.entity.ShopOpenRecord;
import com.planblindbox.entity.ShopReward;
import com.planblindbox.entity.UserAsset;
import com.planblindbox.mapper.AppUserMapper;
import com.planblindbox.mapper.AssetRecordMapper;
import com.planblindbox.mapper.CollectibleMapper;
import com.planblindbox.mapper.ShopMapper;
import com.planblindbox.mapper.UserAssetMapper;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/** 商店：扣款、数值奖励/收藏品发放、流水及开盒记录在同一个事务中完成。 */
@Service
@RequiredArgsConstructor
public class ShopService {

    private final ShopMapper shopMapper;
    private final AppUserMapper appUserMapper;
    private final UserAssetMapper userAssetMapper;
    private final AssetRecordMapper assetRecordMapper;
    private final CollectibleMapper collectibleMapper;

    @Transactional(readOnly = true)
    public List<ShopBoxResponse> boxes() {
        return shopMapper.selectEnabledBoxes().stream()
                .map(box -> new ShopBoxResponse(box.getBoxId(), box.getName(),
                        box.getDescription(), box.getPriceCoin()))
                .toList();
    }

    @Transactional(readOnly = true)
    public ShopBalanceResponse balance(Long userId) {
        requireUser(userId);
        UserAsset assets = userAssetMapper.selectByUserId(userId);
        if (assets == null) return new ShopBalanceResponse(0, 0, 0);
        return new ShopBalanceResponse(assets.getCoin(), assets.getExp(), assets.getWater());
    }

    @Transactional(readOnly = true)
    public List<ShopOpenResponse> history(Long userId, int limit) {
        requireUser(userId);
        if (limit < 1 || limit > 100) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "limit 必须在 1~100 之间");
        }
        return shopMapper.selectRecentOpens(userId, limit).stream()
                .map(this::toResponse).toList();
    }

    @Transactional
    public ShopOpenResponse open(Long userId, Long boxId, String requestId) {
        requireUser(userId);
        if (boxId == null || boxId <= 0 || requestId == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "boxId/requestId 不合法");
        }
        final String normalized;
        try {
            normalized = UUID.fromString(requestId).toString();
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "requestId 必须是 UUID");
        }
        if (!normalized.equalsIgnoreCase(requestId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "requestId 必须是标准 UUID 格式");
        }

        // 同一 requestId 重试时返回第一次的结果，不重复扣款或发奖。
        ShopOpenRecord existing = shopMapper.selectByRequestId(userId, normalized);
        if (existing != null) {
            if (!boxId.equals(existing.getBoxId())) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                        "同一 requestId 不能用于不同商品");
            }
            return toResponse(existing);
        }

        ShopBox box = shopMapper.selectEnabledBox(boxId);
        if (box == null || !Boolean.TRUE.equals(box.getEnabled())) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "盲盒不存在或已下架");
        }
        Integer price = box.getPriceCoin();
        if (price == null || price <= 0) {
            throw new IllegalStateException("盲盒价格配置异常");
        }

        ShopReward reward = pickReward(shopMapper.selectActiveRewards(boxId));

        // 先写入幂等开盒记录。后续任何一步失败，事务会一起回滚。
        ShopOpenRecord record = new ShopOpenRecord();
        record.setUserId(userId);
        record.setBoxId(boxId);
        record.setBoxName(box.getName());
        record.setRequestId(normalized);
        record.setRewardId(reward.getRewardId());
        record.setCollectibleItemId("COLLECTIBLE".equals(reward.getAssetType())
                ? reward.getItemId() : null);
        record.setItemName(reward.getItemName());
        record.setItemRarity(reward.getItemRarity());
        record.setItemImagePath(reward.getItemImagePath());
        record.setItemDescription(reward.getItemDescription());
        record.setPriceCoin(price);
        record.setRewardType(reward.getAssetType());
        record.setRewardAmount(reward.getAmount());
        try {
            if (shopMapper.insertOpen(record) != 1 || record.getOpenId() == null) {
                throw new IllegalStateException("创建开盒记录失败");
            }
        } catch (DuplicateKeyException exception) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "本次开盒请求已被处理，请刷新开盒记录", exception);
        }

        if (shopMapper.deductCoins(userId, price) != 1) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "金币不足，无法开盒");
        }
        addLedger(userId, "SHOP_OPEN_COST", "COIN", -price.longValue(), record.getOpenId());

        switch (reward.getAssetType()) {
            case "COIN" -> grantAssetReward(userId, reward, record.getOpenId(),
                    Math.toIntExact(reward.getAmount()), 0L, 0);
            case "EXP" -> grantAssetReward(userId, reward, record.getOpenId(),
                    0, reward.getAmount(), 0);
            case "COLLECTIBLE" -> grantCollectible(userId, reward, record.getOpenId());
            default -> throw new IllegalStateException("奖励类型配置异常");
        }

        UserAsset balance = userAssetMapper.selectByUserId(userId);
        if (balance == null || balance.getCoin() == null || balance.getExp() == null
                || balance.getWater() == null) {
            throw new IllegalStateException("开盒后读取余额失败");
        }
        record.setCoinBalanceAfter(balance.getCoin());
        record.setExpBalanceAfter(balance.getExp());
        record.setWaterBalanceAfter(balance.getWater());
        if (shopMapper.completeOpen(record) != 1) {
            throw new IllegalStateException("开盒结果持久化失败");
        }
        return toResponse(record);
    }

    private void grantAssetReward(Long userId, ShopReward reward, Long openId,
                                  int coin, long exp, int water) {
        if (userAssetMapper.addAssets(userId, coin, exp, water) < 1) {
            throw new IllegalStateException("开盒奖励入账失败");
        }
        addLedger(userId, "SHOP_OPEN_REWARD", reward.getAssetType(),
                reward.getAmount(), openId);
    }

    private void grantCollectible(Long userId, ShopReward reward, Long openId) {
        int quantity = Math.toIntExact(reward.getAmount());
        if (collectibleMapper.addToInventory(userId, reward.getItemId(), quantity) < 1) {
            throw new IllegalStateException("收藏品库存更新失败");
        }
        if (collectibleMapper.insertAcquisitionRecord(
                userId, reward.getItemId(), quantity, "SHOP_BOX", openId) != 1) {
            throw new IllegalStateException("收藏品获取流水写入失败");
        }
    }

    private ShopReward pickReward(List<ShopReward> rewards) {
        if (rewards == null || rewards.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "盲盒尚未配置可用奖励");
        }
        long weightSum = 0;
        for (ShopReward reward : rewards) {
            if (reward.getRewardId() == null || reward.getAmount() == null
                    || reward.getAmount() <= 0 || reward.getWeight() == null
                    || reward.getWeight() <= 0) {
                throw new IllegalStateException("商店奖励池配置异常");
            }
            switch (reward.getAssetType() == null ? "" : reward.getAssetType()) {
                case "COIN"-> {
                    if (reward.getItemId() != null || reward.getAmount() > Integer.MAX_VALUE) {
                        throw new IllegalStateException("COIN奖励配置异常");
                    }
                }
                case "WATER" -> throw new IllegalStateException(
                        "商店奖励不允许配置水滴，水滴仅通过每日签到发放");
                case "EXP" -> {
                    if (reward.getItemId() != null) {
                        throw new IllegalStateException("EXP 奖励不能关联收藏品");
                    }
                }
                case "COLLECTIBLE" -> {
                    if (reward.getItemId() == null
                            || !Boolean.TRUE.equals(reward.getItemEnabled())
                            || !"PUBLISHED".equals(reward.getPackStatus())
                            || reward.getItemName() == null || reward.getItemName().isBlank()
                            || reward.getItemRarity() == null || reward.getItemRarity().isBlank()
                            || reward.getItemImagePath() == null || reward.getItemImagePath().isBlank()
                            || reward.getAmount() > Integer.MAX_VALUE) {
                        throw new IllegalStateException("收藏品奖励配置异常：请检查收藏品、图片和内容包发布状态");
                    }
                }
                default -> throw new IllegalStateException("奖励类型配置异常");
            }
            weightSum = Math.addExact(weightSum, reward.getWeight().longValue());
        }
        long ticket = ThreadLocalRandom.current().nextLong(weightSum);
        for (ShopReward reward : rewards) {
            ticket -= reward.getWeight();
            if (ticket < 0) return reward;
        }
        throw new IllegalStateException("随机奖励选择失败");
    }

    private void addLedger(Long userId, String action, String assetType,
                           long amount, Long openId) {
        AssetRecord ledger = new AssetRecord();
        ledger.setUserId(userId);
        ledger.setAction(action);
        ledger.setAssetType(assetType);
        ledger.setAmount(amount);
        ledger.setSource("SHOP_OPEN");
        ledger.setSourceId(openId);
        if (assetRecordMapper.insert(ledger) != 1) {
            throw new IllegalStateException("商店资产流水写入失败：" + action);
        }
    }

    private void requireUser(Long userId) {
        if (userId == null || userId <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "userId 不合法");
        }
        if (appUserMapper.selectById(userId) == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "用户不存在");
        }
    }

    private ShopOpenResponse toResponse(ShopOpenRecord record) {
        if (record.getCoinBalanceAfter() == null || record.getExpBalanceAfter() == null
                || record.getWaterBalanceAfter() == null) {
            throw new IllegalStateException("开盒记录缺少结算余额");
        }
        return new ShopOpenResponse(record.getOpenId(), record.getRequestId(),
                record.getBoxId(), record.getBoxName(), record.getPriceCoin(),
                record.getRewardType(), record.getRewardAmount(),
                record.getCoinBalanceAfter(), record.getExpBalanceAfter(),
                record.getWaterBalanceAfter(), record.getCollectibleItemId(),
                record.getItemName(), record.getItemRarity(), record.getItemImagePath(),
                record.getItemDescription());
    }
}
