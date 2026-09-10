import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/mesh_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation — better usability in emergency scenarios.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Immersive dark status bar.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D1117),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    ChangeNotifierProvider(
      create: (_) => MeshService(),
      child: const ResQApp(),
    ),
  );
}

class ResQApp extends StatelessWidget {
  const ResQApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResQ',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const _PermissionGate(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0D1117),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFDC143C),
        secondary: Color(0xFF388BFD),
        surface: Color(0xFF161B22),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Color(0xFFF0F6FC),
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF161B22),
        foregroundColor: Color(0xFFF0F6FC),
        elevation: 0,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: Color(0xFFF0F6FC)),
        bodySmall: TextStyle(color: Color(0xFF8B949E)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF161B22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF161B22),
        contentTextStyle: TextStyle(color: Color(0xFFF0F6FC)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Permission gate — requests all required permissions before showing main UI
// -----------------------------------------------------------------------------

class _PermissionGate extends StatefulWidget {
  const _PermissionGate();

  @override
  State<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<_PermissionGate> {
  bool _checking = true;
  bool _allGranted = false;
  String _statusMessage = 'Requesting permissions…';

  /// Permissions required for Google Nearby Connections on Android 12+.
  static final List<Permission> _requiredPermissions = [
    Permission.location,
    Permission.locationWhenInUse,
    Permission.bluetoothScan,
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
    Permission.nearbyWifiDevices,
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _checking = true;
      _statusMessage = 'Requesting permissions…';
    });

    final statuses = await _requiredPermissions.request();

    final denied = statuses.entries
        .where((e) =>
            e.value.isDenied || e.value.isPermanentlyDenied)
        .map((e) => e.key.toString().split('.').last)
        .toList();

    if (denied.isEmpty) {
      setState(() {
        _allGranted = true;
        _checking = false;
        _statusMessage = 'All permissions granted';
      });

      // Start mesh only after permissions are confirmed.
      if (mounted) {
        context.read<MeshService>().startMesh();
      }
    } else {
      setState(() {
        _allGranted = false;
        _checking = false;
        _statusMessage =
            'Missing: ${denied.join(', ')}\n\nResQ requires all permissions to create an offline mesh network.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allGranted) return const HomeScreen();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo / icon
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFFDC143C).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: const Color(0xFFDC143C).withOpacity(0.5)),
                ),
                child: const Icon(
                  Icons.emergency,
                  color: Color(0xFFDC143C),
                  size: 48,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'ResQ',
                style: TextStyle(
                  color: Color(0xFFF0F6FC),
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Offline Disaster Mesh',
                style: TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 40),
              if (_checking)
                const CircularProgressIndicator(
                  color: Color(0xFFDC143C),
                )
              else ...[
                Icon(
                  _allGranted ? Icons.check_circle : Icons.warning_amber,
                  color: _allGranted
                      ? const Color(0xFF3FB950)
                      : const Color(0xFFD29922),
                  size: 36,
                ),
                const SizedBox(height: 16),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF8B949E),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 32),
                if (!_allGranted)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => openAppSettings(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC143C),
                            side: const BorderSide(color: Color(0xFFDC143C)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Open Settings'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _requestPermissions,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDC143C),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
