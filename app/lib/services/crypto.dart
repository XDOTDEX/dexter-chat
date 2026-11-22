import 'dart:convert';
import 'dart:math';

import 'package:pinenacl/x25519.dart';

/// End-to-end crypto — the exact same constructions as the Python
/// reference client (PyNaCl), cross-verified by test/crypto_test.dart:
///
/// * identity: X25519 keypair (TweetNaCl via pinenacl)
/// * 1-to-1 messages: NaCl box (X25519 + XSalsa20-Poly1305)
/// * blobs & group messages: NaCl secretbox (XSalsa20-Poly1305)
class Identity {
  final PrivateKey privateKey;

  Identity(this.privateKey);

  PublicKey get publicKey => privateKey.publicKey;

  String get publicKeyB64 => base64Encode(publicKey.asTypedList);

  String get privateKeyB64 => base64Encode(privateKey.asTypedList);

  static Identity generate() => Identity(PrivateKey.generate());

  static Identity fromPrivateKeyB64(String b64) =>
      Identity(PrivateKey(Uint8List.fromList(base64Decode(b64))));
}

class BoxCipher {
  static Map<String, String> encrypt(
      Identity me, String peerPubkeyB64, List<int> payload) {
    final box = Box(
      myPrivateKey: me.privateKey,
      theirPublicKey:
          PublicKey(Uint8List.fromList(base64Decode(peerPubkeyB64))),
    );
    final enc = box.encrypt(Uint8List.fromList(payload));
    return {
      'ciphertext': base64Encode(enc.cipherText.asTypedList),
      'nonce': base64Encode(enc.nonce.asTypedList),
    };
  }

  static Uint8List decrypt(
      Identity me, String peerPubkeyB64, String ctB64, String nonceB64) {
    final box = Box(
      myPrivateKey: me.privateKey,
      theirPublicKey:
          PublicKey(Uint8List.fromList(base64Decode(peerPubkeyB64))),
    );
    return box.decrypt(EncryptedMessage(
      nonce: Uint8List.fromList(base64Decode(nonceB64)),
      cipherText: Uint8List.fromList(base64Decode(ctB64)),
    ));
  }
}

class SecretCipher {
  static Uint8List newKey() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  static Map<String, String> encrypt(Uint8List key, List<int> payload) {
    final enc = SecretBox(key).encrypt(Uint8List.fromList(payload));
    return {
      'ciphertext': base64Encode(enc.cipherText.asTypedList),
      'nonce': base64Encode(enc.nonce.asTypedList),
    };
  }

  static Uint8List decrypt(Uint8List key, String ctB64, String nonceB64) {
    return SecretBox(key).decrypt(EncryptedMessage(
      nonce: Uint8List.fromList(base64Decode(nonceB64)),
      cipherText: Uint8List.fromList(base64Decode(ctB64)),
    ));
  }
}
