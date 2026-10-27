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

    @Select("""
            SELECT r.reward_id, r.box_id, r.asset_type, r.amount, r.weight, r.item_id,
                   i.name AS item_name,
                   i.rarity AS item_rarity,
                   i.description AS item_description,
                   i.image_path AS item_image_path,
                   i.enabled AS item_enabled,
                   p.status AS pack_status
            FROM shop_reward r
            LEFT JOIN collectible_item i ON i.item_id = r.item_id
            LEFT JOIN content_pack p ON p.pack_id = i.pack_id
            WHERE r.box_id = #{boxId} AND r.enabled = 1
            ORDER BY r.reward_id
            """)
    List<ShopReward> selectActiveRewards(@Param("boxId") Long boxId);

    @Select("""
            SELECT r.*, b.name AS box_name,
                   i.name AS item_name,
                   i.rarity AS item_rarity,
                   i.description AS item_description,
                   i.image_path AS item_image_path
            FROM shop_open_record r
            JOIN shop_box b ON b.box_id = r.box_id
            LEFT JOIN collectible_item i ON i.item_id = r.collectible_item_id
            WHERE r.user_id = #{userId} AND r.request_id = #{requestId}
            """)
    ShopOpenRecord selectByRequestId(@Param("userId") Long userId,
                                     @Param("requestId") String requestId);

    @Select("""
            SELECT r.*, b.name AS box_name,
                   i.name AS item_name,
                   i.rarity AS item_rarity,
                   i.description AS item_description,
                   i.image_path AS item_image_path
            FROM shop_open_record r
            JOIN shop_box b ON b.box_id = r.box_id
            LEFT JOIN collectible_item i ON i.item_id = r.collectible_item_id
            WHERE r.user_id = #{userId}
            ORDER BY r.open_id DESC LIMIT #{limit}
            """)
    List<ShopOpenRecord> selectRecentOpens(@Param("userId") Long userId,
                                           @Param("limit") int limit);

    @Insert("""
            INSERT INTO shop_open_record (
                user_id, box_id, request_id, reward_id, collectible_item_id,
                price_coin, reward_type, reward_amount
            ) VALUES (
                #{userId}, #{boxId}, #{requestId}, #{rewardId}, #{collectibleItemId},
                #{priceCoin}, #{rewardType}, #{rewardAmount}
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
