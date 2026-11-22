import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/store.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppState state;
  const HomeScreen({super.key, required this.state});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  AppState get state => widget.state;

  Future<void> _openChat(Conversation conv) async {
    setState(() => conv.unread = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ChatScreen(state: state, conversation: conv)),
    );
  }

  Future<void> _newChatDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Their \$name', prefixText: '\$'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, controller.text.trim()),
              child: const Text('Open chat')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final conv = await state.openChatWith(name);
      await state.api.addContact(name);
      if (mounted) await _openChat(conv);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _newGroupDialog() async {
    final nameC = TextEditingController();
    final membersC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameC,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Group name')),
            const SizedBox(height: 12),
            TextField(
                controller: membersC,
                decoration: const InputDecoration(
                    labelText: 'Members (\$names, comma separated)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final members = membersC.text
          .split(',')
          .map((s) => s.trim().replaceAll('\$', ''))
          .where((s) => s.isNotEmpty)
          .toList();
      final conv = await state.createGroup(nameC.text.trim(), members);
      if (mounted) await _openChat(conv);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(['Chats', 'Contacts', 'Profile'][_tab]),
            actions: _tab == 0
                ? [
                    IconButton(
                        icon: const Icon(Icons.person_add),
                        tooltip: 'New chat',
                        onPressed: _newChatDialog),
                    IconButton(
                        icon: const Icon(Icons.group_add),
                        tooltip: 'New group',
                        onPressed: _newGroupDialog),
                  ]
                : null,
          ),
          body: [
            _chatsTab(),
            _contactsTab(),
            ProfileScreen(state: state),
          ][_tab],
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble), label: 'Chats'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.people), label: 'Contacts'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        );
      },
    );
  }

  Widget _chatsTab() {
    final convs = state.sortedConversations;
    if (convs.isEmpty) {
      return const Center(
        child: Text('No chats yet.\nTap + to message someone by \$name.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kMuted)),
      );
    }
    return ListView.builder(
      itemCount: convs.length,
      itemBuilder: (context, i) {
        final conv = convs[i];
        final last = conv.lastActivity;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: kSurface2,
            child: Icon(conv.isGroup ? Icons.group : Icons.person,
                color: kAccent),
          ),
          title: Text(conv.title),
          subtitle: Text(conv.preview,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (last != null)
                Text(
                    '${last.hour.toString().padLeft(2, '0')}:'
                    '${last.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: kMuted, fontSize: 12)),
              if (conv.unread > 0)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                      color: kAccent,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${conv.unread}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                ),
            ],
          ),
          onTap: () => _openChat(conv),
        );
      },
    );
  }

  Widget _contactsTab() {
    return FutureBuilder<List<Profile>>(
      future: state.api.contacts(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
              child: Text('Could not load contacts.\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kMuted)));
        }
        final contacts = snap.data ?? [];
        if (contacts.isEmpty) {
          return const Center(
              child: Text('No contacts yet.\nStart a chat to add people.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kMuted)));
        }
        return ListView.builder(
          itemCount: contacts.length,
          itemBuilder: (context, i) {
            final p = contacts[i];
            final live = state.profilesById[p.userId] ?? p;
            return ListTile(
              leading: Stack(children: [
                const CircleAvatar(
                    backgroundColor: kSurface2,
                    child: Icon(Icons.person, color: kAccent)),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: (live.online ?? false)
                          ? Colors.greenAccent
                          : kMuted,
                      shape: BoxShape.circle,
                      border: Border.all(color: kVoid, width: 2),
                    ),
                  ),
                ),
              ]),
              title: Text(p.display),
              subtitle: Text((live.online ?? false)
                  ? 'online'
                  : 'last seen ${_fmtSeen(live.lastSeen)}'),
              onTap: () async {
                final conv = await state.openChatWith(p.cashtag);
                if (mounted) await _openChat(conv);
              },
            );
          },
        );
      },
    );
  }

  String _fmtSeen(double? epochSeconds) {
    if (epochSeconds == null) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(
        (epochSeconds * 1000).round());
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}
