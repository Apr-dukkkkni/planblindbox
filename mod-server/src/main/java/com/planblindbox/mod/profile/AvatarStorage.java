package com.planblindbox.mod.profile;

import com.planblindbox.mod.auth.UserRepository;
import com.planblindbox.mod.domain.BadRequest;
import java.io.ByteArrayInputStream;
import java.nio.file.*;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

@Service
public class AvatarStorage {
    private final Path root;
    private final UserRepository users;
    public AvatarStorage(@Value("${auth.avatars.directory:./data/avatars}") String dir,UserRepository users){
        this.root=Path.of(dir).toAbsolutePath().normalize();this.users=users;
    }
    public void save(long userId,MultipartFile uploaded) {
        try {
            byte[] bytes=uploaded.getBytes();
            if(bytes.length==0 || bytes.length>2*1024*1024) throw new BadRequest("头像大小不能超过2MiB");
            String ext;
            if(bytes.length>4 && (bytes[0]&255)==0x89 && bytes[1]==0x50 && bytes[2]==0x4e && bytes[3]==0x47)
                ext="png";
            else if(bytes.length>4 && (bytes[0]&255)==0xff && (bytes[1]&255)==0xd8)
                ext="jpg";
            else throw new BadRequest("头像仅支持 PNG 或 JPEG");
            var image=ImageIO.read(new ByteArrayInputStream(bytes));
            if(image==null || image.getWidth()>4096 || image.getHeight()>4096 || image.getWidth()<1 || image.getHeight()<1)
                throw new BadRequest("头像图片内容或尺寸无效");
            Files.createDirectories(root);
            String filename=UUID.randomUUID()+"."+ext;
            Path dest=root.resolve(filename);
            Files.write(dest,bytes,StandardOpenOption.CREATE_NEW);
            try {
                String old=users.byId(userId).avatar();
                users.avatar(userId,"/api/v1/avatars/"+filename);
                deleteOld(old);
            } catch(Exception ex){Files.deleteIfExists(dest);throw ex;}
        } catch(java.io.IOException e) {throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,"头像存储失败");}
    }
    public void clear(long userId) {
        String old=users.byId(userId).avatar();
        users.avatar(userId,null);deleteOld(old);
    }
    private void deleteOld(String old){
        if(old==null || !old.matches("/api/v1/avatars/[0-9a-f-]{36}\\.(png|jpg)"))return;
        try{Files.deleteIfExists(root.resolve(old.substring(old.lastIndexOf('/')+1)));}catch(java.io.IOException ignored){}
    }
    public ResponseEntity<FileSystemResource> get(String filename){
        if(!filename.matches("[0-9a-f-]{36}\\.(png|jpg)"))throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        Path path=root.resolve(filename).normalize();
        if(!path.startsWith(root)||!Files.isRegularFile(path))throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        return ResponseEntity.ok().contentType(filename.endsWith(".png")?MediaType.IMAGE_PNG:MediaType.IMAGE_JPEG)
            .header("Cache-Control","public, max-age=3600").body(new FileSystemResource(path));
    }
}
