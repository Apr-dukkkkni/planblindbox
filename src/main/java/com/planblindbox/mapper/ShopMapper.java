package com.planblindbox.mapper;

import com.planblindbox.entity.ShopBox;
import com.planblindbox.entity.ShopReward;
import com.planblindbox.entity.ShopOpenRecord;
import java.util.List;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Options;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

public interface ShopMapper {

    @Select("SELECT box_id, code, name, description, price_coin, enabled FROM shop_box WHERE enabled = 1 ORDER BY box_id")
    List<ShopBox> selectEnabledBoxes();

    @Select("SELECT box_id, code, name, description, price_coin, enabled FROM shop_box WHERE box_id = #{boxId} AND enabled = 1")
    ShopBox selectEnabledBox(@Param("boxId") Long boxId);

    @Select("SELECT reward_id, box_id, asset_type, amount, weight FROM shop_reward WHERE box_id = #{boxId} AND enabled = 1 ORDER BY reward_id")
    List<ShopReward> selectActiveRewards(@Param("boxId") Long boxId);

    @Select("""
            SELECT r.*, b.name AS box_name FROM shop_open_record r
            JOIN shop_box b ON b.box_id = r.box_id
            WHERE r.user_id = #{userId} AND r.request_id = #{requestId}
            """)
    ShopOpenRecord selectByRequestId(@Param("userId") Long userId,
                                     @Param("requestId") String requestId);

    @Select("""
            SELECT r.*, b.name AS box_name FROM shop_open_record r
            JOIN shop_box b ON b.box_id = r.box_id
            WHERE r.user_id = #{userId}
            ORDER BY r.open_id DESC LIMIT #{limit}
            """)
    List<ShopOpenRecord> selectRecentOpens(@Param("userId") Long userId,
                                           @Param("limit") int limit);

    @Insert("""
            INSERT INTO shop_open_record (
                user_id, box_id, request_id, reward_id, price_coin, reward_type, reward_amount
            ) VALUES (
                #{userId}, #{boxId}, #{requestId}, #{rewardId}, #{priceCoin}, #{rewardType}, #{rewardAmount}
            )
            """)
    @Options(useGeneratedKeys = true, keyProperty = "openId", keyColumn = "open_id")
    int insertOpen(ShopOpenRecord record);

    // 原子条件扣款：余额不足、并发抢余额均返回 0 行。
    @Update("""
            UPDATE user_asset SET coin = coin - #{price}
            WHERE user_id = #{userId} AND coin >= #{price}
            """)
    int deductCoins(@Param("userId") Long userId, @Param("price") int price);

    @Update("""
            UPDATE shop_open_record
            SET coin_balance_after = #{coinBalanceAfter},
                exp_balance_after = #{expBalanceAfter},
                water_balance_after = #{waterBalanceAfter}
            WHERE open_id = #{openId} AND user_id = #{userId}
            """)
    int completeOpen(ShopOpenRecord record);
}
