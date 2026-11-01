package com.planblindbox.mod.service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/** SHA-256 of the exact UTF-8 bytes of the published JSON manifest. */
public final class ManifestIntegrity {
    private ManifestIntegrity() {}

    public static String sha256(String manifest) {
        if (manifest == null) throw new IllegalArgumentException("manifest cannot be null");
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(manifest.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("JDK SHA-256 unavailable", e);
        }
    }
}
