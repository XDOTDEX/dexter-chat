import 'package:material_ui/material_ui.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/store.dart';
import 'theme.dart';
import 'widgets.dart';

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
          final String stage =
              !_state.ready ? 'splash' : _state.isLoggedIn ? 'home' : 'auth';
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(
              key: ValueKey(stage),
              child: switch (stage) {
                'home' => HomeScreen(state: _state),
                'auth' => AuthScreen(state: _state),
                _ => const SplashScreen(),
              },
            ),
          );
        },
      ),
    );
  }
}

/// Branded launch screen shown while the session restores — the same
/// void backdrop, logo mark and wordmark the native splash hands over
/// to, so the whole launch feels like one designed moment.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: VoidBackground(
        child: Center(
          child: FadeInSlide(
            dy: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LogoMark(size: 104),
                SizedBox(height: 22),
                GradientText(
                  'DexterChat',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 8),
                Text(
                  'Private circle messenger · end-to-end encrypted',
                  style: TextStyle(color: kMuted),
                ),
                SizedBox(height: 30),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: kAccent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
