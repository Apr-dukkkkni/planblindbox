package com.planblindbox.mod.profile;
import org.springframework.core.io.FileSystemResource;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
@RestController @RequestMapping("/api/v1/avatars")
public class AvatarController {
    private final AvatarStorage storage;
    public AvatarController(AvatarStorage storage){this.storage=storage;}
    @GetMapping("/{filename:.+}") ResponseEntity<FileSystemResource> file(@PathVariable String filename){return storage.get(filename);}
}
