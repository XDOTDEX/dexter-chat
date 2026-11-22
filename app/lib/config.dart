/// App-wide constants.
class AppConfig {
  /// The one and only DexterChat server. The URL is deliberately NOT
  /// user-changeable anywhere in the app — every install talks to this
  /// address, and any server URL stored by an older build is ignored.
  static const String serverUrl = 'https://chat.dexterbots.eu.cc';

  static const String secureChannel = 'dexter/secure';
}
