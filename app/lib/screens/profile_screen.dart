import 'package:material_ui/material_ui.dart';

import '../services/store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Profile tab: my $name, "username last changed", change history,
/// linked login methods, logout / device reset.
class ProfileScreen extends StatefulWidget {
  final AppState state;
  const ProfileScreen({super.key, required this.state});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _newName = TextEditingController();
  bool _busy = false;

  AppState get state => widget.state;

  @override
  void dispose() {
    _newName.dispose();
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
      padding: const EdgeInsets.all(16),
      children: [
        DepthCard(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
          child: Column(
            children: [
              GradientAvatar(label: me.cashtag, radius: 38),
              const SizedBox(height: 14),
              Text(me.display,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
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
              const SizedBox(height: 14),
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
            ],
          ),
        ),
        const SizedBox(height: 14),
        DepthCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Change \$name',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DepthField(
                    child: TextField(
                      controller: _newName,
                      decoration: bareFieldDecoration(
                          labelText: 'New \$name', prefixText: '\$'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GradientButton(
                  padding:
                      const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
                  onPressed: _busy ? null : _changeName,
                  child: const Text('Change'),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DepthCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.history, color: kMuted),
                          title: Text(h['old'] == null
                              ? 'Registered as ${h['new']}'
                              : '${h['old']} → ${h['new']}'),
                          subtitle: Text(
                              _fmtDate((h['changed_at'] as num).toDouble())),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
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
