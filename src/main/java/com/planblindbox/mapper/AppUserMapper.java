package com.planblindbox.mapper;


import org.apache.ibatis.annotations.Mapper;

@Mapper
public interface AppUserMapper {

//    只要这个接口存在，MyBatis 就能扫描到一个 Mapper。
//    不过后面 Mapper 会越来越多，更推荐统一扫描，而不是每个 Mapper 都写 @Mapper
}
