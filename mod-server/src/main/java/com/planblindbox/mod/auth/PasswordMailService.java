package com.planblindbox.mod.auth;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

@Service
public class PasswordMailService {
    private static final Logger LOG=LoggerFactory.getLogger(PasswordMailService.class);
    private final ObjectProvider<JavaMailSender> sender;
    private final String from;
    private final String host;
    public PasswordMailService(ObjectProvider<JavaMailSender> sender,
          @Value("${auth.reset.mail-from:}") String from,
          @Value("${spring.mail.host:}") String host) {
        this.sender=sender;this.from=from;this.host=host;
    }
    public boolean configured(){return !from.isBlank() && !host.isBlank() && sender.getIfAvailable()!=null;}
    @Async("mailExecutor") public void sendCode(String email,String code){
        try {
            SimpleMailMessage m=new SimpleMailMessage();m.setFrom(from);m.setTo(email);
            m.setSubject("PlanBlindBox 重置密码验证码");
            m.setText("你的密码重置验证码是："+code+"\n10分钟内有效。若非本人操作，请忽略。不要把验证码告诉他人。");
            sender.getObject().send(m);
        } catch(Exception e) {LOG.error("密码重置邮件发送失败（已隐藏邮箱与验证码）",e.getClass().getSimpleName());}
    }
    @Async("mailExecutor") public void changed(String email){
        try {
            SimpleMailMessage m=new SimpleMailMessage();m.setFrom(from);m.setTo(email);
            m.setSubject("PlanBlindBox 密码修改通知");
            m.setText("你的 PlanBlindBox 登录密码已重置。若不是你本人操作，请尽快联系应用维护者。");
            sender.getObject().send(m);
        } catch(Exception e) {LOG.error("密码变更通知发送失败（已隐藏邮箱）");}
    }
}
