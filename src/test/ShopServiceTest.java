package com.planblindbox;

import com.planblindbox.dto.response.ShopOpenResponse;
import com.planblindbox.entity.AppUser;
import com.planblindbox.entity.ShopBox;
import com.planblindbox.entity.ShopOpenRecord;
import com.planblindbox.entity.ShopReward;
import com.planblindbox.entity.UserAsset;
import com.planblindbox.mapper.AppUserMapper;
import com.planblindbox.mapper.AssetRecordMapper;
import com.planblindbox.mapper.ShopMapper;
import com.planblindbox.mapper.UserAssetMapper;
import com.planblindbox.service.ShopService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ShopServiceTest {
    private static final String RID = "b0ee715d-a3c3-49af-bae3-65800a387fed";
    @Mock ShopMapper shopMapper;
    @Mock AppUserMapper appUserMapper;
    @Mock UserAssetMapper userAssetMapper;
    @Mock AssetRecordMapper assetRecordMapper;
    @InjectMocks ShopService shopService;

    private void userExists() {
        when(appUserMapper.selectById(7L)).thenReturn(new AppUser());
    }

    private void enabledBoxAndSingleReward() {
        ShopBox box = new ShopBox();
        box.setBoxId(1L);
        box.setName("普通盲盒");
        box.setEnabled(true);
        box.setPriceCoin(50);
        when(shopMapper.selectEnabledBox(1L)).thenReturn(box);
        ShopReward reward = new ShopReward();
        reward.setRewardId(3L);
        reward.setBoxId(1L);
        reward.setAssetType("EXP");
        reward.setAmount(30L);
        reward.setWeight(100);
        when(shopMapper.selectActiveRewards(1L)).thenReturn(List.of(reward));
    }

    @Test
    void openDeductsAndGrantsAndPersistsTwoLedgerRecords() {
        userExists();
        enabledBoxAndSingleReward();
        when(shopMapper.insertOpen(any())).thenAnswer(invocation -> {
            ShopOpenRecord r = invocation.getArgument(0);
            r.setOpenId(100L);
            return 1;
        });
        when(shopMapper.deductCoins(7L, 50)).thenReturn(1);
        when(userAssetMapper.addAssets(7L, 0, 30L, 0)).thenReturn(2);
        when(assetRecordMapper.insert(any())).thenReturn(1);
        when(shopMapper.completeOpen(any())).thenReturn(1);
        UserAsset assets = new UserAsset();
        assets.setCoin(50);
        assets.setExp(30L);
        assets.setWater(0);
        when(userAssetMapper.selectByUserId(7L)).thenReturn(assets);

        ShopOpenResponse result = shopService.open(7L, 1L, RID);
        assertEquals(100L, result.openId());
        assertEquals(RID, result.requestId());
        assertEquals("EXP", result.rewardType());
        assertEquals(30L, result.rewardAmount());
        assertEquals(50, result.coinBalance());
        verify(assetRecordMapper, times(2)).insert(any());
        verify(shopMapper).deductCoins(7L, 50);
        verify(shopMapper).completeOpen(any());
    }

    @Test
    void insufficientBalanceNeverGrantsReward() {
        userExists();
        enabledBoxAndSingleReward();
        when(shopMapper.insertOpen(any())).thenAnswer(invocation -> {
            ShopOpenRecord r = invocation.getArgument(0);
            r.setOpenId(101L);
            return 1;
        });
        when(shopMapper.deductCoins(7L, 50)).thenReturn(0);
        ResponseStatusException ex = assertThrows(ResponseStatusException.class,
                () -> shopService.open(7L, 1L, RID));
        assertEquals(HttpStatus.CONFLICT, ex.getStatusCode());
        verify(userAssetMapper, never()).addAssets(any(), anyInt(), anyLong(), anyInt());
        verifyNoInteractions(assetRecordMapper);
    }

    @Test
    void retryReturnsSameResultWithoutSecondCharge() {
        userExists();
        ShopOpenRecord previous = new ShopOpenRecord();
        previous.setOpenId(102L);
        previous.setRequestId(RID);
        previous.setBoxId(1L);
        previous.setBoxName("普通盲盒");
        previous.setPriceCoin(50);
        previous.setRewardType("WATER");
        previous.setRewardAmount(2L);
        previous.setCoinBalanceAfter(90);
        previous.setExpBalanceAfter(30L);
        previous.setWaterBalanceAfter(2);
        when(shopMapper.selectByRequestId(7L, RID)).thenReturn(previous);
        ShopOpenResponse result = shopService.open(7L, 1L, RID);
        assertEquals(102L, result.openId());
        assertEquals(90, result.coinBalance());
        verify(shopMapper, never()).deductCoins(any(), anyInt());
        verify(shopMapper, never()).insertOpen(any());
        verifyNoInteractions(assetRecordMapper, userAssetMapper);
    }

    @Test
    void concurrentDuplicateInsertRejectedBeforeDebiting() {
        userExists();
        enabledBoxAndSingleReward();
        when(shopMapper.insertOpen(any()))
                .thenThrow(new DuplicateKeyException("uk_shop_open_user_request"));
        ResponseStatusException ex = assertThrows(ResponseStatusException.class,
                () -> shopService.open(7L, 1L, RID));
        assertEquals(HttpStatus.CONFLICT, ex.getStatusCode());
        verify(shopMapper, never()).deductCoins(any(), anyInt());
        verifyNoInteractions(assetRecordMapper, userAssetMapper);
    }
}
