package com.planblindbox.entity;

import lombok.Data;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Data
public class AppUser {

    private Long userId;

    private String username;

    private String phone;

    private String email;

    private String password;

    private String avatar;

    private String status;

    private LocalDate birthday;

    /**
     * 数据库中是 JSON。
     * 第一版暂时使用 String 接收。
     */
    private String userSetting;

    private LocalDateTime createTime;

    private LocalDateTime updateTime;

    private LocalDateTime lastLoginTime;
}