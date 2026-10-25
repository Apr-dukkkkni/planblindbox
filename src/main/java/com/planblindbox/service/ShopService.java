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

/** 商店：购买 / 扣款 / 发奖 / 流水 / 开盒记录，全部在一个数据库事务内完成。 */
@Service
@RequiredArgsConstructor
public class ShopService {

    private final ShopMapper shopMapper;
    private final AppUserMapper appUserMapper;
    private final UserAssetMapper userAssetMapper;
    private final AssetRecordMapper assetRecordMapper;

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
        // 统一 UUID 表示，避免一笔请求不同大小写被当作两笔开盒。
        final String normalized;
        try {
            normalized = UUID.fromString(requestId).toString();
        } catch (IllegalArgumentException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "requestId 必须是 UUID");
        }
        if (!normalized.equalsIgnoreCase(requestId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "requestId 必须是标准 UUID 格式");
        }

        // 已提交过的同一请求直接返回第一次的结果，不重复扣款或重新抽奖。
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
        // 先用 UNIQUE(user_id, request_id) 占住请求，再执行扣款。
        // 两个同时发起、且 requestId 相同的请求：只有一个能通过插入。
        ShopOpenRecord record = new ShopOpenRecord();
        record.setUserId(userId);
        record.setBoxId(boxId);
        record.setBoxName(box.getName());
        record.setRequestId(normalized);
        record.setRewardId(reward.getRewardId());
        record.setPriceCoin(price);
        record.setRewardType(reward.getAssetType());
        record.setRewardAmount(reward.getAmount());
        try {
            if (shopMapper.insertOpen(record) != 1 || record.getOpenId() == null) {
                throw new IllegalStateException("创建开盒记录失败");
            }
        } catch (DuplicateKeyException exception) {
            // 并发重复请求不扣款。第一次请求的响应可通过 GET /shop/opens 查询。
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "本次开盒请求已被处理，请刷新开盒记录", exception);
        }

        if (shopMapper.deductCoins(userId, price) != 1) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "金币不足，无法开盒");
        }
        addLedger(userId, "SHOP_OPEN_COST", "COIN", -price.longValue(), record.getOpenId());

        int coinReward = 0;
        long expReward = 0;
        int waterReward = 0;
        switch (reward.getAssetType()) {
            case "COIN" -> coinReward = Math.toIntExact(reward.getAmount());
            case "EXP" -> expReward = reward.getAmount();
            case "WATER" -> waterReward = Math.toIntExact(reward.getAmount());
            default -> throw new IllegalStateException("奖励类型配置异常");
        }
        if (userAssetMapper.addAssets(userId, coinReward, expReward, waterReward) < 1) {
            throw new IllegalStateException("开盒奖励入账失败");
        }
        addLedger(userId, "SHOP_OPEN_REWARD", reward.getAssetType(),
                reward.getAmount(), record.getOpenId());

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

    private ShopReward pickReward(List<ShopReward> rewards) {
        if (rewards == null || rewards.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "盲盒尚未配置可用奖励");
        }
        long weightSum = 0;
        for (ShopReward r : rewards) {
            if (r.getRewardId() == null || r.getAmount() == null || r.getAmount() <= 0
                    || r.getWeight() == null || r.getWeight() <= 0
                    || !("COIN".equals(r.getAssetType()) || "EXP".equals(r.getAssetType())
                        || "WATER".equals(r.getAssetType()))) {
                throw new IllegalStateException("商店奖励池配置异常");
            }
            if (!"EXP".equals(r.getAssetType()) && r.getAmount() > Integer.MAX_VALUE) {
                throw new IllegalStateException("COIN/WATER 奖励超出整数范围");
            }
            weightSum = Math.addExact(weightSum, r.getWeight().longValue());
        }
        long ticket = ThreadLocalRandom.current().nextLong(weightSum);
        for (ShopReward r : rewards) {
            ticket -= r.getWeight();
            if (ticket < 0) return r;
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
                record.getWaterBalanceAfter());
    }
}
