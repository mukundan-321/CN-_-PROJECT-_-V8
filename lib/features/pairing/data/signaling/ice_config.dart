/// Per spec: "No TURN relay unless explicitly enabled by the user" and
/// "the design should prioritize privacy over guaranteed connectivity."
///
/// TURN relays see connection metadata (both peers' traffic patterns,
/// timing, volume) even though the payload itself stays E2E encrypted.
/// That's a privacy cost the app doesn't pay by default — connectivity
/// failure is preferable to silently routing through a third party.
class IceConfig {
  static const List<Map<String, dynamic>> stunOnlyServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  /// Only used if [turnEnabled] is true in Settings AND the user has
  /// supplied their own TURN credentials — this app ships with no
  /// default/bundled TURN server, since that would silently reintroduce
  /// the third party the rest of the design goes out of its way to avoid.
  static List<Map<String, dynamic>> buildServers({
    required bool turnEnabled,
    String? turnUrl,
    String? turnUsername,
    String? turnCredential,
  }) {
    if (!turnEnabled || turnUrl == null) return stunOnlyServers;
    return [
      ...stunOnlyServers,
      {
        'urls': turnUrl,
        'username': turnUsername,
        'credential': turnCredential,
      },
    ];
  }

  static Map<String, dynamic> configuration({required bool turnEnabled}) => {
        'iceServers': buildServers(turnEnabled: turnEnabled),
        'iceTransportPolicy': 'all',
      };
}
