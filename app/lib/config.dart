/// App-wide constants. The server URL is user-changeable in Profile
/// (stored in secure storage); this is only the first-run default.
class AppConfig {
  /// 10.0.2.2 reaches the host machine from the Android emulator.
  static const String defaultServerUrl = 'http://10.0.2.2:8642';

  static const String secureChannel = 'dexter/secure';
}
