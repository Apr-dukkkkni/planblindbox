import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.HexFormat;

/** Standalone JDK 17+ tool. Private key is generated on the user's computer. */
public class PublisherSigner {
    private static final String PRIVATE_NAME = "publisher-private.pkcs8";
    private static final String PUBLIC_NAME = "publisher-public.x509";

    public static void main(String[] args) throws Exception {
        if (args.length < 2 || args.length > 3) {
            System.err.println("Usage: java PublisherSigner.java init <keyDirectory> | sign <keyDirectory> <manifest.json>");
            System.exit(2);
        }
        String action = args[0];
        Path keyDir = Path.of(args[1]).toAbsolutePath();
        Path privPath = keyDir.resolve(PRIVATE_NAME);
        Path pubPath = keyDir.resolve(PUBLIC_NAME);
        if ("init".equals(action) && args.length == 2) {
            Files.createDirectories(keyDir);
            if (Files.exists(privPath) || Files.exists(pubPath)) {
                throw new IllegalStateException("Key files already exist; refusing to overwrite. Directory: " + keyDir);
            }
            KeyPairGenerator generator = KeyPairGenerator.getInstance("Ed25519");
            KeyPair pair = generator.generateKeyPair();
            Files.write(privPath, pair.getPrivate().getEncoded(), StandardOpenOption.CREATE_NEW);
            Files.write(pubPath, pair.getPublic().getEncoded(), StandardOpenOption.CREATE_NEW);
            System.out.println("keyId=" + sha256Hex(Files.readAllBytes(pubPath)));
            System.out.println("createdKeyDirectory=" + keyDir);
            return;
        }
        if ("sign".equals(action) && args.length == 3) {
            byte[] publicBytes = Files.readAllBytes(pubPath);
            byte[] privateBytes = Files.readAllBytes(privPath);
            byte[] rawManifest = Files.readAllBytes(Path.of(args[2]));
            PrivateKey privateKey = KeyFactory.getInstance("Ed25519")
                    .generatePrivate(new PKCS8EncodedKeySpec(privateBytes));
            Signature signer = Signature.getInstance("Ed25519");
            signer.initSign(privateKey);
            signer.update(rawManifest);
            byte[] signature = signer.sign();
            Signature verifier = Signature.getInstance("Ed25519");
            verifier.initVerify(KeyFactory.getInstance("Ed25519").generatePublic(new X509EncodedKeySpec(publicBytes)));
            verifier.update(rawManifest);
            if (!verifier.verify(signature)) {
                throw new IllegalStateException("Key pair mismatch: local signature self-check failed");
            }
            System.out.println("keyId=" + sha256Hex(publicBytes));
            System.out.println("manifestSha256=" + sha256Hex(rawManifest));
            System.out.println("signatureBase64=" + Base64.getEncoder().encodeToString(signature));
            System.out.println("signatureVerified=true");
            return;
        }
        throw new IllegalArgumentException("Unsupported action or argument count: " + action);
    }

    private static String sha256Hex(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }
}
