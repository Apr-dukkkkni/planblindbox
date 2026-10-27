package com.planblindbox.mapper;

import com.planblindbox.entity.RewardConfig;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

public interface RewardConfigMapper {
    @Select("SELECT * FROM reward_config WHERE type = #{type}")
    RewardConfig selectByType(@Param("type") String type);
}
