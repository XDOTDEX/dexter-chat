import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'photo_viewer.dart';

class ChatScreen extends StatefulWidget {
  final AppState state;
  final Conversation conversation;
  const ChatScreen({super.key, required this.state, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _recorder = AudioRecorder();
  int? _ttlSeconds;
  bool _recording = false;
  DateTime? _recStart;
  String? _recPath;

  AppState get state => widget.state;
  Conversation get conv => widget.conversation;

  static const _ttlOptions = <String, int?>{
    'Off': null,
    '10 seconds': 10,
    '1 minute': 60,
    '1 hour': 3600,
    '1 day': 86400,
  };
  static const _viewLimits = [1, 2, 3, 5, 10];

  @override
  void initState() {
    super.initState();
    state.openConversationKey = conv.key;
    conv.unread = 0;
  }

  @override
  void dispose() {
    if (state.openConversationKey == conv.key) {
      state.openConversationKey = null;
    }
    _text.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    try {
      await state.sendText(conv, text, ttlSeconds: _ttlSeconds);
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _pickTtl() async {
    final picked = await showModalBottomSheet<int?>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Self-destruct timer')),
            for (final e in _ttlOptions.entries)
              ListTile(
                title: Text(e.key),
                trailing: _ttlSeconds == e.value
                    ? const Icon(Icons.check, color: kAccent)
                    : null,
                onTap: () => Navigator.pop(context, e.value),
              ),
          ],
        ),
      ),
    );
    setState(() => _ttlSeconds = picked);
  }

  Future<void> _sendPhoto() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 2048);
    if (picked == null || !mounted) return;
    final limit = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
                title: Text('How many times can they open this photo?')),
            for (final n in _viewLimits)
              ListTile(
                title: Text(n == 1 ? '1 time' : '$n times'),
                onTap: () => Navigator.pop(context, n),
              ),
          ],
        ),
      ),
    );
    if (limit == null) return;
    try {
      final bytes = await picked.readAsBytes();
      await state.sendPhoto(conv, bytes,
          viewLimit: limit, ttlSeconds: _ttlSeconds);
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await _recorder.stop();
      final duration = DateTime.now().difference(_recStart!).inMilliseconds;
      setState(() => _recording = false);
      if (path != null) {
        try {
          await state.sendVoice(conv, path, duration,
              ttlSeconds: _ttlSeconds);
        } catch (e) {
          _snack(e.toString());
        }
      }
      return;
    }
    if (!await _recorder.hasPermission()) {
      _snack('Microphone permission denied');
      return;
    }
    final dir = await getTemporaryDirectory();
    _recPath =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc), path: _recPath!);
    setState(() {
      _recording = true;
      _recStart = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final peer = conv.isGroup
            ? null
            : state.profilesById[conv.peerUserId];
        return Scaffold(
          appBar: AppBar(
            flexibleSpace: gradientAppBarBackground(),
            title: Row(
              children: [
                if (!conv.isGroup) ...[
                  GradientAvatar(label: conv.title, radius: 17),
                  const SizedBox(width: 10),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conv.title, style: const TextStyle(fontSize: 17)),
                    if (peer != null)
                      Text(
                        (peer.online ?? false) ? 'online' : 'offline',
                        style: TextStyle(
                            fontSize: 12,
                            color: (peer.online ?? false)
                                ? Colors.greenAccent
                                : kMuted),
                      ),
                  ],
                ),
              ],
            ),
          ),
          body: VoidBackground(
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: conv.messages.length,
                    itemBuilder: (context, i) {
                      final msg =
                          conv.messages[conv.messages.length - 1 - i];
                      return _bubble(msg);
                    },
                  ),
                ),
                _inputBar(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bubble(ChatMessage msg) {
    final align = msg.mine ? Alignment.centerRight : Alignment.centerLeft;
    // Bubble "tail": the corner nearest the sender stays tight.
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(19),
      topRight: const Radius.circular(19),
      bottomLeft: Radius.circular(msg.mine ? 19 : 5),
      bottomRight: Radius.circular(msg.mine ? 5 : 19),
    );
    Widget content;
    switch (msg.kind) {
      case 'photo':
        content = InkWell(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      PhotoViewer(state: state, message: msg))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock, size: 18),
            const SizedBox(width: 8),
            Text(msg.mine
                ? 'Photo · view limit ${msg.viewLimit ?? '—'}'
                : 'Photo · tap to view'
                    '${msg.viewLimit != null ? ' (${msg.viewLimit} views)' : ''}'),
          ]),
        );
        break;
      case 'voice':
        content = _VoiceBubble(state: state, message: msg);
        break;
      default:
        content = Text(msg.text ?? '');
    }
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          gradient: msg.mine ? kAccentGradient : kPanelGradient,
          borderRadius: radius,
          border: msg.mine
              ? Border.all(color: const Color(0x2EFFFFFF))
              : Border.all(color: const Color(0x12FFFFFF)),
          boxShadow: msg.mine
              ? [
                  BoxShadow(
                    color: kAccent.withValues(alpha: 0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : depthShadow(strength: 0.55),
        ),
        child: Column(
          crossAxisAlignment:
              msg.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (conv.isGroup && !msg.mine)
              Text('\$${msg.senderCashtag}',
                  style: const TextStyle(fontSize: 11, color: kAccent2)),
            content,
            const SizedBox(height: 3),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                '${msg.createdAt.hour.toString().padLeft(2, '0')}:'
                '${msg.createdAt.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.65)),
              ),
              if (msg.mine) ...[
                const SizedBox(width: 4),
                Icon(
                  msg.serverId != null ? Icons.done : Icons.access_time,
                  size: 11,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ],
              if (msg.expiresAt != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.timer,
                    size: 11, color: Colors.white.withValues(alpha: 0.65)),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF151524), Color(0xFF0C0C15)],
          ),
          border: const Border(top: BorderSide(color: Color(0x14FFFFFF))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 14,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(Icons.timer,
                  color: _ttlSeconds != null ? kAccent : kMuted),
              tooltip: 'Self-destruct timer',
              onPressed: _pickTtl,
            ),
            IconButton(
              icon: const Icon(Icons.photo, color: kMuted),
              tooltip: 'Send photo (view-limited)',
              onPressed: _sendPhoto,
            ),
            Expanded(
              child: DepthField(
                radius: 22,
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  decoration: bareFieldDecoration(hintText: 'Message…'),
                  onSubmitted: (_) => _sendText(),
                ),
              ),
            ),
            if (_recording)
              IconButton(
                icon: const Icon(Icons.stop_circle, color: Colors.redAccent),
                tooltip: 'Stop & send voice note',
                onPressed: _toggleRecord,
              )
            else
              IconButton(
                icon: const Icon(Icons.mic, color: kMuted),
                tooltip: 'Record voice note',
                onPressed: _toggleRecord,
              ),
            const SizedBox(width: 2),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: kAccentGradient,
                border: Border.all(color: const Color(0x2EFFFFFF)),
                boxShadow: [
                  BoxShadow(
                    color: kAccent.withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _sendText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceBubble extends StatefulWidget {
  final AppState state;
  final ChatMessage message;
  const _VoiceBubble({required this.state, required this.message});

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final bytes = await widget.state.fetchVoice(widget.message);
      await _player.play(BytesSource(bytes));
      setState(() => _playing = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Voice note gone: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secs = ((widget.message.durationMs ?? 0) / 1000).ceil();
    return InkWell(
      onTap: _toggle,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_loading)
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(_playing ? Icons.pause_circle : Icons.play_circle, size: 26),
        const SizedBox(width: 8),
        Text('Voice message · ${secs}s'),
      ]),
    );
  }
}
