package com.planblindbox.mod.auth;

import com.planblindbox.mod.domain.BadRequest;
import java.time.LocalDate;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class AuthService {
    public record Profile(long userId,String username,String email,String gender,String avatar,LocalDate birthday) {}
    public record LoginResponse(String accessToken,long expiresIn,Profile user) {}
    private final UserRepository users;
    private final PasswordEncoder encoder;
    private final TokenService tokens;
    public AuthService(UserRepository users,PasswordEncoder encoder,TokenService tokens) {
        this.users=users;this.encoder=encoder;this.tokens=tokens;
    }
    public static Profile profile(UserRepository.User u) {
        return new Profile(u.id(),u.username(),u.email(),u.gender(),u.avatar(),u.birthday());
    }
    @Transactional
    public Profile register(String name,String email,String password,String gender) {
        name=PasswordRules.username(name);email=PasswordRules.email(email);PasswordRules.password(password);
        gender=PasswordRules.gender(gender);
        try {
            long id=users.insert(name,email,encoder.encode(password),gender);
            return profile(users.byId(id));
        } catch (DuplicateKeyException e) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,"该邮箱已经注册");
        }
    }
    public LoginResponse login(String email,String password) {
        email=PasswordRules.email(email);
        if (password==null || password.getBytes(java.nio.charset.StandardCharsets.UTF_8).length>72)
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,"邮箱或密码错误");
        UserRepository.User user=users.byEmail(email);
        if(user==null || !"ACTIVE".equals(user.status()) || !encoder.matches(password,user.passwordHash()))
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,"邮箱或密码错误");
        users.loginAt(user.id());
        return new LoginResponse(tokens.issue(user),tokens.ttl(),profile(user));
    }
    public Profile me(long id) {return profile(require(id));}
    public UserRepository.User require(long id) {
        UserRepository.User user=users.byId(id);
        if(user==null || !"ACTIVE".equals(user.status())) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,"登录状态失效");
        return user;
    }
    @Transactional public Profile update(long id,String name,String gender,LocalDate birthday) {
        require(id);
        name=PasswordRules.username(name);gender=PasswordRules.gender(gender);
        if(birthday!=null && birthday.isAfter(LocalDate.now())) throw new BadRequest("生日不能晚于今天");
        users.update(id,name,gender,birthday);
        return me(id);
    }
    @Transactional public void logout(long id){require(id);users.revoke(id);}
}
