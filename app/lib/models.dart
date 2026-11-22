/// Plain data types mirroring the server API. Note what is NOT here:
/// no wallet address and no phone number ever appear in these models —
/// the $name is the only identifier the UI knows.
class Profile {
  final int userId;
  final String cashtag; // without the leading $
  final String encPubkey; // base64 X25519 public key
  final double createdAt;
  final double? cashtagChangedAt;
  final bool? online;
  final double? lastSeen;
  final bool? hasWallet;
  final bool? hasPhone;

  Profile({
    required this.userId,
    required this.cashtag,
    required this.encPubkey,
    required this.createdAt,
    this.cashtagChangedAt,
    this.online,
    this.lastSeen,
    this.hasWallet,
    this.hasPhone,
  });

  String get display => '\$$cashtag';

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        userId: j['user_id'] as int,
        cashtag: j['cashtag'] as String,
        encPubkey: j['enc_pubkey'] as String,
        createdAt: (j['created_at'] as num).toDouble(),
        cashtagChangedAt: (j['cashtag_changed_at'] as num?)?.toDouble(),
        online: j['online'] as bool?,
        lastSeen: (j['last_seen'] as num?)?.toDouble(),
        hasWallet: j['has_wallet'] as bool?,
        hasPhone: j['has_phone'] as bool?,
      );

  Profile copyWith({bool? online, double? lastSeen, String? cashtag,
      double? cashtagChangedAt}) =>
      Profile(
        userId: userId,
        cashtag: cashtag ?? this.cashtag,
        encPubkey: encPubkey,
        createdAt: createdAt,
        cashtagChangedAt: cashtagChangedAt ?? this.cashtagChangedAt,
        online: online ?? this.online,
        lastSeen: lastSeen ?? this.lastSeen,
        hasWallet: hasWallet,
        hasPhone: hasPhone,
      );
}

class GroupInfo {
  final int id;
  final String name;
  final List<Profile> members;

  GroupInfo({required this.id, required this.name, required this.members});

  factory GroupInfo.fromJson(Map<String, dynamic> j) => GroupInfo(
        id: j['id'] as int,
        name: j['name'] as String,
        members: (j['members'] as List)
            .map((m) => Profile.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

/// One decrypted chat message, held locally. Payload kinds: text, photo,
/// voice (group_key payloads are consumed by the store, never shown).
class ChatMessage {
  int? serverId;
  final int senderId;
  final String senderCashtag;
  final bool mine;
  final String kind; // text | photo | voice
  final String? text;
  final String? blobId;
  final String? blobKeyB64; // secretbox key for the blob
  final int? viewLimit;
  final int? durationMs;
  final DateTime createdAt;
  final DateTime? expiresAt; // self-destruct deadline (local copy)

  ChatMessage({
    this.serverId,
    required this.senderId,
    required this.senderCashtag,
    required this.mine,
    required this.kind,
    this.text,
    this.blobId,
    this.blobKeyB64,
    this.viewLimit,
    this.durationMs,
    required this.createdAt,
    this.expiresAt,
  });

  bool get expired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  Map<String, dynamic> toJson() => {
        'serverId': serverId,
        'senderId': senderId,
        'senderCashtag': senderCashtag,
        'mine': mine,
        'kind': kind,
        'text': text,
        'blobId': blobId,
        'blobKeyB64': blobKeyB64,
        'viewLimit': viewLimit,
        'durationMs': durationMs,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt?.millisecondsSinceEpoch,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        serverId: j['serverId'] as int?,
        senderId: j['senderId'] as int,
        senderCashtag: j['senderCashtag'] as String,
        mine: j['mine'] as bool,
        kind: j['kind'] as String,
        text: j['text'] as String?,
        blobId: j['blobId'] as String?,
        blobKeyB64: j['blobKeyB64'] as String?,
        viewLimit: j['viewLimit'] as int?,
        durationMs: j['durationMs'] as int?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int),
        expiresAt: j['expiresAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['expiresAt'] as int),
      );
}

/// A 1-to-1 (key 'u<userId>') or group (key 'g<groupId>') conversation.
class Conversation {
  final String key;
  final String title; // $name or group name
  final int? peerUserId;
  final int? groupId;
  final List<ChatMessage> messages = [];
  int unread = 0;

  Conversation({required this.key, required this.title, this.peerUserId,
      this.groupId});

  bool get isGroup => groupId != null;

  DateTime? get lastActivity =>
      messages.isEmpty ? null : messages.last.createdAt;

  String get preview {
    if (messages.isEmpty) return '';
    final m = messages.last;
    switch (m.kind) {
      case 'photo':
        return '📷 Photo';
      case 'voice':
        return '🎤 Voice message';
      default:
        return m.text ?? '';
    }
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'peerUserId': peerUserId,
        'groupId': groupId,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final c = Conversation(
      key: j['key'] as String,
      title: j['title'] as String,
      peerUserId: j['peerUserId'] as int?,
      groupId: j['groupId'] as int?,
    );
    c.messages.addAll((j['messages'] as List)
        .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)));
    return c;
  }
}
