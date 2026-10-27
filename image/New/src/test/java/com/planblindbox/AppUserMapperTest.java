package com.planblindbox;

import com.planblindbox.entity.AppUser;
import com.planblindbox.mapper.AppUserMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
class AppUserMapperTest {

    @Autowired
    private AppUserMapper appUserMapper;

    @Test
    void selectById_shouldReturnUser() {
        AppUser user = appUserMapper.selectById(1L);

        assertNotNull(user);
        assertEquals(1L, user.getUserId());

        System.out.println(user);
    }
}