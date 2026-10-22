package com.planblindbox.mapper;

import com.planblindbox.entity.UserAsset;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

public interface UserAssetMapper {
    /**
     * 同一个用户执行不同任务时也可能同时发奖；使用数据库原子累加而不是先 SELECT 再 UPDATE。
     * user_asset.user_id 的 UNIQUE 约束保证一个用户仅一行资产。
     */
    @Insert("""
            INSERT INTO user_asset (user_id, coin, exp, water)
            VALUES (#{userId}, #{coin}, #{exp}, #{water})
            ON DUPLICATE KEY UPDATE
                coin = user_asset.coin + #{coin},
                exp = user_asset.exp + #{exp},
                water = user_asset.water + #{water}
            """)
    int addAssets(@Param("userId") Long userId,
                  @Param("coin") int coin,
                  @Param("exp") long exp,
                  @Param("water") int water);

    @Select("SELECT * FROM user_asset WHERE user_id = #{userId}")
    UserAsset selectByUserId(@Param("userId") Long userId);
}
