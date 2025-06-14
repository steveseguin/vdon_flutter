// social_stream_config.dart
class SocialStreamConfig {
  final String sessionId;
  final ConnectionMode mode;
  final String? password;
  final bool enabled;

  SocialStreamConfig({
    required this.sessionId,
    required this.mode,
    this.password,
    this.enabled = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'mode': mode.name,
      'password': password,
      'enabled': enabled,
    };
  }

  factory SocialStreamConfig.fromMap(Map<String, dynamic> map) {
    return SocialStreamConfig(
      sessionId: map['sessionId'] ?? '',
      mode: ConnectionMode.values.firstWhere(
        (e) => e.name == map['mode'],
        orElse: () => ConnectionMode.webrtc,
      ),
      password: map['password'],
      enabled: map['enabled'] ?? false,
    );
  }
}

enum ConnectionMode {
  webrtc,
  websocket,
}