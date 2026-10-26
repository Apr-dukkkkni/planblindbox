package com.planblindbox.controller;

import com.planblindbox.common.Result;
import com.planblindbox.dto.response.CollectibleItemResponse;
import com.planblindbox.dto.response.CollectiblePackResponse;
import com.planblindbox.service.CollectibleService;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/collection")
@RequiredArgsConstructor
public class CollectibleController {

    private final CollectibleService collectibleService;

    /** 当前用户已发布的收藏系列及收集进度。 */
    @GetMapping("/packs")
    public Result<List<CollectiblePackResponse>> packs(@RequestParam Long userId) {
        return Result.success(collectibleService.packs(userId));
    }

    /** 某个系列中的全部可用收藏品及当前用户的持有数量。 */
    @GetMapping("/packs/{packId}/items")
    public Result<List<CollectibleItemResponse>> items(
            @PathVariable Long packId,
            @RequestParam Long userId) {
        return Result.success(collectibleService.items(userId, packId));
    }
}
