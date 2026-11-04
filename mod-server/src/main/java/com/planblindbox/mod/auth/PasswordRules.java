package com.planblindbox.mod.auth;

import com.planblindbox.mod.domain.BadRequest;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.regex.Pattern;

public final class PasswordRules {
    private static final Pattern EMAIL = Pattern.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$");
    private PasswordRules() {}
    public static String email(String email) {
        if (email == null) throw new BadRequest("请输入邮箱");
        String value = email.strip().toLowerCase(Locale.ROOT);
        if (value.length() > 100 || !EMAIL.matcher(value).matches()) throw new BadRequest("邮箱格式不正确（最多100字符）");
        return value;
    }
    public static String username(String value) {
        if (value == null) throw new BadRequest("请输入名称");
        String name = value.strip();
        if (name.isEmpty() || name.codePointCount(0, name.length()) > 50) throw new BadRequest("名称须为1～50字");
        return name;
    }
    public static void password(String value) {
        if (value == null || value.codePointCount(0, value.length()) < 8 || value.codePointCount(0, value.length()) > 64
                || value.getBytes(StandardCharsets.UTF_8).length > 72) {
            throw new BadRequest("密码须为8～64字符，UTF-8编码不超过72字节");
        }
    }
    public static String gender(String value) {
        if (!"MALE".equals(value) && !"FEMALE".equals(value) && !"UNDISCLOSED".equals(value))
            throw new BadRequest("请选择性别");
        return value;
    }
}
