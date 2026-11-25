package com.planblindbox.mod.manifest;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.mod.domain.BadRequest;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Strict Manifest V1 metadata validator. This does not verify package hashes,
 * Publisher signatures, Store Attestations, user grants, or Runtime support.
 */
@Component
public class ManifestV1Validator {
    public static final int MAX_MANIFEST_BYTES = 64 * 1024;
    private static final Pattern ID = Pattern.compile("^[a-z][a-z0-9]*(\\.[a-z][a-z0-9-]*)+$");
    private static final Pattern DOMAIN = Pattern.compile(
            "^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
          + "(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$");
    private static final Pattern LOCALE = Pattern.compile("^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$");
    private static final Pattern FIELD = Pattern.compile("^[A-Za-z][A-Za-z0-9_]{0,79}$");
    private static final Pattern API_VERSION = Pattern.compile("^(0|[1-9]\\d*)$");

    private static final Set<String> ROOT_KEYS = Set.of(
            "manifestVersion", "id", "version", "name", "description", "publisher",
            "type", "contentKind", "runtime", "compatibility", "ui", "storage",
            "permissions", "dependencies", "assets");
    private static final Set<String> CONTENT_KINDS = Set.of(
            "task_template", "theme", "shop_resource_pack", "reward_rules", "link_hub");
    private static final Set<String> RUNTIMES = Set.of("declarative", "web", "wasm");
    private static final Set<String> PLATFORMS = Set.of("android", "ios", "web", "windows", "macos", "linux");
    private static final Set<String> UI_MODES = Set.of("full_screen", "modal", "overlay");
    private static final Set<String> METHODS = Set.of("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE");
    private static final Set<String> CAPABILITIES = Set.of(
            "storage.local", "storage.files", "network.fetch",
            "host.data.tasks.read", "host.data.habits.read", "host.data.checkins.read",
            "host.data.time_records.read", "host.data.diary.read", "host.data.mood.read",
            "host.tasks.create", "host.tasks.update_limited", "host.habits.create",
            "host.habits.check_in", "host.external_link.open", "host.ui.notification",
            "host.ui.home_widget", "mods.message.send", "mods.message.subscribe");
    private static final Set<String> HOST_BUSINESS = Set.of(
            "host.data.tasks.read", "host.data.habits.read", "host.data.checkins.read",
            "host.data.time_records.read", "host.data.diary.read", "host.data.mood.read",
            "host.tasks.create", "host.tasks.update_limited", "host.habits.create", "host.habits.check_in");
    private static final Set<String> EGRESS = Set.of(
            "network.fetch", "host.external_link.open", "host.ui.notification",
            "host.ui.home_widget", "mods.message.send", "mods.message.subscribe");
    private static final Set<String> HOST_READ = Set.of(
            "host.data.tasks.read", "host.data.habits.read", "host.data.checkins.read",
            "host.data.time_records.read", "host.data.diary.read", "host.data.mood.read");
    private static final Set<String> SCOPE_KEYS = Set.of(
            "domains", "methods", "pathPrefixes", "fields", "maxRecordsPerRequest",
            "maxRequestsPerMinute", "maxRequestBytes", "maxResponseBytes", "timeoutMs", "operations");

    private final ObjectMapper mapper;

    public ManifestV1Validator(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    public JsonNode validate(String raw) {
        if (raw == null || raw.getBytes(StandardCharsets.UTF_8).length > MAX_MANIFEST_BYTES) {
            throw new BadRequest("Manifest 超过 64 KiB");
        }
        checkNestingDepth(raw, 32);
        final JsonNode root;
        try (JsonParser parser = mapper.getFactory().createParser(raw)) {
            parser.enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION);
            root = mapper.readTree(parser);
            if (parser.nextToken() != null) throw new BadRequest("JSON 包含尾随内容");
        } catch (BadRequest e) {
            throw e;
        } catch (Exception e) {
            throw new BadRequest("无效 JSON、重复字段或非法 Unicode");
        }
        if (root == null || !root.isObject()) throw new BadRequest("Manifest 根节点必须是 JSON 对象");
        validateUnicode(root);
        checkKeys(root, ROOT_KEYS, "Manifest");

        JsonNode manifestVersion = root.get("manifestVersion");
        if (manifestVersion == null || !manifestVersion.isInt() || manifestVersion.intValue() != 1) {
            throw new BadRequest("仅支持 manifestVersion = 1");
        }
        String id = text(root, "id", 1, 100, true);
        if (!ID.matcher(id).matches()) throw new BadRequest("id 必须为小写反向域名格式");
        SemVerV1.validate(text(root, "version", 1, 64, true), "version");
        validateName(root.get("name"));
        if (root.has("description")) text(root, "description", 0, 1000, false);

        JsonNode publisher = object(root.get("publisher"), "publisher");
        checkKeys(publisher, Set.of("id"), "publisher");
        String publisherId = text(publisher, "id", 1, 100, true);
        if (!ID.matcher(publisherId).matches()) throw new BadRequest("publisher.id 必须为小写反向域名格式");

        String type = text(root, "type", 1, 16, true);
        if (!type.equals("content") && !type.equals("app")) throw new BadRequest("type 只能是 content 或 app");
        String contentKind = root.has("contentKind") ? text(root, "contentKind", 1, 40, true) : null;
        if (type.equals("content")) {
            if (contentKind == null || !CONTENT_KINDS.contains(contentKind)) {
                throw new BadRequest("content 类型必须声明有效的 contentKind");
            }
        } else if (contentKind != null) {
            throw new BadRequest("app 类型不得声明 contentKind");
        }

        JsonNode runtime = object(root.get("runtime"), "runtime");
        checkKeys(runtime, Set.of("type", "apiVersion", "entrypoint"), "runtime");
        String runtimeType = text(runtime, "type", 1, 16, true);
        if (!RUNTIMES.contains(runtimeType)) throw new BadRequest("runtime.type 不受支持");
        if (type.equals("content") && !runtimeType.equals("declarative")) {
            throw new BadRequest("content 必须使用 declarative Runtime");
        }
        if (type.equals("app") && runtimeType.equals("declarative")) {
            throw new BadRequest("app 必须使用可执行 Runtime");
        }
        String apiVersion = text(runtime, "apiVersion", 1, 32, true);
        if (!API_VERSION.matcher(apiVersion).matches()) throw new BadRequest("runtime.apiVersion 必须为非负整数版本字符串");
        String entrypoint = text(runtime, "entrypoint", 1, 240, true);
        validatePackagePath(entrypoint, "runtime.entrypoint");
        String prefix = switch (runtimeType) {
            case "declarative" -> "content/";
            case "web" -> "web/";
            case "wasm" -> "wasm/";
            default -> throw new BadRequest("runtime.type 不受支持");
        };
        if (!entrypoint.startsWith(prefix)) throw new BadRequest("runtime.entrypoint 必须位于 " + prefix + " 目录");

        JsonNode compatibility = object(root.get("compatibility"), "compatibility");
        checkKeys(compatibility, Set.of("hostApi", "platforms"), "compatibility");
        SemVerV1.validateRange(text(compatibility, "hostApi", 1, 100, true), "compatibility.hostApi");
        stringArray(compatibility.get("platforms"), "compatibility.platforms", 1, 6, PLATFORMS);

        JsonNode ui = object(root.get("ui"), "ui");
        checkKeys(ui, Set.of("allowedModes", "defaultMode"), "ui");
        Set<String> modes = stringArray(ui.get("allowedModes"), "ui.allowedModes", 1, 3, UI_MODES);
        String defaultMode = text(ui, "defaultMode", 1, 32, true);
        if (!UI_MODES.contains(defaultMode) || !modes.contains(defaultMode)) {
            throw new BadRequest("ui.defaultMode 必须包含在 ui.allowedModes 中");
        }

        JsonNode storage = object(root.get("storage"), "storage");
        checkKeys(storage, Set.of("local"), "storage");
        JsonNode local = object(storage.get("local"), "storage.local");
        checkKeys(local, Set.of("enabled", "quotaMiB", "persistent"), "storage.local");
        if (!local.has("enabled") || !local.get("enabled").isBoolean()
                || !local.has("persistent") || !local.get("persistent").isBoolean()) {
            throw new BadRequest("storage.local.enabled/persistent 必须为布尔值");
        }
        boolean storageEnabled = local.get("enabled").booleanValue();
        boolean persistent = local.get("persistent").booleanValue();
        int quota = integer(local.get("quotaMiB"), "storage.local.quotaMiB", 0, 2048);
        if (storageEnabled && quota < 1) throw new BadRequest("启用 storage.local 时 quotaMiB 必须大于 0");
        if (!storageEnabled && (quota != 0 || persistent)) {
            throw new BadRequest("禁用 storage.local 时 quotaMiB 必须为 0 且 persistent 必须为 false");
        }

        Set<String> permissions = validatePermissions(root.get("permissions"));
        if (storageEnabled != permissions.contains("storage.local")) {
            throw new BadRequest("storage.local.enabled 必须与 storage.local 权限声明一致");
        }
        boolean hasHost = permissions.stream().anyMatch(HOST_BUSINESS::contains);
        boolean hasEgress = permissions.stream().anyMatch(EGRESS::contains);
        if (hasHost && hasEgress) {
            throw new BadRequest("V1 禁止同一 MOD 同时申请宿主业务 API 与网络/外发/跨 MOD 能力");
        }
        if ("task_template".equals(contentKind) && !permissions.contains("host.tasks.create")) {
            throw new BadRequest("task_template 必须声明 host.tasks.create");
        }
        if ("link_hub".equals(contentKind) && !permissions.contains("host.external_link.open")) {
            throw new BadRequest("link_hub 必须声明 host.external_link.open");
        }

        validateDependencies(root.get("dependencies"), id);
        if (root.has("assets")) {
            JsonNode assets = object(root.get("assets"), "assets");
            checkKeys(assets, Set.of("icon"), "assets");
            if (assets.has("icon")) {
                String icon = text(assets, "icon", 1, 240, true);
                validatePackagePath(icon, "assets.icon");
                if (!icon.startsWith("assets/")) throw new BadRequest("assets.icon 必须位于 assets/ 目录");
            }
        }
        return root;
    }

    private Set<String> validatePermissions(JsonNode value) {
        if (value == null || !value.isArray() || value.size() > 30) {
            throw new BadRequest("permissions 必须是数组，最多 30 项");
        }
        Set<String> result = new HashSet<>();
        for (int i = 0; i < value.size(); i++) {
            JsonNode permission = object(value.get(i), "permissions[" + i + "]");
            checkKeys(permission, Set.of("capability", "required", "reason", "scope"), "permissions[" + i + "]");
            String capability = text(permission, "capability", 1, 80, true);
            if (!CAPABILITIES.contains(capability)) throw new BadRequest("不支持的 capability：" + capability);
            if (!result.add(capability)) throw new BadRequest("permissions 中 capability 重复：" + capability);
            if (!permission.has("required") || !permission.get("required").isBoolean()) {
                throw new BadRequest("permissions[" + i + "].required 必须为布尔值");
            }
            text(permission, "reason", 1, 500, true);
            if (permission.has("scope")) validateScope(capability, permission.get("scope"));
            if (capability.equals("network.fetch") && !permission.has("scope")) {
                throw new BadRequest("network.fetch 必须声明 scope");
            }
            if (HOST_READ.contains(capability) && !permission.has("scope")) {
                throw new BadRequest(capability + " 必须声明 scope");
            }
        }
        return result;
    }

    private void validateScope(String capability, JsonNode value) {
        JsonNode scope = object(value, "permissions[" + capability + "].scope");
        checkKeys(scope, SCOPE_KEYS, "permissions[" + capability + "].scope");
        if (scope.isEmpty()) throw new BadRequest(capability + " 的 scope 不能为空");
        if (scope.has("domains")) {
            Set<String> domains = stringArray(scope.get("domains"), capability + ".scope.domains", 1, 20, null);
            for (String domain : domains) if (!DOMAIN.matcher(domain).matches()) {
                throw new BadRequest("network.fetch 域名必须是小写 DNS 主机名：" + domain);
            }
        }
        if (scope.has("methods")) stringArray(scope.get("methods"), capability + ".scope.methods", 1, 6, METHODS);
        if (scope.has("pathPrefixes")) {
            Set<String> paths = stringArray(scope.get("pathPrefixes"), capability + ".scope.pathPrefixes", 1, 30, null);
            for (String path : paths) validatePathPrefix(path);
        }
        if (scope.has("fields")) {
            Set<String> fields = stringArray(scope.get("fields"), capability + ".scope.fields", 1, 50, null);
            for (String field : fields) if (!FIELD.matcher(field).matches()) {
                throw new BadRequest("scope.fields 包含无效字段名：" + field);
            }
        }
        if (scope.has("maxRecordsPerRequest")) integer(scope.get("maxRecordsPerRequest"), capability + ".scope.maxRecordsPerRequest", 1, 500);
        if (scope.has("maxRequestsPerMinute")) integer(scope.get("maxRequestsPerMinute"), capability + ".scope.maxRequestsPerMinute", 1, 600);
        if (scope.has("maxRequestBytes")) integer(scope.get("maxRequestBytes"), capability + ".scope.maxRequestBytes", 0, 10 * 1024 * 1024);
        if (scope.has("maxResponseBytes")) integer(scope.get("maxResponseBytes"), capability + ".scope.maxResponseBytes", 0, 10 * 1024 * 1024);
        if (scope.has("timeoutMs")) integer(scope.get("timeoutMs"), capability + ".scope.timeoutMs", 100, 60000);
        if (scope.has("operations")) {
            Set<String> operations = stringArray(scope.get("operations"), capability + ".scope.operations", 1, 20, null);
            for (String operation : operations) if (operation.length() > 80) {
                throw new BadRequest(capability + ".scope.operations 单项最长 80 个字符");
            }
        }

        if (capability.equals("network.fetch")) {
            for (String key : Set.of("domains", "methods", "pathPrefixes")) {
                if (!scope.has(key)) throw new BadRequest("network.fetch.scope 缺少 " + key);
            }
        }
        if (HOST_READ.contains(capability)) {
            for (String key : Set.of("fields", "maxRecordsPerRequest")) {
                if (!scope.has(key)) throw new BadRequest(capability + ".scope 缺少 " + key);
            }
        }
    }

    private void validateDependencies(JsonNode value, String ownId) {
        if (value == null) return;
        if (!value.isArray() || value.size() > 50) throw new BadRequest("dependencies 必须是数组，最多 50 项");
        Set<String> ids = new HashSet<>();
        for (int i = 0; i < value.size(); i++) {
            JsonNode dependency = object(value.get(i), "dependencies[" + i + "]");
            checkKeys(dependency, Set.of("id", "versionRange", "optional"), "dependencies[" + i + "]");
            String id = text(dependency, "id", 1, 100, true);
            if (!ID.matcher(id).matches() || id.equals(ownId) || !ids.add(id)) {
                throw new BadRequest("dependencies[" + i + "].id 无效、指向自身或重复");
            }
            SemVerV1.validateRange(text(dependency, "versionRange", 1, 100, true), "dependencies[" + i + "].versionRange");
            if (dependency.has("optional") && !dependency.get("optional").isBoolean()) {
                throw new BadRequest("dependencies[" + i + "].optional 必须为布尔值");
            }
        }
    }

    private void validateName(JsonNode value) {
        JsonNode name = object(value, "name");
        if (name.isEmpty() || name.size() > 10) throw new BadRequest("name 必须包含 1 到 10 个语言版本");
        Iterator<String> names = name.fieldNames();
        while (names.hasNext()) {
            String locale = names.next();
            if (!LOCALE.matcher(locale).matches()) throw new BadRequest("name 包含无效语言标签：" + locale);
            text(name, locale, 1, 60, true);
        }
    }

    private Set<String> stringArray(JsonNode value, String field, int min, int max, Set<String> allowed) {
        if (value == null || !value.isArray() || value.size() < min || value.size() > max) {
            throw new BadRequest(field + " 必须包含 " + min + " 至 " + max + " 项");
        }
        Set<String> result = new HashSet<>();
        for (JsonNode item : value) {
            if (!item.isTextual() || item.asText().isEmpty() || (allowed != null && !allowed.contains(item.asText()))
                    || !result.add(item.asText())) {
                throw new BadRequest(field + " 包含无效或重复项目");
            }
        }
        return result;
    }

    private JsonNode object(JsonNode value, String field) {
        if (value == null || !value.isObject()) throw new BadRequest(field + " 必须是 JSON 对象");
        return value;
    }

    private void checkKeys(JsonNode value, Set<String> allowed, String field) {
        Iterator<String> keys = value.fieldNames();
        while (keys.hasNext()) {
            String key = keys.next();
            if (!allowed.contains(key)) throw new BadRequest(field + " 包含未知字段：" + key);
        }
    }

    private String text(JsonNode node, String key, int min, int max, boolean trimNonEmpty) {
        JsonNode value = node.get(key);
        if (value == null || !value.isTextual()) throw new BadRequest(key + " 必须是字符串");
        String text = value.asText();
        if (text.length() < min || text.length() > max || (trimNonEmpty && text.isBlank())) {
            throw new BadRequest(key + " 必须是长度为 " + min + " 至 " + max + " 的字符串");
        }
        return text;
    }

    private int integer(JsonNode value, String field, int min, int max) {
        if (value == null || !value.isIntegralNumber() || !value.canConvertToInt()
                || value.intValue() < min || value.intValue() > max) {
            throw new BadRequest(field + " 必须是 " + min + " 至 " + max + " 的整数");
        }
        return value.intValue();
    }

    private void checkNestingDepth(String raw, int maximum) {
        int depth = 0;
        boolean inString = false;
        boolean escaped = false;
        for (int i = 0; i < raw.length(); i++) {
            char c = raw.charAt(i);
            if (inString) {
                if (escaped) escaped = false;
                else if (c == '\\') escaped = true;
                else if (c == '"') inString = false;
                continue;
            }
            if (c == '"') inString = true;
            else if (c == '{' || c == '[') {
                depth++;
                if (depth > maximum) throw new BadRequest("JSON 嵌套层级超过 " + maximum);
            } else if (c == '}' || c == ']') {
                depth--;
            }
        }
    }

    private void validateUnicode(JsonNode node) {
        if (node.isTextual()) {
            if (hasUnpairedSurrogate(node.asText())) throw new BadRequest("JSON 字符串包含非法 Unicode");
            return;
        }
        if (node.isObject()) {
            Iterator<String> fields = node.fieldNames();
            while (fields.hasNext()) {
                String key = fields.next();
                if (hasUnpairedSurrogate(key)) throw new BadRequest("JSON 字段名包含非法 Unicode");
                validateUnicode(node.get(key));
            }
        } else if (node.isArray()) {
            for (JsonNode child : node) validateUnicode(child);
        }
    }

    private boolean hasUnpairedSurrogate(String value) {
        for (int i = 0; i < value.length(); i++) {
            char current = value.charAt(i);
            if (Character.isHighSurrogate(current)) {
                if (i + 1 >= value.length() || !Character.isLowSurrogate(value.charAt(i + 1))) return true;
                i++;
            } else if (Character.isLowSurrogate(current)) {
                return true;
            }
        }
        return false;
    }

    private void validatePackagePath(String value, String field) {
        if (value.isEmpty() || value.startsWith("/") || value.contains("\\") || value.indexOf('\0') >= 0
                || value.contains(":") || value.contains("//")) {
            throw new BadRequest(field + " 必须是安全的相对 POSIX 路径");
        }
        for (String segment : value.split("/", -1)) {
            if (segment.isEmpty() || segment.equals(".") || segment.equals("..")) {
                throw new BadRequest(field + " 不得包含空路径段、. 或 ..");
            }
        }
    }

    private void validatePathPrefix(String value) {
        if (value.isEmpty() || value.length() > 240 || !value.startsWith("/") || value.startsWith("//") || value.contains("\\")
                || value.contains("?") || value.contains("#") || Pattern.compile("%2e|%2f|%5c", Pattern.CASE_INSENSITIVE).matcher(value).find()) {
            throw new BadRequest("network.fetch pathPrefix 不是安全路径：" + value);
        }
        for (String segment : value.split("/", -1)) {
            if (segment.equals(".") || segment.equals("..")) throw new BadRequest("network.fetch pathPrefix 不得包含 . 或 ..：" + value);
        }
    }
}
