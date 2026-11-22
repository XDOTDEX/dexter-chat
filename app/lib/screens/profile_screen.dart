import 'package:material_ui/material_ui.dart';

import '../services/store.dart';
import '../theme.dart';

/// Profile tab: my $name, "username last changed", change history,
/// linked login methods, server settings, logout / device reset.
class ProfileScreen extends StatefulWidget {
  final AppState state;
  const ProfileScreen({super.key, required this.state});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _newName = TextEditingController();
  final _server = TextEditingController();
  bool _busy = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _server.text = state.api.baseUrl;
  }

  @override
  void dispose() {
    _newName.dispose();
    _server.dispose();
    super.dispose();
  }

  String _fmtDate(double epochSeconds) {
    final d =
        DateTime.fromMillisecondsSinceEpoch((epochSeconds * 1000).round());
    return '${d.day}/${d.month}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _changeName() async {
    final name = _newName.text.trim().replaceAll('\$', '');
    if (name.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Change to \$$name?'),
        content: const Text(
            'Your old \$name is released immediately and someone else '
            'could take it. The change is recorded on your profile.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Change')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await state.changeCashtag(name);
      _newName.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('\$name changed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = state.me;
    if (me == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const CircleAvatar(
          radius: 34,
          backgroundColor: kSurface2,
          child: Icon(Icons.person, size: 36, color: kAccent),
        ),
        const SizedBox(height: 12),
        Text(me.display,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Member since ${_fmtDate(me.createdAt)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted)),
        Text(
          me.cashtagChangedAt == null
              ? 'Username last changed: never'
              : 'Username last changed: ${_fmtDate(me.cashtagChangedAt!)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: kMuted),
        ),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
          Chip(
              avatar: const Icon(Icons.account_balance_wallet, size: 16),
              label: Text((me.hasWallet ?? false)
                  ? 'Wallet linked'
                  : 'No wallet linked')),
          Chip(
              avatar: const Icon(Icons.phone_android, size: 16),
              label: Text((me.hasPhone ?? false)
                  ? 'Phone linked'
                  : 'No phone linked')),
        ]),
        const Divider(height: 36),
        const Text('Change \$name',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _newName,
              decoration: const InputDecoration(
                  labelText: 'New \$name', prefixText: '\$'),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
              onPressed: _busy ? null : _changeName,
              child: const Text('Change')),
        ]),
        const SizedBox(height: 16),
        const Text('\$name history',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: state.api.cashtagHistory(),
          builder: (context, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            return Column(
              children: [
                for (final h in snap.data!)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, color: kMuted),
                    title: Text(h['old'] == null
                        ? 'Registered as ${h['new']}'
                        : '${h['old']} → ${h['new']}'),
                    subtitle:
                        Text(_fmtDate((h['changed_at'] as num).toDouble())),
                  ),
              ],
            );
          },
        ),
        const Divider(height: 36),
        const Text('Server',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
                controller: _server,
                decoration: const InputDecoration(labelText: 'Server URL')),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => state.setServerUrl(_server.text.trim()),
            child: const Text('Save'),
          ),
        ]),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
          onPressed: () => state.logout(),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
          label: const Text('Reset this device',
              style: TextStyle(color: Colors.redAccent)),
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Reset this device?'),
                content: const Text(
                    'This forgets your login, your encryption keys and all '
                    'local chats on this phone. Without the keys, old '
                    'messages cannot be decrypted again.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Reset')),
                ],
              ),
            );
            if (confirm == true) await state.resetDevice();
          },
        ),
      ],
    );
  }
}
