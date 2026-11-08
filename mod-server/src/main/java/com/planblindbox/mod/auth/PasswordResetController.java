package com.planblindbox.mod.auth;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

/**
 * V1 email-only password reset is disabled for E2EE accounts. A V2 recovery
 * flow must re-wrap the AMK using a trusted device or the user's recovery key.
 */
@RestController @RequestMapping("/api/v1/auth/password")
public class PasswordResetController {
    @PostMapping({"/forgot", "/reset"})
    void retiredV1Reset() {
        throw new ResponseStatusException(HttpStatus.GONE,
            "V2 端到端加密账号不能使用旧式邮件重置密码；请使用可信设备或恢复材料恢复账号密钥");
    }
}
