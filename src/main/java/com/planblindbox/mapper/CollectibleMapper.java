package com.planblindbox.mapper;

import com.planblindbox.dto.response.CollectibleItemResponse;
import com.planblindbox.dto.response.CollectiblePackResponse;
import java.util.List;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

public interface CollectibleMapper {

    @Select("""
            SELECT p.pack_id, p.pack_key, p.name, p.description, p.version,
                   p.unlock_level,
                   COUNT(DISTINCT CASE WHEN i.enabled = 1 THEN i.item_id END) AS total_items,
                   COUNT(DISTINCT CASE
                       WHEN i.enabled = 1 AND uc.owned_count > 0 THEN i.item_id
                   END) AS owned_items
            FROM content_pack p
            LEFT JOIN collectible_item i ON i.pack_id = p.pack_id
            LEFT JOIN user_collectible uc
                ON uc.item_id = i.item_id AND uc.user_id = #{userId}
            WHERE p.status = 'PUBLISHED'
            GROUP BY p.pack_id, p.pack_key, p.name, p.description, p.version, p.unlock_level
            ORDER BY p.pack_id
            """)
    List<CollectiblePackResponse> selectPublishedPacksForUser(@Param("userId") Long userId);

    @Select("""
            SELECT COUNT(*)
            FROM content_pack
            WHERE pack_id = #{packId} AND status = 'PUBLISHED'
            """)
    int countPublishedPack(@Param("packId") Long packId);

    @Select("""
            SELECT i.item_id, i.pack_id, i.item_key, i.name, i.rarity,
                   i.description, i.image_path, i.sort_order,
                   COALESCE(uc.owned_count, 0) AS owned_count,
                   CASE WHEN COALESCE(uc.owned_count, 0) > 0 THEN 1 ELSE 0 END AS owned
            FROM collectible_item i
            JOIN content_pack p ON p.pack_id = i.pack_id
            LEFT JOIN user_collectible uc
                ON uc.item_id = i.item_id AND uc.user_id = #{userId}
            WHERE i.pack_id = #{packId}
              AND i.enabled = 1
              AND p.status = 'PUBLISHED'
            ORDER BY i.sort_order, i.item_id
            """)
    List<CollectibleItemResponse> selectItemsForUser(
            @Param("userId") Long userId,
            @Param("packId") Long packId);

    @Insert("""
            INSERT INTO user_collectible (
                user_id, item_id, owned_count, first_obtained_time, last_obtained_time
            ) VALUES (
                #{userId}, #{itemId}, #{quantity}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            )
            ON DUPLICATE KEY UPDATE
                owned_count = user_collectible.owned_count + VALUES(owned_count),
                last_obtained_time = CURRENT_TIMESTAMP
            """)
    int addToInventory(@Param("userId") Long userId,
                       @Param("itemId") Long itemId,
                       @Param("quantity") int quantity);

    @Insert("""
            INSERT INTO collectible_acquisition_record (
                user_id, item_id, quantity, source_type, source_id
            ) VALUES (
                #{userId}, #{itemId}, #{quantity}, #{sourceType}, #{sourceId}
            )
            """)
    int insertAcquisitionRecord(@Param("userId") Long userId,
                                @Param("itemId") Long itemId,
                                @Param("quantity") int quantity,
                                @Param("sourceType") String sourceType,
                                @Param("sourceId") Long sourceId);
}
