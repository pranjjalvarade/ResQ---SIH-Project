import 'dart:convert';
import 'dart:typed_data';

/// Severity status of the distress sender.
enum SosStatus {
  critical,
  injured,
  trapped,
  safe,
}

extension SosStatusX on SosStatus {
  String get label {
    switch (this) {
      case SosStatus.critical:
        return 'CRITICAL';
      case SosStatus.injured:
        return 'MEDICAL EMERGENCY';
      case SosStatus.trapped:
        return 'TRAPPED';
      case SosStatus.safe:
        return 'SAFE';
    }
  }

  static SosStatus fromString(String value) {
    switch (value.toUpperCase()) {
      case 'CRITICAL':
        return SosStatus.critical;
      case 'MEDICAL EMERGENCY':
      case 'INJURED':
        return SosStatus.injured;
      case 'TRAPPED':
        return SosStatus.trapped;
      case 'SAFE':
        return SosStatus.safe;
      default:
        return SosStatus.trapped;
    }
  }
}

/// Core data packet broadcast across the ResQ mesh network.
///
/// Each packet originates from a victim device and is relayed
/// hop-by-hop through nearby civilian devices until TTL expires.
class SosPacket {
  /// Unique UUID v4 — used for deduplication across the mesh.
  final String id;

  /// Human-readable name of the distress sender.
  final String senderName;

  /// Unix epoch milliseconds when the packet was first created.
  final int timestamp;

  /// GPS latitude of the sender at packet creation time.
  /// Set to 0.0 when GPS is unavailable.
  final double lat;

  /// GPS longitude of the sender at packet creation time.
  /// Set to 0.0 when GPS is unavailable.
  final double lng;

  /// Current distress severity status.
  final SosStatus status;

  /// Battery percentage (0–100) of the originating device.
  final int battery;

  /// Number of hops this packet has already traversed.
  int hopCount;

  /// Time-To-Live: maximum remaining hops before the packet is discarded.
  /// Defaults to 5 on creation. Decremented by each relay node.
  int ttl;

  SosPacket({
    required this.id,
    required this.senderName,
    required this.timestamp,
    required this.lat,
    required this.lng,
    required this.status,
    required this.battery,
    this.hopCount = 0,
    this.ttl = 5,
  });

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderName': senderName,
        'timestamp': timestamp,
        'lat': lat,
        'lng': lng,
        'status': status.label,
        'battery': battery,
        'hopCount': hopCount,
        'ttl': ttl,
      };

  factory SosPacket.fromJson(Map<String, dynamic> json) => SosPacket(
        id: json['id'] as String,
        senderName: json['senderName'] as String,
        timestamp: json['timestamp'] as int,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        status: SosStatusX.fromString(json['status'] as String),
        battery: json['battery'] as int,
        hopCount: json['hopCount'] as int? ?? 0,
        ttl: json['ttl'] as int? ?? 5,
      );

  /// Encodes the packet to a UTF-8 byte array for Nearby Connections payload.
  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Decodes a UTF-8 byte array received from a Nearby Connections payload.
  static SosPacket fromBytes(Uint8List bytes) =>
      SosPacket.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);

  /// Returns a copy of this packet with updated relay fields.
  SosPacket relayed() => SosPacket(
        id: id,
        senderName: senderName,
        timestamp: timestamp,
        lat: lat,
        lng: lng,
        status: status,
        battery: battery,
        hopCount: hopCount + 1,
        ttl: ttl - 1,
      );

  @override
  String toString() =>
      'SosPacket(id: $id, sender: $senderName, status: ${status.label}, hops: $hopCount, ttl: $ttl)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SosPacket && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
