-- PlanBlindBox Step 12.3: seed the first butterfly collectible pack.
-- Prerequisites: content_pack, collectible_item, user_collectible,
-- collectible_acquisition_record already exist; shop_reward.item_id and
-- COLLECTIBLE type constraints are installed; shop_box has NORMAL/PREMIUM.
-- Re-runnable for the same pack keys and reward codes.
-- Proposed odds: NORMAL collectible weight sum=23 against existing 100;
-- PREMIUM collectible weight sum=52 against existing 100. Existing numeric
-- reward weights are not modified, so adding these rows changes total odds.

START TRANSACTION;

INSERT INTO content_pack (pack_key, name, description, version, unlock_level, status)
VALUES ('butterfly-pack', '蝴蝶图鉴', '以不同艺术风格呈现的蝴蝶收藏系列。', '1.0.0', 1, 'PUBLISHED')
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    description = VALUES(description),
    version = VALUES(version),
    unlock_level = VALUES(unlock_level),
    status = VALUES(status);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'oil_blue_yellow', '油彩花草蝶', 'COMMON',
       '蓝黄蝶翼在油画般的花草间展开。', '/collectibles/butterfly/butterfly_oil_meadow.png', 1, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_OIL_MEADOW', 'COLLECTIBLE', 1, i.item_id, 3, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'oil_blue_yellow'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_OIL_MEADOW', 'COLLECTIBLE', 1, i.item_id, 3, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'oil_blue_yellow'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'warm_lattice_shadow', '暖影镂彩蝶', 'RARE',
       '暖金色镂空蝶翼，带有皮影艺术的装饰感。', '/collectibles/butterfly/butterfly_warm_shadow.png', 2, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_WARM_SHADOW', 'COLLECTIBLE', 1, i.item_id, 2, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'warm_lattice_shadow'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_WARM_SHADOW', 'COLLECTIBLE', 1, i.item_id, 4, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'warm_lattice_shadow'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'gothic_moon_beaded', '月下哥特蝶', 'LEGENDARY',
       '暗红珠饰与哥特花纹构成神秘的月下蝶影。', '/collectibles/butterfly/butterfly_gothic_moon.png', 3, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_GOTHIC_MOON', 'COLLECTIBLE', 1, i.item_id, 1, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'gothic_moon_beaded'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_GOTHIC_MOON', 'COLLECTIBLE', 1, i.item_id, 5, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'gothic_moon_beaded'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'violet_garden_dream', '紫罗兰梦蝶', 'RARE',
       '紫罗兰色蝶翼融入柔和的梦幻花园。', '/collectibles/butterfly/butterfly_violet_garden.png', 4, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_VIOLET_GARDEN', 'COLLECTIBLE', 1, i.item_id, 2, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'violet_garden_dream'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_VIOLET_GARDEN', 'COLLECTIBLE', 1, i.item_id, 4, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'violet_garden_dream'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'crystal_ice_realm', '冰晶幻蝶', 'EPIC',
       '由晶莹冰晶与冷色光芒构成的幻想蝶翼。', '/collectibles/butterfly/butterfly_crystal_ice.png', 5, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_CRYSTAL_ICE', 'COLLECTIBLE', 1, i.item_id, 1, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'crystal_ice_realm'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_CRYSTAL_ICE', 'COLLECTIBLE', 1, i.item_id, 6, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'crystal_ice_realm'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'pop_art_colorful', '波普彩蝶', 'COMMON',
       '以高饱和撞色和波普艺术风格呈现的缤纷蝶翼。', '/collectibles/butterfly/butterfly_pop_art.png', 6, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_POP_ART', 'COLLECTIBLE', 1, i.item_id, 3, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'pop_art_colorful'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_POP_ART', 'COLLECTIBLE', 1, i.item_id, 3, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'pop_art_colorful'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'pointillism_dream', '点彩幻蝶', 'COMMON',
       '细密色点汇聚成梦境般的彩色蝶翼。', '/collectibles/butterfly/butterfly_pointillism.png', 7, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_POINTILLISM', 'COLLECTIBLE', 1, i.item_id, 3, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'pointillism_dream'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_POINTILLISM', 'COLLECTIBLE', 1, i.item_id, 3, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'pointillism_dream'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'mechanical_gear_realm', '齿轮机械蝶', 'EPIC',
       '精密齿轮与金属结构环绕发光的机械蝶翼。', '/collectibles/butterfly/butterfly_mechanical_gear.png', 8, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_MECHANICAL_GEAR', 'COLLECTIBLE', 1, i.item_id, 1, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'mechanical_gear_realm'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_MECHANICAL_GEAR', 'COLLECTIBLE', 1, i.item_id, 6, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'mechanical_gear_realm'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'embroidered_garden', '锦绣花园蝶', 'COMMON',
       '以花卉刺绣和丰富纹样装饰的彩翼蝴蝶。', '/collectibles/butterfly/butterfly_embroidery_garden.png', 9, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_EMBROIDERY', 'COLLECTIBLE', 1, i.item_id, 3, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'embroidered_garden'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_EMBROIDERY', 'COLLECTIBLE', 1, i.item_id, 3, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'embroidered_garden'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'golden_sakura_waves', '金彩樱海蝶', 'RARE',
       '金色纹样、樱花与海浪元素交织成华丽蝶翼。', '/collectibles/butterfly/butterfly_golden_sakura.png', 10, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_GOLDEN_SAKURA', 'COLLECTIBLE', 1, i.item_id, 2, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'golden_sakura_waves'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_GOLDEN_SAKURA', 'COLLECTIBLE', 1, i.item_id, 4, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'golden_sakura_waves'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'gilded_ice_blue_silk', '鎏金冰纱蝶', 'EPIC',
       '鎏金边饰与冰蓝薄纱交织出轻盈而华丽的蝶翼。', '/collectibles/butterfly/butterfly_gilded_ice_silk.png', 11, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_GILDED_ICE_SILK', 'COLLECTIBLE', 1, i.item_id, 1, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'gilded_ice_blue_silk'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_GILDED_ICE_SILK', 'COLLECTIBLE', 1, i.item_id, 6, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'gilded_ice_blue_silk'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO collectible_item (pack_id, item_key, name, rarity, description, image_path, sort_order, enabled)
SELECT p.pack_id, 'cosmic_nebula', '星云宇宙蝶', 'LEGENDARY',
       '霓虹蓝紫色蝶翼仿佛映照着遥远星云。', '/collectibles/butterfly/butterfly_cosmic_nebula.png', 12, 1
FROM content_pack p
WHERE p.pack_key = 'butterfly-pack'
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    rarity = VALUES(rarity),
    description = VALUES(description),
    image_path = VALUES(image_path),
    sort_order = VALUES(sort_order),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_COSMIC_NEBULA', 'COLLECTIBLE', 1, i.item_id, 1, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'cosmic_nebula'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'NORMAL'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

INSERT INTO shop_reward (box_id, code, asset_type, amount, item_id, weight, enabled)
SELECT b.box_id, 'BFLY_COSMIC_NEBULA', 'COLLECTIBLE', 1, i.item_id, 5, 1
FROM shop_box b
JOIN collectible_item i ON i.item_key = 'cosmic_nebula'
JOIN content_pack p ON p.pack_id = i.pack_id AND p.pack_key = 'butterfly-pack'
WHERE b.code = 'PREMIUM'
ON DUPLICATE KEY UPDATE
    asset_type = VALUES(asset_type),
    amount = VALUES(amount),
    item_id = VALUES(item_id),
    weight = VALUES(weight),
    enabled = VALUES(enabled);

COMMIT;

-- Verify content pack.
SELECT pack_id, pack_key, name, version, unlock_level, status
FROM content_pack WHERE pack_key = 'butterfly-pack';

-- Verify the 12 collectible definitions and their image paths.
SELECT item_id, item_key, name, rarity, image_path, sort_order, enabled
FROM collectible_item
WHERE pack_id = (SELECT pack_id FROM content_pack WHERE pack_key = 'butterfly-pack')
ORDER BY sort_order;

-- Verify the 24 collectible reward rows (12 in each existing box).
SELECT b.code AS box_code, r.code AS reward_code, r.asset_type, r.amount,
       r.weight, i.item_key, i.name AS item_name
FROM shop_reward r
JOIN shop_box b ON b.box_id = r.box_id
JOIN collectible_item i ON i.item_id = r.item_id
WHERE r.asset_type = 'COLLECTIBLE'
  AND i.pack_id = (SELECT pack_id FROM content_pack WHERE pack_key = 'butterfly-pack')
ORDER BY b.box_id, i.sort_order;
