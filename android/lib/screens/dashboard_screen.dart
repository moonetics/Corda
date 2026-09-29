import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/platform_bridge.dart';
import '../theme/corda_theme.dart';
import 'onboarding_screen.dart';
import 'qr_scanner_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToTransfer;

  const DashboardScreen({super.key, this.onNavigateToTransfer});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  PermissionStatusModel _permissions = const PermissionStatusModel(
    accessibility: false,
    batteryIgnored: false,
    notification: false,
  );

  bool _isServiceRunning = false;
  bool _isPossibleAPIsolation = false;
  final List<DiscoveredDeviceModel> _discoveredDevices = [];
  List<TrustedDeviceModel> _trustedDevices = [];
  Map<String, dynamic> _connectionStatus = {'isConnected': false, 'connectedHost': '', 'connectedPort': 0};
  ClipboardEventModel? _lastClipboardEvent;

  StreamSubscription<ClipboardEventModel>? _clipboardSub;
  StreamSubscription<DiscoveredDeviceModel>? _discoverySub;
  StreamSubscription<bool>? _isolationSub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDashboard();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _clipboardSub?.cancel();
    _discoverySub?.cancel();
    _isolationSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollStatus();
    }
  }

  Future<void> _initDashboard() async {
    await _pollStatus();

    // Auto-start foreground service if accessibility is granted
    if (!_isServiceRunning && _permissions.accessibility) {
      await PlatformBridge.instance.startForegroundService();
      final running = await PlatformBridge.instance.isServiceRunning();
      if (mounted) setState(() => _isServiceRunning = running);
    }

    _clipboardSub = PlatformBridge.instance.clipboardStream.listen((event) {
      if (mounted) {
        setState(() => _lastClipboardEvent = event);
      }
    });

    _discoverySub = PlatformBridge.instance.discoveryStream.listen((device) {
      if (mounted) {
        setState(() {
          final idx = _discoveredDevices.indexWhere((d) => d.id == device.id || d.host == device.host);
          if (idx >= 0) {
            _discoveredDevices[idx] = device;
          } else {
            _discoveredDevices.add(device);
          }
        });
      }
    });

    _isolationSub = PlatformBridge.instance.apIsolationStream.listen((suspected) {
      if (mounted) {
        setState(() => _isPossibleAPIsolation = suspected);
      }
    });
  }

  Future<void> _pollStatus() async {
    final perms = await PlatformBridge.instance.checkPermissions();
    final running = await PlatformBridge.instance.isServiceRunning();
    final trusted = await PlatformBridge.instance.getTrustedDevices();
    final conn = await PlatformBridge.instance.getConnectionStatus();

    if (mounted) {
      setState(() {
        _permissions = perms;
        _isServiceRunning = running;
        _trustedDevices = trusted;
        _connectionStatus = conn;
      });
    }
  }

  Future<void> _unpairDevice(TrustedDeviceModel device) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Putuskan Perangkat?'),
        content: Text(
          'Anda yakin ingin memutuskan sambungan dengan "${device.name}"? Kunci E2EE akan dihapus.',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Putuskan'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PlatformBridge.instance.unpairDevice(device.id);
      await _pollStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CordaTheme.obsidianGlass,
            content: Text('Perangkat ${device.name} telah diputuskan.'),
          ),
        );
      }
    }
  }

  void _showPairWithDiscoveredDeviceDialog(DiscoveredDeviceModel device) {
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: CordaTheme.obsidianGlass,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: CordaTheme.obsidianGlassBorder),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: CordaTheme.aquaGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(CupertinoIcons.macwindow, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Pasangkan dengan ${device.name}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alamat IP: ${device.host}:${device.port}',
                style: const TextStyle(fontSize: 12, color: Colors.white54, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 14),
              const Text(
                'Masukkan 6-digit PIN yang tampil di jendela Menu Bar Mac Anda:',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                  color: CordaTheme.aquaCyan,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: TextStyle(
                    letterSpacing: 8,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: CordaTheme.obsidianGlassBorder),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QRScannerScreen()),
                );
              },
              child: const Text('Buka Kamera QR', style: TextStyle(color: CordaTheme.aquaCyan)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CordaTheme.aquaPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final pin = pinController.text.trim();
                if (pin.length == 6) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: CordaTheme.obsidianGlass,
                      content: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: CordaTheme.aquaCyan),
                          ),
                          const SizedBox(width: 12),
                          Text('Menghubungkan ke ${device.name}...'),
                        ],
                      ),
                      duration: const Duration(seconds: 5),
                    ),
                  );

                  final result = await PlatformBridge.instance.pairDevice(
                    host: device.host,
                    port: device.port,
                    pin: pin,
                    fingerprint: device.fingerprint,
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    if (result['success'] == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: CordaTheme.mintGreen,
                          content: Text('Berhasil dipasangkan dengan ${device.name}!'),
                        ),
                      );
                      _pollStatus();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: CordaTheme.roseDanger,
                          content: Text(result['message']?.toString() ?? 'Pairing gagal'),
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Pasangkan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionStatus['isConnected'] == true;
    final primaryTrustedDevice = _trustedDevices.isNotEmpty ? _trustedDevices.first : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _pollStatus,
          color: CordaTheme.aquaCyan,
          backgroundColor: CordaTheme.obsidianGlass,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            children: [
              // Top Bar Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: CordaTheme.obsidianGlass,
                          border: Border.all(color: CordaTheme.obsidianGlassBorder),
                          boxShadow: [
                            BoxShadow(
                              color: CordaTheme.aquaPrimary.withValues(alpha: 0.25),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/corda_logo_icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => CordaTheme.aquaGradient.createShader(bounds),
                            child: const Text(
                              'CORDA',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            'Continuity Bridge • macOS Sonoma',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(CupertinoIcons.question_circle, color: Colors.white70, size: 22),
                        tooltip: 'Panduan',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.arrow_clockwise, color: Colors.white70, size: 20),
                        tooltip: 'Refresh',
                        onPressed: _pollStatus,
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Accessibility Warning Banner (if disabled)
              if (!_permissions.accessibility) ...[
                LiquidGlassCard(
                  borderColor: CordaTheme.amberWarning.withValues(alpha: 0.6),
                  fillColor: CordaTheme.amberWarning.withValues(alpha: 0.08),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: CordaTheme.amberWarning.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              CupertinoIcons.exclamationmark_triangle_fill,
                              color: CordaTheme.amberWarning,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Aksesibilitas Diperlukan',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: CordaTheme.amberWarning,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Layanan Aksesibilitas diperlukan agar Corda dapat mendeteksi saat Anda menyalin teks di Android secara instan di background.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.8),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CordaTheme.amberWarning,
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(38),
                        ),
                        onPressed: () {
                          PlatformBridge.instance.openAccessibilitySettings();
                        },
                        icon: const Icon(CupertinoIcons.arrow_up_right_square, size: 16),
                        label: const Text(
                          'Aktifkan Aksesibilitas Sekarang',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // HERO CARD: Apple Continuity Device Card (Prominent Paired Mac Status)
              _buildAppleContinuityDeviceCard(primaryTrustedDevice, isConnected),

              const SizedBox(height: 24),

              // Discovered Macs on Wi-Fi Network
              _buildSectionTitle('PERANGKAT MAC DI WI-FI LOKAL'),
              const SizedBox(height: 10),
              _buildDiscoveredDevicesSection(),

              const SizedBox(height: 24),

              // Live Clipboard Activity Card
              _buildSectionTitle('AKTIVITAS CLIPBOARD TERAKHIR'),
              const SizedBox(height: 10),
              _buildClipboardActivityCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  /// Apple Continuity Device Card
  /// Prominently displays pairing status, connected Mac details, TLS status, and actions.
  Widget _buildAppleContinuityDeviceCard(TrustedDeviceModel? device, bool isConnected) {
    if (device == null) {
      // Unpaired state: Hero card inviting user to pair
      return LiquidGlassCard(
        glow: true,
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: CordaTheme.aquaGradient,
                boxShadow: [
                  BoxShadow(
                    color: CordaTheme.aquaCyan.withValues(alpha: 0.35),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Icon(CupertinoIcons.macwindow, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 14),
            const Text(
              'Belum Terhubung ke Mac',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pasangkan Android dengan Mac Anda untuk sinkronisasi clipboard dua arah & pengiriman file instan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.6),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CordaTheme.aquaPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const QRScannerScreen()),
                      );
                    },
                    icon: const Icon(CupertinoIcons.qrcode_viewfinder, size: 18),
                    label: const Text(
                      'Pindai QR Mac',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // PAIRED STATE: Apple Continuity Device Card
    final host = _connectionStatus['connectedHost'] as String? ?? device.connectedHost;
    final port = _connectionStatus['connectedPort'] as int? ?? device.connectedPort;
    final displayHost = host.isNotEmpty ? host : 'Wi-Fi Lokal';

    return LiquidGlassCard(
      glow: true,
      borderColor: isConnected
          ? CordaTheme.aquaCyan.withValues(alpha: 0.5)
          : CordaTheme.obsidianGlassBorder,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Device Name + Live Badge
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: isConnected
                        ? [const Color(0xFF0A84FF), const Color(0xFF00D2D3)]
                        : [const Color(0xFF2C3E50), const Color(0xFF34495E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    if (isConnected)
                      BoxShadow(
                        color: CordaTheme.aquaCyan.withValues(alpha: 0.4),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.macwindow,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected ? CordaTheme.mintGreen : Colors.white38,
                            boxShadow: [
                              if (isConnected)
                                BoxShadow(
                                  color: CordaTheme.mintGreen.withValues(alpha: 0.6),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? 'Terhubung & Aktif ⚡' : 'Tersimpan (Siaga)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isConnected ? CordaTheme.mintGreen : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: const Text(
                  'macOS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 16),

          // Specs Grid
          Row(
            children: [
              Expanded(
                child: _buildDeviceSpecItem(
                  icon: CupertinoIcons.wifi,
                  label: 'ALAMAT IP',
                  value: port > 0 ? '$displayHost:$port' : displayHost,
                ),
              ),
              Expanded(
                child: _buildDeviceSpecItem(
                  icon: CupertinoIcons.lock_shield_fill,
                  label: 'KEAMANAN',
                  value: 'TLS 1.3 E2EE',
                  highlight: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDeviceSpecItem(
                  icon: CupertinoIcons.barcode,
                  label: 'FINGERPRINT',
                  value: device.fingerprint.length > 12
                      ? '${device.fingerprint.substring(0, 8)}...${device.fingerprint.substring(device.fingerprint.length - 4)}'
                      : (device.fingerprint.isEmpty ? 'Tervalidasi' : device.fingerprint),
                ),
              ),
              Expanded(
                child: _buildDeviceSpecItem(
                  icon: CupertinoIcons.calendar,
                  label: 'DIPASANGKAN',
                  value: device.pairedAt.split('T').first.isNotEmpty
                      ? device.pairedAt.split('T').first
                      : 'Aktif',
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 14),

          // Action row
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: CordaTheme.roseDanger,
                  side: BorderSide(color: CordaTheme.roseDanger.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: () => _unpairDevice(device),
                icon: const Icon(CupertinoIcons.xmark_circle, size: 16),
                label: const Text('Putuskan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CordaTheme.aquaPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  if (widget.onNavigateToTransfer != null) {
                    widget.onNavigateToTransfer!();
                  }
                },
                icon: const Icon(CupertinoIcons.paperplane_fill, size: 14),
                label: const Text('Kirim Berkas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSpecItem({
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.white38),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: label == 'ALAMAT IP' || label == 'FINGERPRINT' ? 'monospace' : null,
            color: highlight ? CordaTheme.aquaCyan : Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  /// Discovered Macs Section
  Widget _buildDiscoveredDevicesSection() {
    if (_discoveredDevices.isEmpty) {
      return LiquidGlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: CordaTheme.aquaCyan),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Mencari siaran Mac via mDNS (_corda._tcp)... Pastikan Mac membuka Corda di Wi-Fi yang sama.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            if (_isPossibleAPIsolation) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CordaTheme.amberWarning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CordaTheme.amberWarning.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(CupertinoIcons.wifi_exclamationmark, color: CordaTheme.amberWarning, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Kemungkinan AP Isolation aktif di Wi-Fi ini. Komunikasi lokal diblokir oleh router. Gunakan Hotspot Pribadi.',
                        style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: _discoveredDevices.map((dev) {
        return LiquidGlassCard(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CordaTheme.aquaPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(CupertinoIcons.macwindow, color: CordaTheme.aquaCyan, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dev.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                    ),
                    Text(
                      '${dev.host}:${dev.port}',
                      style: const TextStyle(fontSize: 12, color: Colors.white54, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CordaTheme.aquaPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _showPairWithDiscoveredDeviceDialog(dev),
                child: const Text('Pasangkan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Real-Time Clipboard Activity Card
  Widget _buildClipboardActivityCard() {
    final event = _lastClipboardEvent;
    if (event == null) {
      return LiquidGlassCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(CupertinoIcons.doc_on_clipboard, color: Colors.white38, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Belum ada teks disalin. Salin teks di aplikasi apa pun (WhatsApp, Chrome, Catatan) untuk sinkron otomatis ke Mac.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.45),
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final dateStr = DateTime.fromMillisecondsSinceEpoch(event.timestamp)
        .toLocal()
        .toString()
        .split('.')
        .first;

    return LiquidGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.doc_on_clipboard_fill, size: 16, color: CordaTheme.aquaCyan),
                  const SizedBox(width: 8),
                  Text(
                    event.sourcePackage.isNotEmpty ? event.sourcePackage : 'Tersinkron',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: CordaTheme.mintGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Tersinkron ke Mac ✨',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: CordaTheme.mintGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Text(
              event.text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${event.text.length} karakter • $dateStr',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: event.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Teks disalin kembali ke clipboard Android'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: const Row(
                  children: [
                    Icon(CupertinoIcons.doc_on_doc, size: 14, color: CordaTheme.aquaCyan),
                    SizedBox(width: 4),
                    Text(
                      'Salin Ulang',
                      style: TextStyle(fontSize: 11, color: CordaTheme.aquaCyan, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
