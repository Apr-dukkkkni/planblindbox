package com.planblindbox.mod.sync;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

/** V1 password-derived private-sync setup is retired by the V2 OPAQUE/AMK protocol. */
@RestController
@RequestMapping("/api/v1/me/sync/crypto")
public class CoreSyncCryptoController {
    @GetMapping
    void retiredGet() {
        throw new ResponseStatusException(HttpStatus.GONE,
            "私密同步已升级为 OPAQUE V2 账号密钥体系");
    }
    @PutMapping
    void retiredCreate() {
        throw new ResponseStatusException(HttpStatus.GONE,
            "旧版恢复口令配置已停用，请使用 OPAQUE V2 客户端");
    }
}
