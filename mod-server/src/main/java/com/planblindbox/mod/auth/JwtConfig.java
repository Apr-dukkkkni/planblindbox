package com.planblindbox.mod.auth;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;

import com.nimbusds.jose.jwk.source.ImmutableSecret;
import java.util.Base64;
import java.util.List;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.*;

@Configuration
public class JwtConfig {
    @Bean SecretKey jwtSecret(@Value("${auth.jwt.secret-base64:}") String raw) {
        try {
            byte[] key=Base64.getDecoder().decode(raw);
            if (key.length<32) throw new IllegalArgumentException("JWT secret must be at least 32 random bytes");
            return new SecretKeySpec(key,"HmacSHA256");
        } catch (IllegalArgumentException e) {
            throw new IllegalStateException("请配置 APP_JWT_SECRET_BASE64（至少32随机字节，Base64）",e);
        }
    }
    @Bean JwtEncoder jwtEncoder(SecretKey jwtSecret) {return new NimbusJwtEncoder(new ImmutableSecret<>(jwtSecret));}
    @Bean JwtDecoder jwtDecoder(SecretKey jwtSecret,UserRepository users,
            @Value("${auth.jwt.issuer}") String issuer,@Value("${auth.jwt.audience}") String audience) {
        NimbusJwtDecoder decoder=NimbusJwtDecoder.withSecretKey(jwtSecret).macAlgorithm(MacAlgorithm.HS256).build();
        OAuth2TokenValidator<Jwt> custom=jwt -> {
            try {
                if (!jwt.getAudience().contains(audience) || jwt.getIssuedAt()==null || jwt.getExpiresAt()==null)
                    return invalid("invalid audience or timestamps");
                long id=Long.parseLong(jwt.getSubject());
                Object cv=jwt.getClaim("cv");
                if (!(cv instanceof Number)) return invalid("invalid credentials");
                UserRepository.User user=users.byId(id);
                if (user==null || !"ACTIVE".equals(user.status()) || user.credentialVersion()!=((Number)cv).longValue())
                    return invalid("credential revoked");
                return OAuth2TokenValidatorResult.success();
            } catch (RuntimeException e) {return invalid("invalid credentials");}
        };
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(JwtValidators.createDefaultWithIssuer(issuer),custom));
        return decoder;
    }
    private static OAuth2TokenValidatorResult invalid(String message) {
        return OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token",message,null));
    }
}
