import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/sos_packet.dart';
import '../services/mesh_service.dart';

/// Primary screen of ResQ — mesh dashboard + SOS broadcast center.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // ── Form state ──────────────────────────────────────────────────────────────
  final _nameController = TextEditingController(text: 'Survivor');
  SosStatus _selectedStatus = SosStatus.trapped;
  bool _isBroadcasting = false;

  // ── Pulse animation for SOS button ──────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ── Theme colors ────────────────────────────────────────────────────────────
  static const Color _bg = Color(0xFF0D1117);
  static const Color _surface = Color(0xFF161B22);
  static const Color _card = Color(0xFF1C2128);
  static const Color _crimson = Color(0xFFDC143C);
  static const Color _crimsonDim = Color(0xFF8B0A25);
  static const Color _textPrimary = Color(0xFFF0F6FC);
  static const Color _textSecondary = Color(0xFF8B949E);
  static const Color _green = Color(0xFF3FB950);
  static const Color _amber = Color(0xFFD29922);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SOS broadcast logic
  // ---------------------------------------------------------------------------

  Future<void> _broadcastSOS(MeshService mesh) async {
    if (_isBroadcasting) return;
    setState(() => _isBroadcasting = true);

    // ── Get GPS (best-effort, fallback to 0.0) ──────────────────────────────
    double lat = 0.0, lng = 0.0;
    try {
      final LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 5));
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {
      // GPS unavailable — underground or denied. (0.0, 0.0) is the fallback.
    }

    // ── Build packet ────────────────────────────────────────────────────────
    final packet = SosPacket(
      id: const Uuid().v4(),
      senderName: _nameController.text.trim().isEmpty
          ? 'Unknown'
          : _nameController.text.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      lat: lat,
      lng: lng,
      status: _selectedStatus,
      battery: 80, // Static value — real impl would call BatteryPlus
      hopCount: 0,
      ttl: 5,
    );

    await mesh.broadcastSOS(packet);

    setState(() => _isBroadcasting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _crimson,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SOS broadcast to ${mesh.peerCount} peer(s)',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshService>();

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(mesh),
      body: SafeArea(
        child: Column(
          children: [
            _buildMeshStatusBanner(mesh),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    _buildNameField(),
                    const SizedBox(height: 16),
                    _buildStatusChips(),
                    const SizedBox(height: 24),
                    _buildSOSButton(mesh),
                    const SizedBox(height: 28),
                    _buildFeedSection(mesh),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildRelayFAB(mesh),
    );
  }

  // ---------------------------------------------------------------------------
  // App Bar
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar(MeshService mesh) {
    return AppBar(
      backgroundColor: _surface,
      elevation: 0,
      centerTitle: false,
      title: Row(
        children: [
          Icon(
            Icons.wifi_tethering,
            color: mesh.isMeshActive ? _green : _textSecondary,
            size: 20,
          ),
          const SizedBox(width: 8),
          const Text(
            'ResQ',
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '— OFFLINE MESH ACTIVE',
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w400,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      actions: [
        // Peer count badge
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: mesh.peerCount > 0
                ? _green.withOpacity(0.15)
                : _textSecondary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: mesh.peerCount > 0 ? _green : _textSecondary,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.people,
                color: mesh.peerCount > 0 ? _green : _textSecondary,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                '${mesh.peerCount} Peers',
                style: TextStyle(
                  color: mesh.peerCount > 0 ? _green : _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mesh status banner
  // ---------------------------------------------------------------------------

  Widget _buildMeshStatusBanner(MeshService mesh) {
    final active = mesh.isMeshActive;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: active ? _green.withOpacity(0.1) : _crimson.withOpacity(0.1),
      child: Row(
        children: [
          Icon(
            active ? Icons.circle : Icons.error_outline,
            color: active ? _green : _crimson,
            size: 10,
          ),
          const SizedBox(width: 8),
          Text(
            active
                ? 'Mesh online — advertising & listening on BLE / Wi-Fi Direct'
                : 'Mesh offline — starting up…',
            style: TextStyle(
              color: active ? _green : _crimson,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (mesh.lastError != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mesh.lastError!,
                style: const TextStyle(color: _crimson, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Name field
  // ---------------------------------------------------------------------------

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR NAME',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _nameController,
          style: const TextStyle(color: _textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: _surface,
            hintText: 'Enter your name',
            hintStyle: const TextStyle(color: _textSecondary),
            prefixIcon:
                const Icon(Icons.person_outline, color: _textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _card),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _textSecondary.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _crimson),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Status chips
  // ---------------------------------------------------------------------------

  Widget _buildStatusChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DISTRESS STATUS',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SosStatus.values
              .where((s) => s != SosStatus.safe)
              .map((s) => _StatusChip(
                    status: s,
                    isSelected: _selectedStatus == s,
                    onTap: () => setState(() => _selectedStatus = s),
                  ))
              .toList(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SOS button
  // ---------------------------------------------------------------------------

  Widget _buildSOSButton(MeshService mesh) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) => Transform.scale(
        scale: _isBroadcasting ? 1.0 : _pulseAnimation.value,
        child: child,
      ),
      child: GestureDetector(
        onTap: _isBroadcasting ? null : () => _broadcastSOS(mesh),
        child: Container(
          width: double.infinity,
          height: 100,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                _crimson,
                _crimsonDim,
              ],
              radius: 1.2,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _crimson.withOpacity(0.45),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: _isBroadcasting
              ? const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.sos,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'BROADCAST SOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      ),
                    ),
                    Text(
                      mesh.peerCount > 0
                          ? 'Sending to ${mesh.peerCount} peer(s) • relays up to 5 hops'
                          : 'No peers — will broadcast when mesh connects',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mesh traffic feed
  // ---------------------------------------------------------------------------

  Widget _buildFeedSection(MeshService mesh) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'MESH TRAFFIC  /  DISTRESS FEED',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            if (mesh.receivedPackets.isNotEmpty)
              Text(
                '${mesh.receivedPackets.length} packet(s)',
                style: const TextStyle(color: _textSecondary, fontSize: 11),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (mesh.receivedPackets.isEmpty)
          _buildEmptyFeed()
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: mesh.receivedPackets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) =>
                _PacketCard(packet: mesh.receivedPackets[i]),
          ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildEmptyFeed() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _textSecondary.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Icon(Icons.radar, color: _textSecondary.withOpacity(0.4), size: 48),
          const SizedBox(height: 12),
          Text(
            'Listening for mesh traffic…',
            style: TextStyle(
              color: _textSecondary.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Packets from nearby devices will appear here',
            style: TextStyle(
              color: _textSecondary.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Relay FAB
  // ---------------------------------------------------------------------------

  Widget _buildRelayFAB(MeshService mesh) {
    return FloatingActionButton.extended(
      backgroundColor: mesh.isRelayEnabled
          ? _green.withOpacity(0.9)
          : _textSecondary.withOpacity(0.3),
      onPressed: mesh.toggleRelay,
      icon: Icon(
        mesh.isRelayEnabled ? Icons.swap_horiz : Icons.block,
        color: Colors.white,
      ),
      label: Text(
        mesh.isRelayEnabled ? 'Relay ON' : 'Relay OFF',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

/// Selectable chip for SOS distress status selection.
class _StatusChip extends StatelessWidget {
  final SosStatus status;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.status,
    required this.isSelected,
    required this.onTap,
  });

  Color get _chipColor {
    switch (status) {
      case SosStatus.critical:
        return const Color(0xFFDC143C);
      case SosStatus.injured:
        return const Color(0xFFD29922);
      case SosStatus.trapped:
        return const Color(0xFF388BFD);
      case SosStatus.safe:
        return const Color(0xFF3FB950);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _chipColor.withOpacity(0.2) : const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _chipColor : const Color(0xFF8B949E).withOpacity(0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(Icons.check_circle, color: _chipColor, size: 14),
              const SizedBox(width: 4),
            ],
            Text(
              status.label,
              style: TextStyle(
                color: isSelected ? _chipColor : const Color(0xFF8B949E),
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card displaying a single received SOS packet in the mesh feed.
class _PacketCard extends StatelessWidget {
  final SosPacket packet;

  const _PacketCard({required this.packet});

  static const Color _card = Color(0xFF1C2128);
  static const Color _textPrimary = Color(0xFFF0F6FC);
  static const Color _textSecondary = Color(0xFF8B949E);

  Color get _statusColor {
    switch (packet.status) {
      case SosStatus.critical:
        return const Color(0xFFDC143C);
      case SosStatus.injured:
        return const Color(0xFFD29922);
      case SosStatus.trapped:
        return const Color(0xFF388BFD);
      case SosStatus.safe:
        return const Color(0xFF3FB950);
    }
  }

  String get _timeAgo {
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(packet.timestamp));
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  String get _gps {
    if (packet.lat == 0.0 && packet.lng == 0.0) return 'GPS Unavailable';
    return '${packet.lat.toStringAsFixed(5)}, ${packet.lng.toStringAsFixed(5)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _statusColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────────
          Row(
            children: [
              // Status badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _statusColor, width: 1),
                ),
                child: Text(
                  packet.status.label,
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  packet.senderName,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _timeAgo,
                style: const TextStyle(color: _textSecondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── Detail row ──────────────────────────────────────────────────────
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _InfoChip(
                icon: Icons.route,
                label: 'Hops: ${packet.hopCount}',
              ),
              _InfoChip(
                icon: Icons.location_on,
                label: _gps,
              ),
              _InfoChip(
                icon: Icons.battery_std,
                label: '${packet.battery}%',
              ),
              _InfoChip(
                icon: Icons.timer,
                label: 'TTL: ${packet.ttl}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small label+icon pair used in packet cards.
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: const Color(0xFF8B949E)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8B949E),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
