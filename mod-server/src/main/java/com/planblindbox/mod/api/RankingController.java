package com.planblindbox.mod.api;

import com.planblindbox.mod.service.RankingService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/mods/ranking")
public class RankingController {
    private final RankingService ranking;

    public RankingController(RankingService ranking) {
        this.ranking = ranking;
    }

    @GetMapping
    public List<Map<String, Object>> top(@RequestParam(defaultValue = "10") int limit) {
        return ranking.top(limit);
    }
}
