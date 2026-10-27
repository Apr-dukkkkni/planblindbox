package com.planblindbox.mapper;

import com.planblindbox.entity.AppUser;
import org.apache.ibatis.annotations.Select;

public interface AppUserMapper {

    @Select("""
            SELECT *
            FROM app_user
            WHERE user_id = #{userId}
            """)
    AppUser selectById(Long userId);

}