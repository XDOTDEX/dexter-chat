import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/x25519.dart';

import 'package:dexter_chat/services/crypto.dart';

/// Cross-implementation vectors generated with PyNaCl (the Python
/// reference client). If these pass, the Dart crypto is byte-compatible
/// with the server-side test client — same X25519 keys, same NaCl box
/// and secretbox constructions.
const _aliceSk = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';
const _alicePk = 'B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9/AsrhtHHw=';
const _bobSk = 'ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=';
const _bobPk = 'WGmv9FBUlzLLqu1eXfmzCm2jHLDldCutWtShp2jxpns=';
const _nonce = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYX';
const _plaintext = 'hello dexterchat';
const _boxCiphertext = 'n3rbZxOcLJYKeDWYcIPtKHqQtzU1HRm3gYYkcZwqcMk=';
const _secretKey = 'ZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXp7fH1+f4CBgoM=';
const _secretCiphertext = 'ftA0SLQLnYJZ2dYa/INNqNpbbXCaHFLPvDki52aNIG8=';

Uint8List _d(String b64) => base64Decode(b64);

void main() {
  test('identity: private key bytes derive PyNaCl public keys', () {
    expect(Identity.fromPrivateKeyB64(_aliceSk).publicKeyB64, _alicePk);
    expect(Identity.fromPrivateKeyB64(_bobSk).publicKeyB64, _bobPk);
  });

  test('box: decrypts PyNaCl ciphertext', () {
    final bob = Identity.fromPrivateKeyB64(_bobSk);
    final plain =
        BoxCipher.decrypt(bob, _alicePk, _boxCiphertext, _nonce);
    expect(utf8.decode(plain), _plaintext);
  });

  test('box: fixed-nonce encryption equals PyNaCl byte-for-byte', () {
    final box = Box(
      myPrivateKey: PrivateKey(_d(_aliceSk)),
      theirPublicKey: PublicKey(_d(_bobPk)),
    );
    final enc = box.encrypt(utf8.encode(_plaintext), nonce: _d(_nonce));
    expect(base64Encode(enc.cipherText.asTypedList), _boxCiphertext);
    expect(base64Encode(enc.nonce.asTypedList), _nonce);
  });

  test('box: Dart roundtrip via app helpers', () {
    final alice = Identity.fromPrivateKeyB64(_aliceSk);
    final bob = Identity.fromPrivateKeyB64(_bobSk);
    final enc = BoxCipher.encrypt(alice, _bobPk, utf8.encode('roundtrip'));
    final plain =
        BoxCipher.decrypt(bob, _alicePk, enc['ciphertext']!, enc['nonce']!);
    expect(utf8.decode(plain), 'roundtrip');
  });

  test('secretbox: decrypts PyNaCl ciphertext', () {
    final plain =
        SecretCipher.decrypt(_d(_secretKey), _secretCiphertext, _nonce);
    expect(utf8.decode(plain), _plaintext);
  });

  test('secretbox: fixed-nonce encryption equals PyNaCl byte-for-byte', () {
    final enc = SecretBox(_d(_secretKey))
        .encrypt(utf8.encode(_plaintext), nonce: _d(_nonce));
    expect(base64Encode(enc.cipherText.asTypedList), _secretCiphertext);
  });
}
