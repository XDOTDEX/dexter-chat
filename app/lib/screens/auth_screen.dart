import 'package:material_ui/material_ui.dart';

import '../services/store.dart';
import '../services/wallet.dart';
import '../theme.dart';

/// Login / signup: wallet (EVM personal_sign) or phone OTP.
/// Signup is invite-only — the extra fields appear when "I'm new" is on.
class AuthScreen extends StatefulWidget {
  final AppState state;
  const AuthScreen({super.key, required this.state});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  int _method = 0; // 0 wallet, 1 phone
  bool _isNew = false;
  bool _busy = false;
  String? _error;
  String? _devCode;

  final _server = TextEditingController();
  final _invite = TextEditingController();
  final _cashtag = TextEditingController();
  final _privKey = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _server.text = state.api.baseUrl;
    state.savedWalletKey().then((k) {
      if (k != null && mounted) _privKey.text = k;
    });
  }

  @override
  void dispose() {
    for (final c in [_server, _invite, _cashtag, _privKey, _phone, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _walletGo() async {
    final keyText = _privKey.text.trim();
    if (keyText.isEmpty) {
      setState(() => _error = 'Paste your wallet private key first');
      return;
    }
    await _run(() async {
      final wallet = WalletService.fromPrivateKeyHex(keyText);
      await state.walletAuth(
        wallet,
        inviteCode: _isNew ? _invite.text.trim() : null,
        cashtag: _isNew ? _cashtag.text.trim() : null,
      );
    });
  }

  Future<void> _createWallet() async {
    final wallet = WalletService.createRandom();
    setState(() {
      _privKey.text = wallet.privateKeyHex;
      _isNew = true;
    });
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New wallet created'),
        content: const Text(
            'The private key is filled in below. Save it somewhere safe — '
            'it IS your login. Then add an invite code and your \$name and '
            'continue.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _phoneSend() async {
    await _run(() async {
      final res = await state.phoneRequest(_phone.text.trim());
      setState(() {
        _codeSent = true;
        _devCode = res['dev_code'] as String?;
      });
    });
  }

  Future<void> _phoneGo() async {
    await _run(() => state.phoneVerify(
          _phone.text.trim(),
          _code.text.trim(),
          inviteCode: _isNew ? _invite.text.trim() : null,
          cashtag: _isNew ? _cashtag.text.trim() : null,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Text('DexterChat',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: kAccent)),
              const Text('Private circle messenger · end-to-end encrypted',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kMuted)),
              const SizedBox(height: 28),
              TextField(
                controller: _server,
                decoration: const InputDecoration(
                    labelText: 'Server URL', prefixIcon: Icon(Icons.dns)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => state.setServerUrl(_server.text.trim()),
                  child: const Text('Use this server'),
                ),
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.account_balance_wallet),
                      label: Text('Wallet')),
                  ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.phone_android),
                      label: Text('Phone')),
                ],
                selected: {_method},
                onSelectionChanged: (s) =>
                    setState(() => _method = s.first),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: _isNew,
                onChanged: (v) => setState(() => _isNew = v),
                title: const Text("I'm new here"),
                subtitle: const Text('Signup needs an invite code'),
              ),
              if (_isNew) ...[
                TextField(
                  controller: _invite,
                  decoration: const InputDecoration(
                      labelText: 'Invite code', prefixText: ''),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cashtag,
                  decoration: const InputDecoration(
                      labelText: 'Choose your \$name', prefixText: '\$'),
                ),
                const SizedBox(height: 16),
              ],
              if (_method == 0) ..._walletFields(),
              if (_method == 1) ..._phoneFields(),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _walletFields() => [
        TextField(
          controller: _privKey,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Wallet private key',
            helperText:
                'Stored only in this device\'s secure keystore. '
                'It is never shown anywhere in the app.',
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _walletGo,
          child: const Text('Continue with wallet'),
        ),
        TextButton(
          onPressed: _busy ? null : _createWallet,
          child: const Text('Create a new wallet instead'),
        ),
      ];

  List<Widget> _phoneFields() => [
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone number'),
        ),
        const SizedBox(height: 12),
        if (!_codeSent)
          ElevatedButton(
            onPressed: _busy ? null : _phoneSend,
            child: const Text('Send code'),
          )
        else ...[
          if (_devCode != null)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: kSurface2, borderRadius: BorderRadius.circular(8)),
              child: Text('DEV MODE — your code is $_devCode',
                  style: const TextStyle(color: kAccent2)),
            ),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '6-digit code'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : _phoneGo,
            child: const Text('Verify & continue'),
          ),
        ],
      ];
}
