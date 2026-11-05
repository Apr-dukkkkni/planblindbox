package com.planblindbox.mod.profile;

import com.planblindbox.mod.auth.AuthService;
import java.time.LocalDate;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

@RestController @RequestMapping("/api/v1/me")
public class ProfileController {
    public record UpdateProfile(String username,String gender,LocalDate birthday) {}
    private final AuthService auth;
    private final AvatarStorage avatars;
    public ProfileController(AuthService auth,AvatarStorage avatars){this.auth=auth;this.avatars=avatars;}
    private long id(Jwt jwt){return Long.parseLong(jwt.getSubject());}
    @GetMapping AuthService.Profile me(@AuthenticationPrincipal Jwt jwt){return auth.me(id(jwt));}
    @PutMapping AuthService.Profile update(@AuthenticationPrincipal Jwt jwt,@RequestBody UpdateProfile request){
        return auth.update(id(jwt),request.username(),request.gender(),request.birthday());
    }
    @PostMapping("/avatar") AuthService.Profile avatar(@AuthenticationPrincipal Jwt jwt,@RequestParam("file") MultipartFile file){
        avatars.save(id(jwt),file);return auth.me(id(jwt));
    }
    @DeleteMapping("/avatar") @ResponseStatus(HttpStatus.NO_CONTENT)
    void deleteAvatar(@AuthenticationPrincipal Jwt jwt){avatars.clear(id(jwt));}
}
