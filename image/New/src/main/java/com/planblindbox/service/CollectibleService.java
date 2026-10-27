package com.planblindbox.service;

import com.planblindbox.dto.response.CollectibleItemResponse;
import com.planblindbox.dto.response.CollectiblePackResponse;
import com.planblindbox.mapper.AppUserMapper;
import com.planblindbox.mapper.CollectibleMapper;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/** 用户收藏查询。只读，不负责发放收藏品；发放由开盒事务完成。 */
@Service
@RequiredArgsConstructor
public class CollectibleService {

    private final CollectibleMapper collectibleMapper;
    private final AppUserMapper appUserMapper;

    @Transactional(readOnly = true)
    public List<CollectiblePackResponse> packs(Long userId) {
        requireUser(userId);
        return collectibleMapper.selectPublishedPacksForUser(userId);
    }

    @Transactional(readOnly = true)
    public List<CollectibleItemResponse> items(Long userId, Long packId) {
        requireUser(userId);
        if (packId == null || packId <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "packId 必须为正整数");
        }
        if (collectibleMapper.countPublishedPack(packId) == 0) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "内容包不存在或尚未发布");
        }
        return collectibleMapper.selectItemsForUser(userId, packId);
    }

    private void requireUser(Long userId) {
        if (userId == null || userId <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "userId 必须为正整数");
        }
        if (appUserMapper.selectById(userId) == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "用户不存在");
        }
    }
}
