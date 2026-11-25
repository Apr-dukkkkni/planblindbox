package com.planblindbox.mod.manifest;

import com.planblindbox.mod.domain.BadRequest;

import java.math.BigInteger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** SemVer 2.0.0 syntax and precedence shared by Manifest V1 code. */
public final class SemVerV1 {
    private static final Pattern VERSION = Pattern.compile(
            "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)"
          + "(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?"
          + "(?:\\+([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?$");

    private SemVerV1() {}

    public static void validate(String value, String field) {
        if (value == null || value.length() > 64) throw new BadRequest(field + " 最长 64 个字符");
        Matcher matcher = VERSION.matcher(value == null ? "" : value);
        if (!matcher.matches()) throw new BadRequest(field + " 必须符合 SemVer 2.0.0");
        String prerelease = matcher.group(4);
        if (prerelease != null) {
            for (String identifier : prerelease.split("\\.")) {
                if (identifier.matches("\\d+") && identifier.length() > 1 && identifier.startsWith("0")) {
                    throw new BadRequest(field + " 的数字预发布标识符不得有前导零");
                }
            }
        }
    }

    /** V1 range subset: exact, caret and tilde SemVer expressions. */
    public static void validateRange(String value, String field) {
        if (value == null || value.isBlank()) throw new BadRequest(field + " 不能为空");
        if (value.length() > 66) throw new BadRequest(field + " 最长 66 个字符");
        String version = value;
        if (version.startsWith("^") || version.startsWith("~")) version = version.substring(1);
        validate(version, field);
    }

    public static int compare(String left, String right) {
        validate(left, "left version");
        validate(right, "right version");
        Matcher a = VERSION.matcher(left);
        Matcher b = VERSION.matcher(right);
        a.matches();
        b.matches();
        for (int i = 1; i <= 3; i++) {
            int c = new BigInteger(a.group(i)).compareTo(new BigInteger(b.group(i)));
            if (c != 0) return c;
        }
        String aPre = a.group(4);
        String bPre = b.group(4);
        if (aPre == null && bPre == null) return 0;
        if (aPre == null) return 1;
        if (bPre == null) return -1;
        String[] aa = aPre.split("\\.");
        String[] bb = bPre.split("\\.");
        for (int i = 0; i < Math.min(aa.length, bb.length); i++) {
            String x = aa[i], y = bb[i];
            boolean xNumeric = x.matches("\\d+");
            boolean yNumeric = y.matches("\\d+");
            int c;
            if (xNumeric && yNumeric) {
                c = new BigInteger(x).compareTo(new BigInteger(y));
            } else if (xNumeric != yNumeric) {
                c = xNumeric ? -1 : 1;
            } else {
                c = x.compareTo(y);
            }
            if (c != 0) return c;
        }
        return Integer.compare(aa.length, bb.length);
    }
}
