import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../models.dart';
import 'api.dart';
import 'crypto.dart';
import 'wallet.dart';

class PhotoResult {
  final Uint8List bytes;
  final int? viewsLeft;
  final int? viewLimit;
  PhotoResult(this.bytes, {this.viewsLeft, this.viewLimit});
}

/// Central app state: session, identity keys, conversations, live socket.
///
/// Decrypted messages live in memory and in a JSON file in the app's
/// private documents directory (OS-sandboxed). Group keys and the
/// identity private key live in the platform keystore (secure storage).
/// The server only ever sees ciphertext.
class AppState extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  late ApiClient api;

  Identity? identity;
  Profile? me;
  bool ready = false;
  bool get isLoggedIn => me != null && api.token != null;

  final Map<int, Profile> profilesById = {};
  final Map<String, Conversation> conversations = {};
  final Map<int, Uint8List> groupKeys = {};
  final Map<String, Uint8List> _blobCache = {};
  final Map<String, ChatMessage> _pendingEcho = {};
  final List<Map<String, dynamic>> _pendingGroupMsgs = [];

  String? openConversationKey;
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;
  Timer? _cleanupTimer;
  Future<void> _incomingChain = Future.value();
  bool _wsWanted = false;

  List<Conversation> get sortedConversations {
    final list = conversations.values.toList()
      ..sort((a, b) => (b.lastActivity ?? DateTime(2000))
          .compareTo(a.lastActivity ?? DateTime(2000)));
    return list;
  }

  // ------------------------------------------------------------ startup
  Future<void> init() async {
    // The server is fixed (see AppConfig) — a server URL stored by an
    // older build is ignored and dropped.
    api = ApiClient(AppConfig.serverUrl);
    await _storage.delete(key: 'server_url');
    final priv = await _storage.read(key: 'identity_priv');
    if (priv != null) identity = Identity.fromPrivateKeyB64(priv);
    final keys = await _storage.read(key: 'group_keys');
    if (keys != null) {
      (jsonDecode(keys) as Map<String, dynamic>).forEach((k, v) {
        groupKeys[int.parse(k)] = base64Decode(v as String);
      });
    }
    await _loadChats();
    final token = await _storage.read(key: 'session_token');
    if (token != null && identity != null) {
      api.token = token;
      try {
        me = await api.me();
        profilesById[me!.userId] = me!;
        await _syncGroups();
        connectSocket();
      } catch (_) {
        api.token = null; // stale token — back to auth screen
      }
    }
    _cleanupTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_purgeExpiredLocal()) {
        _persist();
        notifyListeners();
      }
    });
    ready = true;
    notifyListeners();
  }

  Future<Identity> _ensureIdentity() async {
    if (identity != null) return identity!;
    identity = Identity.generate();
    await _storage.write(
        key: 'identity_priv', value: identity!.privateKeyB64);
    return identity!;
  }

  // ------------------------------------------------------------ auth
  Future<void> walletAuth(WalletService wallet,
      {String? inviteCode, String? cashtag}) async {
    final id = await _ensureIdentity();
    final challenge = await api.walletChallenge(wallet.address);
    final signature = wallet.signMessage(challenge);
    final res = await api.walletVerify(
      address: wallet.address,
      signature: signature,
      inviteCode: inviteCode,
      cashtag: cashtag,
      encPubkey: inviteCode != null ? id.publicKeyB64 : null,
    );
    await _acceptSession(res, walletPrivateKey: wallet.privateKeyHex);
  }

  Future<Map<String, dynamic>> phoneRequest(String phone) =>
      api.phoneRequest(phone);

  Future<void> phoneVerify(String phone, String code,
      {String? inviteCode, String? cashtag}) async {
    final id = await _ensureIdentity();
    final res = await api.phoneVerify(
      phone: phone,
      code: code,
      inviteCode: inviteCode,
      cashtag: cashtag,
      encPubkey: inviteCode != null ? id.publicKeyB64 : null,
    );
    await _acceptSession(res);
  }

  Future<void> _acceptSession(Map<String, dynamic> res,
      {String? walletPrivateKey}) async {
    api.token = res['token'] as String;
    me = Profile.fromJson(res['user'] as Map<String, dynamic>);
    profilesById[me!.userId] = me!;
    await _storage.write(key: 'session_token', value: api.token);
    if (walletPrivateKey != null) {
      await _storage.write(key: 'wallet_privkey', value: walletPrivateKey);
    }
    await _syncGroups();
    connectSocket();
    notifyListeners();
  }

  Future<void> refreshMe() async {
    me = await api.me();
    profilesById[me!.userId] = me!;
    notifyListeners();
  }

  Future<void> changeCashtag(String newCashtag) async {
    me = await api.changeCashtag(newCashtag);
    profilesById[me!.userId] = me!;
    notifyListeners();
  }

  Future<String?> savedWalletKey() => _storage.read(key: 'wallet_privkey');

  Future<void> logout() async {
    _wsWanted = false;
    await _wsSub?.cancel();
    await _ws?.sink.close();
    _ws = null;
    api.token = null;
    me = null;
    await _storage.delete(key: 'session_token');
    notifyListeners();
  }

  /// Full wipe: identity, keys, chats — the account itself stays on the
  /// server, but this device forgets everything (new device = new keys).
  Future<void> resetDevice() async {
    await logout();
    await _storage.deleteAll();
    conversations.clear();
    groupKeys.clear();
    identity = null;
    final f = await _chatsFile();
    if (await f.exists()) await f.delete();
    notifyListeners();
  }

  // ------------------------------------------------------------ profiles
  Future<Profile> profileFor(int userId, {String? cashtag}) async {
    final cached = profilesById[userId];
    if (cached != null) return cached;
    if (cashtag != null) {
      final p = await api.lookup(cashtag);
      profilesById[p.userId] = p;
      return p;
    }
    throw StateError('unknown user $userId');
  }

  Future<Profile> lookup(String cashtag) async {
    final p = await api.lookup(cashtag);
    profilesById[p.userId] = p;
    return p;
  }

  // ------------------------------------------------------------ groups
  Future<void> _syncGroups() async {
    try {
      for (final g in await api.groups()) {
        for (final m in g.members) {
          profilesById[m.userId] = m;
        }
        conversations.putIfAbsent(
            'g${g.id}',
            () => Conversation(
                key: 'g${g.id}', title: g.name, groupId: g.id));
      }
    } catch (_) {
      /* offline at startup — groups appear when messages arrive */
    }
  }

  Future<Conversation> createGroup(String name, List<String> cashtags) async {
    final info = await api.createGroup(name, cashtags);
    for (final m in info.members) {
      profilesById[m.userId] = m;
    }
    final key = SecretCipher.newKey();
    groupKeys[info.id] = key;
    await _saveGroupKeys();
    // Distribute the group key to each member over the 1-to-1 channels.
    for (final member in info.members) {
      if (member.userId == me!.userId) continue;
      final payload = utf8.encode(jsonEncode({
        'kind': 'group_key',
        'group_id': info.id,
        'key': base64Encode(key),
      }));
      final enc = BoxCipher.encrypt(identity!, member.encPubkey, payload);
      await api.sendMessage({
        'to_cashtag': member.cashtag,
        'ciphertext': enc['ciphertext'],
        'nonce': enc['nonce'],
      });
    }
    final conv = Conversation(
        key: 'g${info.id}', title: info.name, groupId: info.id);
    conversations[conv.key] = conv;
    _persist();
    notifyListeners();
    return conv;
  }

  Future<void> _saveGroupKeys() async {
    final map = {
      for (final e in groupKeys.entries) '${e.key}': base64Encode(e.value)
    };
    await _storage.write(key: 'group_keys', value: jsonEncode(map));
  }

  // ------------------------------------------------------------ socket
  void connectSocket() {
    _wsWanted = true;
    _reconnectTimer?.cancel();
    final wsUrl = '${api.baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/ws';
    final channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _ws = channel;
    channel.sink.add(jsonEncode({'type': 'auth', 'token': api.token}));
    _wsSub = channel.stream.listen(
      (raw) => _incomingChain =
          _incomingChain.then((_) => _handleFrame(raw as String)),
      onDone: _scheduleReconnect,
      onError: (_) => _scheduleReconnect(),
    );
  }

  void _scheduleReconnect() {
    if (!_wsWanted) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_wsWanted && isLoggedIn) connectSocket();
    });
  }

  Future<void> _handleFrame(String raw) async {
    final frame = jsonDecode(raw) as Map<String, dynamic>;
    switch (frame['type']) {
      case 'message':
        await _onIncoming(frame['message'] as Map<String, dynamic>);
        break;
      case 'sent':
        final echo = _pendingEcho.remove(frame['client_ref']);
        final ids = (frame['message_ids'] as List?)?.cast<int>() ?? [];
        if (echo != null && ids.isNotEmpty) echo.serverId = ids.first;
        _persist();
        notifyListeners();
        break;
      case 'expired':
        _removeByServerId(frame['message_id'] as int);
        break;
      case 'presence':
        final uid = frame['user_id'] as int;
        final cached = profilesById[uid];
        if (cached != null) {
          profilesById[uid] = cached.copyWith(
            online: frame['online'] as bool,
            lastSeen: (frame['last_seen'] as num?)?.toDouble(),
          );
          notifyListeners();
        }
        break;
    }
  }

  Future<void> _ack(int messageId) async {
    if (_ws != null) {
      _ws!.sink.add(jsonEncode({'type': 'ack', 'message_id': messageId}));
    } else {
      try {
        await api.ack(messageId);
      } catch (_) {}
    }
  }

  Future<void> _onIncoming(Map<String, dynamic> msg) async {
    final serverId = msg['id'] as int;
    final groupId = msg['group_id'] as int?;
    final senderId = msg['sender_id'] as int;
    final senderCashtag = msg['sender_cashtag'] as String;
    final expiresAt = (msg['expires_at'] as num?) == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            ((msg['expires_at'] as num) * 1000).round());
    try {
      Map<String, dynamic> payload;
      if (groupId != null) {
        final key = groupKeys[groupId];
        if (key == null) {
          _pendingGroupMsgs.add(msg); // key distribution may arrive later
          return;
        }
        payload = jsonDecode(utf8.decode(SecretCipher.decrypt(
            key, msg['ciphertext'] as String, msg['nonce'] as String)));
      } else {
        final sender = await profileFor(senderId, cashtag: senderCashtag);
        payload = jsonDecode(utf8.decode(BoxCipher.decrypt(identity!,
            sender.encPubkey, msg['ciphertext'] as String,
            msg['nonce'] as String)));
      }

      if (payload['kind'] == 'group_key') {
        final gid = payload['group_id'] as int;
        groupKeys[gid] = base64Decode(payload['key'] as String);
        await _saveGroupKeys();
        try {
          final info = await api.group(gid);
          for (final m in info.members) {
            profilesById[m.userId] = m;
          }
          conversations.putIfAbsent(
              'g$gid',
              () => Conversation(
                  key: 'g$gid', title: info.name, groupId: gid));
        } catch (_) {}
        await _ack(serverId);
        // Retry anything that was waiting for this key.
        final waiting = List.of(_pendingGroupMsgs);
        _pendingGroupMsgs.clear();
        for (final m in waiting) {
          await _onIncoming(m);
        }
        notifyListeners();
        return;
      }

      final conv = await _conversationFor(msg, payload);
      conv.messages.add(ChatMessage(
        serverId: serverId,
        senderId: senderId,
        senderCashtag: senderCashtag,
        mine: false,
        kind: payload['kind'] as String,
        text: payload['text'] as String?,
        blobId: payload['blob_id'] as String?,
        blobKeyB64: payload['key'] as String?,
        viewLimit: payload['view_limit'] as int?,
        durationMs: payload['duration_ms'] as int?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            ((msg['created_at'] as num) * 1000).round()),
        expiresAt: expiresAt,
      ));
      if (openConversationKey != conv.key) conv.unread++;
      await _ack(serverId);
      _persist();
      notifyListeners();
    } catch (e) {
      debugPrint('incoming message failed: $e');
    }
  }

  Future<Conversation> _conversationFor(
      Map<String, dynamic> msg, Map<String, dynamic> payload) async {
    final groupId = msg['group_id'] as int?;
    if (groupId != null) {
      var conv = conversations['g$groupId'];
      if (conv == null) {
        final info = await api.group(groupId);
        conv = Conversation(
            key: 'g$groupId', title: info.name, groupId: groupId);
        conversations[conv.key] = conv;
      }
      return conv;
    }
    final senderId = msg['sender_id'] as int;
    final senderCashtag = msg['sender_cashtag'] as String;
    return conversations.putIfAbsent(
        'u$senderId',
        () => Conversation(
            key: 'u$senderId',
            title: '\$$senderCashtag',
            peerUserId: senderId));
  }

  void _removeByServerId(int serverId) {
    for (final conv in conversations.values) {
      final before = conv.messages.length;
      conv.messages.removeWhere((m) => m.serverId == serverId);
      if (conv.messages.length != before) {
        _persist();
        notifyListeners();
        return;
      }
    }
  }

  bool _purgeExpiredLocal() {
    var changed = false;
    for (final conv in conversations.values) {
      final before = conv.messages.length;
      conv.messages.removeWhere((m) => m.expired);
      changed = changed || conv.messages.length != before;
    }
    return changed;
  }

  // ------------------------------------------------------------ sending
  Future<Conversation> openChatWith(String cashtag) async {
    final p = await lookup(cashtag.replaceAll('\$', ''));
    final conv = conversations.putIfAbsent(
        'u${p.userId}',
        () => Conversation(
            key: 'u${p.userId}', title: p.display, peerUserId: p.userId));
    notifyListeners();
    return conv;
  }

  Map<String, String> _encryptFor(
      Conversation conv, List<int> payload, Profile? peer) {
    if (conv.isGroup) {
      final key = groupKeys[conv.groupId];
      if (key == null) {
        throw StateError('group key not received yet');
      }
      return SecretCipher.encrypt(key, payload);
    }
    return BoxCipher.encrypt(identity!, peer!.encPubkey, payload);
  }

  Future<void> _sendPayload(Conversation conv, Map<String, dynamic> payload,
      {int? ttlSeconds}) async {
    Profile? peer;
    if (!conv.isGroup) peer = await profileFor(conv.peerUserId!);
    final enc = _encryptFor(
        conv, utf8.encode(jsonEncode(payload)), peer);
    final local = ChatMessage(
      senderId: me!.userId,
      senderCashtag: me!.cashtag,
      mine: true,
      kind: payload['kind'] as String,
      text: payload['text'] as String?,
      blobId: payload['blob_id'] as String?,
      blobKeyB64: payload['key'] as String?,
      viewLimit: payload['view_limit'] as int?,
      durationMs: payload['duration_ms'] as int?,
      createdAt: DateTime.now(),
      expiresAt: ttlSeconds == null
          ? null
          : DateTime.now().add(Duration(seconds: ttlSeconds)),
    );
    conv.messages.add(local);
    _persist();
    notifyListeners();

    final clientRef = 'c${DateTime.now().microsecondsSinceEpoch}';
    _pendingEcho[clientRef] = local;
    final frame = <String, dynamic>{
      'type': 'send',
      'client_ref': clientRef,
      'ciphertext': enc['ciphertext'],
      'nonce': enc['nonce'],
      if (ttlSeconds != null) 'ttl_seconds': ttlSeconds,
      if (conv.isGroup)
        'group_id': conv.groupId
      else
        'to_cashtag': peer!.cashtag,
    };
    if (_ws != null) {
      _ws!.sink.add(jsonEncode(frame));
    } else {
      final created = await api.sendMessage(frame..remove('type')
        ..remove('client_ref'));
      if (created.isNotEmpty) local.serverId = created.first['id'] as int;
      _pendingEcho.remove(clientRef);
      _persist();
      notifyListeners();
    }
  }

  Future<void> sendText(Conversation conv, String text,
          {int? ttlSeconds}) =>
      _sendPayload(conv, {'kind': 'text', 'text': text},
          ttlSeconds: ttlSeconds);

  Future<void> sendPhoto(Conversation conv, Uint8List bytes,
      {required int viewLimit, int? ttlSeconds}) async {
    final key = SecretCipher.newKey();
    final enc = SecretCipher.encrypt(key, bytes);
    final blob = await api.uploadBlob({
      'kind': 'photo',
      'ciphertext': enc['ciphertext'],
      'nonce': enc['nonce'],
      if (conv.isGroup)
        'group_id': conv.groupId
      else
        'recipients': [(await profileFor(conv.peerUserId!)).cashtag],
      'view_limit': viewLimit,
      if (ttlSeconds != null) 'ttl_seconds': ttlSeconds,
    });
    final blobId = blob['blob_id'] as String;
    _blobCache[blobId] = bytes; // sender keeps a local copy for preview
    await _sendPayload(conv, {
      'kind': 'photo',
      'blob_id': blobId,
      'key': base64Encode(key),
      'view_limit': viewLimit,
    }, ttlSeconds: ttlSeconds);
  }

  Future<void> sendVoice(Conversation conv, String filePath, int durationMs,
      {int? ttlSeconds}) async {
    final bytes = await File(filePath).readAsBytes();
    final key = SecretCipher.newKey();
    final enc = SecretCipher.encrypt(key, bytes);
    final blob = await api.uploadBlob({
      'kind': 'voice',
      'ciphertext': enc['ciphertext'],
      'nonce': enc['nonce'],
      if (conv.isGroup)
        'group_id': conv.groupId
      else
        'recipients': [(await profileFor(conv.peerUserId!)).cashtag],
      if (ttlSeconds != null) 'ttl_seconds': ttlSeconds,
    });
    final blobId = blob['blob_id'] as String;
    _blobCache[blobId] = bytes;
    await _sendPayload(conv, {
      'kind': 'voice',
      'blob_id': blobId,
      'key': base64Encode(key),
      'duration_ms': durationMs,
    }, ttlSeconds: ttlSeconds);
  }

  // ------------------------------------------------------------ blobs in
  Future<PhotoResult> fetchPhoto(ChatMessage msg) async {
    final cached = _blobCache[msg.blobId];
    if (cached != null && msg.mine) {
      return PhotoResult(cached, viewLimit: msg.viewLimit);
    }
    final res = await api.fetchBlob(msg.blobId!);
    final plain = SecretCipher.decrypt(base64Decode(msg.blobKeyB64!),
        res['ciphertext'] as String, res['nonce'] as String);
    return PhotoResult(plain,
        viewsLeft: res['views_left'] as int?,
        viewLimit: res['view_limit'] as int?);
  }

  Future<Uint8List> fetchVoice(ChatMessage msg) async {
    final cached = _blobCache[msg.blobId];
    if (cached != null) return cached;
    final res = await api.fetchBlob(msg.blobId!);
    final plain = SecretCipher.decrypt(base64Decode(msg.blobKeyB64!),
        res['ciphertext'] as String, res['nonce'] as String);
    _blobCache[msg.blobId!] = plain;
    return plain;
  }

  // ------------------------------------------------------------ persistence
  Future<File> _chatsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/chats.json');
  }

  Future<void> _loadChats() async {
    try {
      final f = await _chatsFile();
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString())
          as Map<String, dynamic>;
      for (final c in (data['conversations'] as List)) {
        final conv = Conversation.fromJson(c as Map<String, dynamic>);
        conv.messages.removeWhere((m) => m.expired);
        conversations[conv.key] = conv;
      }
    } catch (_) {
      /* corrupt local history must never block startup */
    }
  }

  Future<void> _persist() async {
    try {
      final f = await _chatsFile();
      await f.writeAsString(jsonEncode({
        'conversations':
            conversations.values.map((c) => c.toJson()).toList(),
      }));
    } catch (_) {}
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _ws?.sink.close();
    super.dispose();
  }
}
