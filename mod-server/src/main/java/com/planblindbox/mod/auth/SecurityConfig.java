package com.planblindbox.mod.auth;

import jakarta.servlet.DispatcherType;
import java.util.Map;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;
import static org.springframework.security.config.Customizer.withDefaults;

@Configuration @EnableWebSecurity
public class SecurityConfig {
    @Bean PasswordEncoder passwordEncoder(){return new BCryptPasswordEncoder(12);}
    // Existing administrator authorization stays in ModAdminController.authorize().
    @Bean @Order(1) SecurityFilterChain adminChain(HttpSecurity http) throws Exception {
        return http.securityMatcher("/api/v1/admin/**").csrf(c->c.disable()).cors(withDefaults())
                .sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(a->a.anyRequest().permitAll()).build();
    }
    @Bean @Order(2) SecurityFilterChain userChain(HttpSecurity http) throws Exception {
        http.csrf(c->c.disable()).cors(withDefaults()).httpBasic(c->c.disable()).formLogin(c->c.disable())
            .sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .exceptionHandling(e->e.authenticationEntryPoint((req,res,ex)->{
                res.setStatus(401);res.setContentType("application/json;charset=UTF-8");
                res.getWriter().write("{\"code\":\"UNAUTHORIZED\",\"message\":\"请先登录\"}");
            }).accessDeniedHandler((req,res,ex)->{
                res.setStatus(403);res.setContentType("application/json;charset=UTF-8");
                res.getWriter().write("{\"code\":\"FORBIDDEN\",\"message\":\"权限不足\"}");
            }))
            .authorizeHttpRequests(a->a
               .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
               .requestMatchers(HttpMethod.OPTIONS,"/**").permitAll()
               .requestMatchers(HttpMethod.POST,"/api/v1/auth/register","/api/v1/auth/login",
                       "/api/v1/auth/password/forgot","/api/v1/auth/password/reset").permitAll()
               .requestMatchers(HttpMethod.GET,"/api/v1/avatars/**").permitAll()
               .requestMatchers(HttpMethod.POST,"/api/v1/mods/*/versions/*/download").authenticated()
               .requestMatchers(HttpMethod.GET,"/api/v1/mods/*/versions/*/manifest").authenticated()
               .requestMatchers(HttpMethod.GET,"/api/v1/mods","/api/v1/mods/ranking","/api/v1/mods/*").permitAll()
               .requestMatchers("/api/v1/me","/api/v1/me/**","/api/v1/auth/logout").authenticated()
               .anyRequest().denyAll())
            .oauth2ResourceServer(o->o.jwt(withDefaults()));
        return http.build();
    }
}
