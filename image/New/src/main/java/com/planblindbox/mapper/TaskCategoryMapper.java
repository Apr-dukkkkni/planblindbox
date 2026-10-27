package com.planblindbox.mapper;

import com.planblindbox.entity.TaskCategory;
import org.apache.ibatis.annotations.*;

import java.util.List;

@Mapper
public interface TaskCategoryMapper {

    @Select("SELECT COUNT(*) FROM task_category WHERE user_id = #{userId}")
    int countByUserId(@Param("userId") Long userId);

    @Select("""
            SELECT COUNT(*) FROM task_category
            WHERE user_id = #{userId} AND name = #{name}
            """)
    int countByUserAndName(@Param("userId") Long userId, @Param("name") String name);

    @Select("""
            SELECT category_id, user_id, name, color, icon,
                   is_default AS defaultCategory, enabled, create_time, update_time
            FROM task_category
            WHERE category_id = #{categoryId} AND user_id = #{userId}
            """)
    TaskCategory selectById(@Param("userId") Long userId,
                            @Param("categoryId") Long categoryId);

    @Select("""
            <script>
            SELECT category_id, user_id, name, color, icon,
                   is_default AS defaultCategory, enabled, create_time, update_time
            FROM task_category
            WHERE user_id = #{userId}
            <if test='includeDisabled == false'>
              AND enabled = 1
            </if>
            ORDER BY is_default DESC, category_id ASC
            </script>
            """)
    List<TaskCategory> selectByUserId(@Param("userId") Long userId,
                                      @Param("includeDisabled") boolean includeDisabled);

    @Insert("""
            INSERT INTO task_category
                (user_id, name, color, icon, is_default, enabled)
            VALUES
                (#{userId}, #{name}, #{color}, #{icon}, #{defaultCategory}, #{enabled})
            """)
    @Options(useGeneratedKeys = true, keyProperty = "categoryId", keyColumn = "category_id")
    int insert(TaskCategory category);

    /** 并发初始化默认分类时，依靠唯一索引避免重复插入。 */
    @Insert("""
            INSERT IGNORE INTO task_category
                (user_id, name, color, icon, is_default, enabled)
            VALUES
                (#{userId}, #{name}, #{color}, #{icon}, 1, 1)
            """)
    int insertDefaultIfAbsent(@Param("userId") Long userId,
                              @Param("name") String name,
                              @Param("color") String color,
                              @Param("icon") String icon);

    @Update("""
            UPDATE task_category
            SET name = #{name}, color = #{color}, enabled = #{enabled}
            WHERE category_id = #{categoryId} AND user_id = #{userId}
            """)
    int update(TaskCategory category);
}
