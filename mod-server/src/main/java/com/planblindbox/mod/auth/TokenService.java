package com.planblindbox.mod.auth;

import java.time.Instant;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.stereotype.Service;

@Service
public class TokenService {
    private final JwtEncoder encoder;
    private final String issuer,audience;
    private final long ttl;
    public TokenService(JwtEncoder encoder,@Value("${auth.jwt.issuer}") String issuer,
          @Value("${auth.jwt.audience}") String audience,@Value("${auth.jwt.ttl-seconds:7200}") long ttl) {
        this.encoder=encoder;this.issuer=issuer;this.audience=audience;this.ttl=ttl;
    }
    public String issue(UserRepository.User user) {
        Instant now=Instant.now();
        JwtClaimsSet claims=JwtClaimsSet.builder().issuer(issuer).audience(java.util.List.of(audience))
            .subject(Long.toString(user.id())).issuedAt(now).expiresAt(now.plusSeconds(ttl))
            .claim("cv",user.credentialVersion()).build();
        return encoder.encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(),claims)).getTokenValue();
    }
    public long ttl() {return ttl;}
}
