package com.planblindbox.mod.sync;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/**
 * Retired V1 whole-database snapshot endpoint.
 *
 * V2 sync stores private records as client-encrypted private_blob records.
 * This endpoint must never read or write legacy snapshot payloads because
 * they may contain diary, mood, or period data in plaintext.
 */
@RestController
@RequestMapping("/api/v1/me/progress")
public class ProgressController {
    private ResponseStatusException retired() {
        return new ResponseStatusException(
            HttpStatus.GONE,
            "旧版整库云端快照接口已停用，请使用 V2 加密同步"
        );
    }

    @GetMapping
    public void get() {
        throw retired();
    }

    @PutMapping
    public void save() {
        throw retired();
    }
}
