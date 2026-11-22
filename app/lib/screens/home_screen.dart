import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets.dart';
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
            flexibleSpace: gradientAppBarBackground(),
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
          body: VoidBackground(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: [
                  _chatsTab(),
                  _contactsTab(),
                  ProfileScreen(state: state),
                ][_tab],
              ),
            ),
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF14141F), Color(0xFF0B0B13)],
              ),
              border: const Border(top: BorderSide(color: Color(0x14FFFFFF))),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: BottomNavigationBar(
              backgroundColor: Colors.transparent,
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
          ),
        );
      },
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: kPanelGradient,
                border: Border.all(color: const Color(0x14FFFFFF)),
                boxShadow: depthShadow(),
              ),
              child: Icon(icon, size: 40, color: kAccentSoft),
            ),
            const SizedBox(height: 20),
            Text(title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted)),
          ],
        ),
      ),
    );
  }

  Widget _chatsTab() {
    final convs = state.sortedConversations;
    if (convs.isEmpty) {
      return _emptyState(Icons.chat_bubble_outline_rounded, 'No chats yet',
          'Tap + to message someone by \$name.');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: convs.length,
      itemBuilder: (context, i) {
        final conv = convs[i];
        final last = conv.lastActivity;
        return DepthCard(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          radius: 18,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            leading: GradientAvatar(
                label: conv.title, group: conv.isGroup, radius: 24),
            title: Text(conv.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
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
                      gradient: kAccentGradient,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: kAccent.withValues(alpha: 0.45),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text('${conv.unread}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
              ],
            ),
            onTap: () => _openChat(conv),
          ),
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
          return _emptyState(Icons.people_outline_rounded, 'No contacts yet',
              'Start a chat to add people.');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          itemCount: contacts.length,
          itemBuilder: (context, i) {
            final p = contacts[i];
            final live = state.profilesById[p.userId] ?? p;
            return DepthCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              radius: 18,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: Stack(children: [
                  GradientAvatar(label: p.cashtag, radius: 24),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
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
                title: Text(p.display,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text((live.online ?? false)
                    ? 'online'
                    : 'last seen ${_fmtSeen(live.lastSeen)}'),
                onTap: () async {
                  final conv = await state.openChatWith(p.cashtag);
                  if (mounted) await _openChat(conv);
                },
              ),
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
