package com.planblindbox.mod.auth;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Repository;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Repository
public class UserRepository {
    public record User(long id, String username, String email, String passwordHash,
            String gender, String avatar, LocalDate birthday, String status, long credentialVersion) {}
    private final JdbcTemplate jdbc;
    public UserRepository(JdbcTemplate jdbc) { this.jdbc=jdbc; }
    public record OpaqueCredential(long userId, String opaqueUserIdentifier,
            String registrationRecord, String wrappedAmkJson, String serverStaticPublicKey) {}
    private final org.springframework.jdbc.core.RowMapper<User> mapper = (rs,n) -> new User(
        rs.getLong("user_id"),rs.getString("username"),rs.getString("email"),rs.getString("password_hash"),
        rs.getString("gender"),rs.getString("avatar"),rs.getObject("birthday",LocalDate.class),
        rs.getString("status"),rs.getLong("credential_version"));
    public User byEmail(String email) {
        List<User> list=jdbc.query("SELECT * FROM community_user WHERE email=?",mapper,email);
        return list.isEmpty()?null:list.get(0);
    }
    public User byId(long id) {
        List<User> list=jdbc.query("SELECT * FROM community_user WHERE user_id=?",mapper,id);
        return list.isEmpty()?null:list.get(0);
    }
    public User lockById(long id) {
        List<User> list=jdbc.query("SELECT * FROM community_user WHERE user_id=? FOR UPDATE",mapper,id);
        return list.isEmpty()?null:list.get(0);
    }
    public User lockEmail(String email) {
        List<User> list=jdbc.query("SELECT * FROM community_user WHERE email=? FOR UPDATE",mapper,email);
        return list.isEmpty()?null:list.get(0);
    }
    public long insert(String name,String email,String hash,String gender) {
        KeyHolder holder=new GeneratedKeyHolder();
        jdbc.update(connection->{
            PreparedStatement ps=connection.prepareStatement(
                "INSERT INTO community_user(username,email,password_hash,gender,avatar) VALUES (?,?,?,?,NULL)",Statement.RETURN_GENERATED_KEYS);
            ps.setString(1,name);ps.setString(2,email);ps.setString(3,hash);ps.setString(4,gender);return ps;
        },holder);
        return holder.getKey().longValue();
    }
    public long insertOpaque(String name,String email,String gender) {
        KeyHolder holder=new GeneratedKeyHolder();
        jdbc.update(connection->{
            PreparedStatement ps=connection.prepareStatement(
                "INSERT INTO community_user(username,email,password_hash,gender,avatar) VALUES (?,?,NULL,?,NULL)",
                Statement.RETURN_GENERATED_KEYS);
            ps.setString(1,name);ps.setString(2,email);ps.setString(3,gender);return ps;
        },holder);
        return holder.getKey().longValue();
    }
    public void insertOpaqueCredential(long id,String opaqueIdentifier,String record,String wrappedAmk,String publicKey) {
        jdbc.update("INSERT INTO user_opaque_credential(user_id,opaque_user_identifier,registration_record,wrapped_amk_json,server_static_public_key) VALUES(?,?,?,?,?)",
            id,opaqueIdentifier,record,wrappedAmk,publicKey);
    }
    public OpaqueCredential opaqueCredential(long id) {
        List<OpaqueCredential> rows=jdbc.query(
            "SELECT user_id,opaque_user_identifier,registration_record,wrapped_amk_json,server_static_public_key FROM user_opaque_credential WHERE user_id=?",
            (rs,n)->new OpaqueCredential(rs.getLong(1),rs.getString(2),rs.getString(3),rs.getString(4),rs.getString(5)),id);
        return rows.isEmpty()?null:rows.get(0);
    }
    public OpaqueCredential opaqueCredentialForUpdate(long id) {
        List<OpaqueCredential> rows=jdbc.query(
            "SELECT user_id,opaque_user_identifier,registration_record,wrapped_amk_json,server_static_public_key FROM user_opaque_credential WHERE user_id=? FOR UPDATE",
            (rs,n)->new OpaqueCredential(rs.getLong(1),rs.getString(2),rs.getString(3),rs.getString(4),rs.getString(5)),id);
        return rows.isEmpty()?null:rows.get(0);
    }
    public int replaceOpaqueCredentialAndRevoke(long id, String opaqueIdentifier,
            String registrationRecord, String wrappedAmk, String publicKey) {
        int changed = jdbc.update(
            "UPDATE user_opaque_credential SET registration_record=?,wrapped_amk_json=?," +
            "server_static_public_key=?,updated_at=CURRENT_TIMESTAMP " +
            "WHERE user_id=? AND opaque_user_identifier=?",
            registrationRecord, wrappedAmk, publicKey, id, opaqueIdentifier);
        if (changed == 1) {
            jdbc.update("UPDATE community_user SET credential_version=credential_version+1 WHERE user_id=?", id);
        }
        return changed;
    }
    public void loginAt(long id) { jdbc.update("UPDATE community_user SET last_login_at=CURRENT_TIMESTAMP WHERE user_id=?",id); }
    public void update(long id,String name,String gender,LocalDate birthday) {
        jdbc.update("UPDATE community_user SET username=?,gender=?,birthday=? WHERE user_id=?",name,gender,birthday,id);
    }
    public void avatar(long id,String avatar) {jdbc.update("UPDATE community_user SET avatar=? WHERE user_id=?",avatar,id);}
    public void revoke(long id) {jdbc.update("UPDATE community_user SET credential_version=credential_version+1 WHERE user_id=?",id);}
    public void passwordAndRevoke(long id,String hash) {
        jdbc.update("UPDATE community_user SET password_hash=?,credential_version=credential_version+1 WHERE user_id=?",hash,id);
    }
}
