package com.planblindbox.mod.water;

import java.util.List;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/me/water")
public class WaterController {
    private final WaterService water;
    public WaterController(WaterService water) {this.water=water;}
    private long currentUser(Jwt jwt){return Long.parseLong(jwt.getSubject());}

    @GetMapping
    public WaterService.Status status(@AuthenticationPrincipal Jwt jwt){return water.status(currentUser(jwt));}
    @PostMapping("/check-in")
    public WaterService.Claim checkIn(@AuthenticationPrincipal Jwt jwt){return water.claim(currentUser(jwt));}
    @GetMapping("/transactions")
    public List<WaterService.Transaction> transactions(@AuthenticationPrincipal Jwt jwt,
            @RequestParam(defaultValue="30") int limit) {
        return water.transactions(currentUser(jwt),limit);
    }
    @GetMapping("/check-ins")
    public List<WaterService.CheckIn> checkIns(@AuthenticationPrincipal Jwt jwt,
            @RequestParam int year,@RequestParam int month) {
        if(year<2000 || year>2100 || month<1 || month>12)
            throw new org.springframework.web.server.ResponseStatusException(
                org.springframework.http.HttpStatus.BAD_REQUEST,"日期无效");
        return water.month(currentUser(jwt),year,month);
    }
}
