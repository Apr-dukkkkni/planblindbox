package com.planblindbox.mod.service;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.mod.domain.BadRequest;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Set;
import java.util.regex.Pattern;

@Component
public class ManifestValidator {
    private final ObjectMapper mapper;
    private static final Pattern ID = Pattern.compile("^[a-z][a-z0-9]*(\\.[a-z][a-z0-9-]*)+$");
    private static final Pattern VERSION = Pattern.compile("^\\d{1,6}\\.\\d{1,6}\\.\\d{1,6}$");
    private static final Set<String> KEYS = Set.of("schemaVersion", "id", "name", "version", "description", "permissions", "dependencies", "taskTemplates", "minHostVersion");
    private static final Set<String> TEMPLATE_KEYS = Set.of("title", "note", "targetCount", "importance", "difficulty");

    public ManifestValidator(ObjectMapper mapper) { this.mapper = mapper; }

    public JsonNode validate(String raw) {
        if (raw == null || raw.getBytes(StandardCharsets.UTF_8).length > 64 * 1024) throw new BadRequest("清单最大为 64 KB");
        final JsonNode node;
        try (JsonParser parser = mapper.getFactory().createParser(raw)) {
            parser.enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION);
            node = mapper.readTree(parser);
            if (parser.nextToken() != null) throw new BadRequest("JSON 包含多余内容");
        } catch (BadRequest e) {
            throw e;
        } catch (Exception e) {
            throw new BadRequest("无效 JSON 或存在重复字段");
        }
        if (node == null || !node.isObject() || !node.path("schemaVersion").isInt() || node.path("schemaVersion").asInt() != 1)
            throw new BadRequest("仅支持 schemaVersion=1 的 JSON 对象");
        node.fieldNames().forEachRemaining(k -> { if (!KEYS.contains(k)) throw new BadRequest("未知字段: " + k); });
        String id = text(node, "id", 100);
        if (!ID.matcher(id).matches()) throw new BadRequest("id 必须为反向域名格式");
        text(node, "name", 60);
        String version = text(node, "version", 32);
        if (!VERSION.matcher(version).matches()) throw new BadRequest("version 必须为 major.minor.patch，且每段最多 6 位");
        if (node.has("minHostVersion")) {
            String minHost = text(node, "minHostVersion", 32);
            if (!VERSION.matcher(minHost).matches()) throw new BadRequest("minHostVersion 格式错误");
        }
        if (node.has("description")) textAllowEmpty(node, "description", 300);
        JsonNode permissions = node.path("permissions");
        if (!permissions.isMissingNode()) {
            if (!permissions.isArray() || permissions.size() > 10) throw new BadRequest("permissions 应为数组，最多 10 项");
            Set<String> distinct = new HashSet<>();
            for (JsonNode p : permissions) {
                if (!p.isTextual() || !p.asText().equals("tasks.create") || !distinct.add(p.asText()))
                    throw new BadRequest("包含不支持或重复的权限");
            }
        }
        JsonNode dependencies = node.path("dependencies");
        if (!dependencies.isMissingNode()) {
            if (!dependencies.isArray() || dependencies.size() > 10) throw new BadRequest("dependencies 格式错误");
            Set<String> distinct = new HashSet<>();
            for (JsonNode dep : dependencies) {
                if (!dep.isTextual() || !ID.matcher(dep.asText()).matches() || dep.asText().equals(id) || !distinct.add(dep.asText()))
                    throw new BadRequest("依赖 ID 错误或重复");
            }
        }
        JsonNode templates = node.path("taskTemplates");
        if (!templates.isMissingNode()) {
            if (!templates.isArray() || templates.size() > 20) throw new BadRequest("任务模板不能超过 20 项");
            if (!templates.isEmpty() && (!permissions.isArray() || !hasPermission(permissions))) throw new BadRequest("模板需要 tasks.create 权限");
            for (JsonNode t : templates) {
                if (!t.isObject()) throw new BadRequest("模板必须为对象");
                t.fieldNames().forEachRemaining(k -> { if (!TEMPLATE_KEYS.contains(k)) throw new BadRequest("模板未知字段"); });
                text(t, "title", 100);
                if (t.has("note")) textAllowEmpty(t,"note",500);
                number(t,"targetCount",1,999);
                number(t,"importance",1,5);
                number(t,"difficulty",1,5);
            }
        }
        return node;
    }

    private boolean hasPermission(JsonNode ps) { for (JsonNode p : ps) if (p.asText().equals("tasks.create")) return true; return false; }
    private String text(JsonNode node, String key, int max) {
        String value = textAllowEmpty(node,key,max);
        if (value.isBlank()) throw new BadRequest(key + " 不能为空");
        return value;
    }
    private String textAllowEmpty(JsonNode node,String key,int max) {
        JsonNode value=node.path(key);
        if (!value.isTextual() || value.asText().length()>max) throw new BadRequest(key+" 应为长度不超过 "+max+" 的字符串");
        return value.asText();
    }
    private void number(JsonNode node, String key, int min, int max) {
        if (!node.has(key)) return; // Flutter 客户端提供默认值
        JsonNode value=node.get(key);
        if (!value.isInt() || value.asInt()<min || value.asInt()>max) throw new BadRequest(key+" 超出范围");
    }
}
