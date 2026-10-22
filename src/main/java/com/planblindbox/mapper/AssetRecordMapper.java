package com.planblindbox.mapper;

import com.planblindbox.entity.AssetRecord;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Options;

public interface AssetRecordMapper {
    @Insert("""
            INSERT INTO asset_record (
                user_id, 
                action, 
                asset_type, 
                amount, 
                source, 
                source_id)
            VALUES (
                #{userId}, 
                #{action}, 
                #{assetType}, 
                #{amount}, 
                #{source}, 
                #{sourceId})
            """)
    @Options(useGeneratedKeys = true, keyProperty = "recordId", keyColumn = "record_id")
    int insert(AssetRecord record);
}
