import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

/// EVM wallet login: sign the server's nonce message with personal_sign.
///
/// Phase 1 route: the user imports the wallet's private key into the app
/// (kept in the OS keystore via flutter_secure_storage). WalletConnect /
/// external-wallet signing is a later phase. The address itself is never
/// shown in the UI — it stays an internal login credential.
class WalletService {
  final EthPrivateKey _credentials;

  WalletService._(this._credentials);

  factory WalletService.fromPrivateKeyHex(String hex) {
    var h = hex.trim();
    if (h.startsWith('0x')) h = h.substring(2);
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(h)) {
      throw const FormatException('Private key must be 64 hex characters');
    }
    return WalletService._(EthPrivateKey.fromHex(h));
  }

  static WalletService createRandom() =>
      WalletService._(EthPrivateKey.createRandom(Random.secure()));

  String get address => _credentials.address.with0x;

  String get privateKeyHex => '0x${_credentials.privateKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  /// personal_sign (EIP-191) over the server's challenge text.
  String signMessage(String message) {
    final sig = _credentials.signPersonalMessageToUint8List(
        Uint8List.fromList(utf8.encode(message)));
    return '0x${sig.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
