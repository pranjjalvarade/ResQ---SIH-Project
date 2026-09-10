import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';

import '../models/sos_packet.dart';

/// Core mesh engine for the ResQ app.
///
/// Manages Google Nearby Connections advertising + discovery simultaneously
/// using [Strategy.P2P_CLUSTER], enabling multi-hop store-and-forward relay
/// of [SosPacket]s across civilian devices without internet or cellular.
class MeshService extends ChangeNotifier {
  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  static const String _serviceId = 'com.resqmesh.emergency';
  static const String _userName = 'ResQNode';

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// Whether advertising + discovery are currently running.
  bool _isMeshActive = false;
  bool get isMeshActive => _isMeshActive;

  /// Whether packet relay is enabled on this node.
  bool _isRelayEnabled = true;
  bool get isRelayEnabled => _isRelayEnabled;

  /// Map of endpointId → endpointName for all currently connected peers.
  final Map<String, String> _connectedPeers = {};
  Map<String, String> get connectedPeers => Map.unmodifiable(_connectedPeers);
  int get peerCount => _connectedPeers.length;

  /// Ordered list of unique packets received or originated on this node.
  final List<SosPacket> _receivedPackets = [];
  List<SosPacket> get receivedPackets => List.unmodifiable(_receivedPackets);

  /// Deduplication set: IDs of packets already processed this session.
  final Set<String> _seenIds = {};

  /// Last error message for display in the UI.
  String? _lastError;
  String? get lastError => _lastError;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Starts simultaneous Nearby advertising and discovery.
  /// Safe to call multiple times — stops previous session first.
  Future<void> startMesh() async {
    if (_isMeshActive) await stopMesh();

    _lastError = null;

    try {
      await _startAdvertising();
      await _startDiscovery();

      _isMeshActive = true;
      notifyListeners();
      debugPrint('[MeshService] Mesh started (advertising + discovery)');
    } catch (e) {
      _lastError = 'Failed to start mesh: $e';
      _isMeshActive = false;
      notifyListeners();
      debugPrint('[MeshService] startMesh error: $e');
    }
  }

  /// Stops all Nearby activity and clears connected peers.
  Future<void> stopMesh() async {
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      await Nearby().stopAllEndpoints();
    } catch (_) {}

    _connectedPeers.clear();
    _isMeshActive = false;
    notifyListeners();
    debugPrint('[MeshService] Mesh stopped');
  }

  /// Toggles packet relay on/off. When disabled, this node still receives
  /// packets and shows them in the feed but does NOT re-broadcast them.
  void toggleRelay() {
    _isRelayEnabled = !_isRelayEnabled;
    notifyListeners();
  }

  /// Creates and broadcasts an SOS packet from the local device.
  ///
  /// [packet] should be freshly constructed with the user's chosen status.
  Future<void> broadcastSOS(SosPacket packet) async {
    // Mark as seen to prevent echo loops if the packet bounces back.
    _seenIds.add(packet.id);

    // Add to local feed immediately.
    _addToFeed(packet);

    // Broadcast raw bytes to all connected peers.
    await _sendToAllPeers(packet.toBytes(), sourcePacketId: packet.id);

    debugPrint(
        '[MeshService] SOS broadcast: ${packet.id} to ${_connectedPeers.length} peers');
  }

  // ---------------------------------------------------------------------------
  // Advertising
  // ---------------------------------------------------------------------------

  Future<void> _startAdvertising() async {
    await Nearby().startAdvertising(
      _userName,
      Strategy.P2P_CLUSTER,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
      serviceId: _serviceId,
    );
  }

  // ---------------------------------------------------------------------------
  // Discovery
  // ---------------------------------------------------------------------------

  Future<void> _startDiscovery() async {
    await Nearby().startDiscovery(
      _userName,
      Strategy.P2P_CLUSTER,
      onEndpointFound: _onEndpointFound,
      onEndpointLost: _onEndpointLost,
      serviceId: _serviceId,
    );
  }

  // ---------------------------------------------------------------------------
  // Connection callbacks
  // ---------------------------------------------------------------------------

  /// Called on BOTH sides when a connection is initiated.
  /// Auto-accepts without PIN prompt — appropriate for emergency context.
  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    debugPrint(
        '[MeshService] Connection initiated: $endpointId (${info.endpointName})');

    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: (endpointId, update) {
        // No-op: bytes payloads complete atomically, no chunk tracking needed.
      },
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      // Name is stored during discovery; fall back to endpointId if missing.
      _connectedPeers[endpointId] =
          _connectedPeers[endpointId] ?? endpointId;
      debugPrint(
          '[MeshService] Connected: $endpointId — peers: ${_connectedPeers.length}');
    } else {
      _connectedPeers.remove(endpointId);
      debugPrint('[MeshService] Connection failed: $endpointId ($status)');
    }
    notifyListeners();
  }

  void _onDisconnected(String endpointId) {
    _connectedPeers.remove(endpointId);
    debugPrint(
        '[MeshService] Disconnected: $endpointId — peers: ${_connectedPeers.length}');
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Discovery callbacks
  // ---------------------------------------------------------------------------

  void _onEndpointFound(
      String endpointId, String endpointName, String serviceId) {
    debugPrint('[MeshService] Endpoint found: $endpointId ($endpointName)');

    // Store name early so it's available when connection is accepted.
    _connectedPeers[endpointId] = endpointName;

    // Immediately request connection to the discovered endpoint.
    Nearby().requestConnection(
      _userName,
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  void _onEndpointLost(String? endpointId) {
    if (endpointId != null) {
      _connectedPeers.remove(endpointId);
      notifyListeners();
      debugPrint('[MeshService] Endpoint lost: $endpointId');
    }
  }

  // ---------------------------------------------------------------------------
  // Payload handling (store-and-forward relay)
  // ---------------------------------------------------------------------------

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES) return;
    final bytes = payload.bytes;
    if (bytes == null) return;

    SosPacket packet;
    try {
      packet = SosPacket.fromBytes(bytes);
    } catch (e) {
      debugPrint('[MeshService] Failed to parse payload: $e');
      return;
    }

    // ── Deduplication ────────────────────────────────────────────────────────
    if (_seenIds.contains(packet.id)) {
      debugPrint('[MeshService] Duplicate dropped: ${packet.id}');
      return;
    }

    _seenIds.add(packet.id);
    _addToFeed(packet);
    debugPrint(
        '[MeshService] Received packet: ${packet.id} hops=${packet.hopCount} ttl=${packet.ttl}');

    // ── Store-and-Forward Relay ───────────────────────────────────────────────
    if (_isRelayEnabled && packet.ttl > 1) {
      final relayed = packet.relayed();
      _sendToAllPeers(
        relayed.toBytes(),
        sourcePacketId: packet.id,
        excludeEndpoint: endpointId, // Don't echo back to sender.
      );
      debugPrint(
          '[MeshService] Relayed: ${packet.id} hops=${relayed.hopCount} ttl=${relayed.ttl}');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _addToFeed(SosPacket packet) {
    // Insert newest at top.
    _receivedPackets.insert(0, packet);
    notifyListeners();
  }

  Future<void> _sendToAllPeers(
    Uint8List bytes, {
    required String sourcePacketId,
    String? excludeEndpoint,
  }) async {
    final targets = _connectedPeers.keys
        .where((id) => id != excludeEndpoint)
        .toList();

    for (final endpointId in targets) {
      try {
        await Nearby().sendBytesPayload(endpointId, bytes);
      } catch (e) {
        debugPrint(
            '[MeshService] Send failed to $endpointId for $sourcePacketId: $e');
      }
    }
  }

  @override
  void dispose() {
    stopMesh();
    super.dispose();
  }
}
