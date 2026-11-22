import 'package:material_ui/material_ui.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/store.dart';
import 'theme.dart';

void main() => runApp(const DexterApp());

class DexterApp extends StatefulWidget {
  const DexterApp({super.key});

  @override
  State<DexterApp> createState() => _DexterAppState();
}

class _DexterAppState extends State<DexterApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.init();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DexterChat',
      theme: buildDexterTheme(),
      home: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          if (!_state.ready) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return _state.isLoggedIn
              ? HomeScreen(state: _state)
              : AuthScreen(state: _state);
        },
      ),
    );
  }
}
