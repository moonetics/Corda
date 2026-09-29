import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/platform_bridge.dart';
import '../theme/corda_theme.dart';
import 'file_transfer_screen.dart';
import 'onboarding_screen.dart';
import 'qr_scanner_screen.dart';
import 'settings_tab.dart';

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
  TransferEventModel? _activeTransfer;
  bool _isPicking = false;

  StreamSubscription<ClipboardEventModel>? _clipboardSub;
  StreamSubscription<DiscoveredDeviceModel>? _discoverySub;
  StreamSubscription<bool>? _isolationSub;
  StreamSubscription<TransferEventModel>? _transferSub;
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
    _transferSub?.cancel();
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

    _transferSub = PlatformBridge.instance.transferStream.listen((event) {
      if (mounted) {
        setState(() => _activeTransfer = event);
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
        title: const Text('Unpair Device?'),
        content: Text(
          'Are you sure you want to unpair "${device.name}"? End-to-end encryption keys will be removed.',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unpair'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
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
            backgroundColor: CordaTheme.surfaceCard,
            content: Text('${device.name} has been unpaired.'),
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendFiles() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);

    try {
      final filePaths = await PlatformBridge.instance.pickFiles();
      if (!mounted) return;
      if (filePaths.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CordaTheme.surfaceCard,
            content: Row(
              children: [
                const Icon(CupertinoIcons.paperplane_fill, color: CordaTheme.accentBlue, size: 16),
                const SizedBox(width: 10),
                Text(
                  'Sending ${filePaths.length} file(s) to Mac...',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: CordaTheme.borderSubtle),
            ),
          ),
        );

        for (final path in filePaths) {
          await PlatformBridge.instance.sendFile(path);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  void _showPairWithDiscoveredDeviceDialog(DiscoveredDeviceModel device) {
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: CordaTheme.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: CordaTheme.borderSubtle),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CordaTheme.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CordaTheme.borderSubtle),
                ),
                child: const Icon(CupertinoIcons.macwindow, color: CordaTheme.accentBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Pair with ${device.name}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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
                'Host: ${device.host}:${device.port}',
                style: const TextStyle(fontSize: 12, color: CordaTheme.textSecondary, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 14),
              const Text(
                'Enter the 6-digit PIN displayed on your Mac:',
                style: TextStyle(fontSize: 13, color: CordaTheme.textSecondary),
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
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: TextStyle(
                    letterSpacing: 8,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  filled: true,
                  fillColor: CordaTheme.surfaceSubtle,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: CordaTheme.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: CordaTheme.accentBlue),
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
              child: const Text('Scan QR Code', style: TextStyle(color: CordaTheme.accentBlue)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CordaTheme.accentBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final pin = pinController.text.trim();
                if (pin.length == 6) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: CordaTheme.surfaceCard,
                      content: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: CordaTheme.accentBlue),
                          ),
                          const SizedBox(width: 12),
                          Text('Connecting to ${device.name}...'),
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
                          backgroundColor: CordaTheme.surfaceCard,
                          content: Text('Successfully paired with ${device.name}!'),
                        ),
                      );
                      _pollStatus();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: CordaTheme.surfaceCard,
                          content: Text(result['message']?.toString() ?? 'Pairing failed'),
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Pair', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showManualPairDialog() {
    final hostController = TextEditingController();
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: CordaTheme.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: CordaTheme.borderSubtle),
          ),
          title: const Row(
            children: [
              Icon(CupertinoIcons.link, color: CordaTheme.accentBlue, size: 20),
              SizedBox(width: 10),
              Text(
                'Pair Device Manually',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mac IP Address:', style: TextStyle(fontSize: 12, color: CordaTheme.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: hostController,
                style: const TextStyle(fontSize: 14, color: Colors.white, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: '192.168.1.xxx',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  filled: true,
                  fillColor: CordaTheme.surfaceSubtle,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: CordaTheme.borderSubtle),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 14),
              const Text('6-Digit PIN:', style: TextStyle(fontSize: 12, color: CordaTheme.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 6, color: Colors.white),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: TextStyle(letterSpacing: 6, color: Colors.white.withValues(alpha: 0.2)),
                  filled: true,
                  fillColor: CordaTheme.surfaceSubtle,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: CordaTheme.borderSubtle),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: CordaTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CordaTheme.accentBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final host = hostController.text.trim();
                final pin = pinController.text.trim();
                if (host.isNotEmpty && pin.length == 6) {
                  Navigator.of(ctx).pop();
                  final result = await PlatformBridge.instance.pairDevice(
                    host: host,
                    port: 54321,
                    pin: pin,
                    fingerprint: '',
                  );
                  if (mounted) {
                    if (result['success'] == true) {
                      _pollStatus();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Successfully paired with Mac!')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result['message']?.toString() ?? 'Pairing failed')),
                      );
                    }
                  }
                }
              },
              child: const Text('Pair', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      backgroundColor: CordaTheme.canvasBg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _pollStatus,
          color: CordaTheme.accentBlue,
          backgroundColor: CordaTheme.surfaceCard,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              // Clean Sonoma Top Header
              _buildTopHeader(),

              const SizedBox(height: 16),

              // Minimal Overlay (Appear on Top) Banner (if disabled)
              if (!_permissions.overlay) ...[
                _buildOverlayBanner(),
                const SizedBox(height: 14),
              ],

              // Minimal Accessibility Warning Banner (if disabled)
              if (!_permissions.accessibility) ...[
                _buildAccessibilityBanner(),
                const SizedBox(height: 14),
              ],

              // AP Isolation Warning Banner (if detected)
              if (_isPossibleAPIsolation) ...[
                _buildApIsolationBanner(),
                const SizedBox(height: 14),
              ],

              // Section 1: CONNECTED DEVICES
              _buildSectionTitle('CONNECTED DEVICES'),
              const SizedBox(height: 8),
              _buildConnectedDevicesCard(primaryTrustedDevice, isConnected),

              const SizedBox(height: 20),

              // Section 2: SEND FILES
              _buildSectionTitle('DROP OR CLICK TO SEND FILES'),
              const SizedBox(height: 8),
              _buildSendFilesCard(),

              const SizedBox(height: 20),

              // Section 3: RECENT CLIPBOARD
              _buildSectionTitle('RECENT CLIPBOARD'),
              const SizedBox(height: 8),
              _buildClipboardCard(),

              const SizedBox(height: 20),

              // Section 4: DISCOVERED MACS (if any discovered nearby)
              if (_discoveredDevices.isNotEmpty) ...[
                _buildSectionTitle('DISCOVERED MACS'),
                const SizedBox(height: 8),
                _buildDiscoveredDevicesList(),
                const SizedBox(height: 20),
              ],

              // Section 5: Pair Action & Footer
              _buildFooterActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Image.asset(
              'assets/images/logo_corda.png',
              width: 32,
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Corda',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Mac & Android Continuity',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: CordaTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(CupertinoIcons.question_circle, color: CordaTheme.textSecondary, size: 20),
              tooltip: 'Guide',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.arrow_up_arrow_down_circle, color: CordaTheme.textSecondary, size: 20),
              tooltip: 'Transfers',
              onPressed: () {
                if (widget.onNavigateToTransfer != null) {
                  widget.onNavigateToTransfer!();
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FileTransferScreen()),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.gear_alt, color: CordaTheme.textSecondary, size: 20),
              tooltip: 'Settings',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsTab()),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: CordaTheme.textMuted,
        ),
      ),
    );
  }

  Widget _buildOverlayBanner() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF14243B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1D4A7A), width: 1.0),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(CupertinoIcons.layers_alt_fill, color: CordaTheme.accentBlue, size: 16),
              SizedBox(width: 8),
              Text(
                'Quick Sync Permission Recommended',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: CordaTheme.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Allows Corda to immediately capture in-app copy buttons and sync to Mac in the background.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white70,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CordaTheme.accentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => PlatformBridge.instance.openOverlaySettings(),
              child: const Text('Enable in Settings', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessibilityBanner() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF221A10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A3416), width: 1.0),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_triangle_fill, color: CordaTheme.amberWarning, size: 16),
              SizedBox(width: 8),
              Text(
                'Accessibility Permission Required',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: CordaTheme.amberWarning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Needed for automatic instant background clipboard sync from Android to Mac.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white70,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CordaTheme.amberWarning,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => PlatformBridge.instance.openAccessibilitySettings(),
              child: const Text('Enable in Settings', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApIsolationBanner() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF221A10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A3416), width: 1.0),
      ),
      padding: const EdgeInsets.all(14),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.wifi_exclamationmark, color: CordaTheme.amberWarning, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wi-Fi AP Isolation Detected',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: CordaTheme.amberWarning),
                ),
                SizedBox(height: 4),
                Text(
                  'Your router might be blocking peer-to-peer traffic. If devices cannot connect, try enabling Mobile Hotspot or checking router settings.',
                  style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedDevicesCard(TrustedDeviceModel? device, bool isConnected) {
    if (device == null) {
      return SonomaCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: CordaTheme.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CordaTheme.borderSubtle),
              ),
              child: const Icon(CupertinoIcons.macwindow, color: CordaTheme.textSecondary, size: 24),
            ),
            const SizedBox(height: 12),
            const Text(
              'No Connected Mac',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pair your Android with your Mac for instant clipboard sync and file transfer.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: CordaTheme.textSecondary, height: 1.3),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 38,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CordaTheme.accentBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const QRScannerScreen()),
                  );
                },
                icon: const Icon(CupertinoIcons.qrcode_viewfinder, size: 16),
                label: const Text('Pair Device with QR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }

    final host = _connectionStatus['connectedHost'] as String? ?? device.connectedHost;
    final port = _connectionStatus['connectedPort'] as int? ?? device.connectedPort;
    final displayHost = host.isNotEmpty ? host : 'Wi-Fi Network';

    return SonomaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: CordaTheme.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CordaTheme.borderSubtle),
                ),
                child: const Icon(CupertinoIcons.macwindow, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected ? CordaTheme.mintGreen : CordaTheme.textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? 'Connected • Clipboard Sync Active' : 'Saved (Standby)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isConnected ? CordaTheme.mintGreen : CordaTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: CordaTheme.surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: CordaTheme.borderSubtle),
                ),
                child: const Text(
                  'macOS',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: CordaTheme.textSecondary),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Specs Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NETWORK ADDRESS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: CordaTheme.textMuted)),
                    const SizedBox(height: 2),
                    Text(
                      port > 0 ? '$displayHost:$port' : displayHost,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SECURITY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: CordaTheme.textMuted)),
                    const SizedBox(height: 2),
                    const Text('TLS 1.3 E2EE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CordaTheme.mintGreen)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Action Buttons
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: CordaTheme.roseDanger,
                  side: const BorderSide(color: Color(0xFF452224)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _unpairDevice(device),
                icon: const Icon(CupertinoIcons.xmark_circle, size: 14),
                label: const Text('Unpair', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CordaTheme.accentBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _pickAndSendFiles,
                icon: const Icon(CupertinoIcons.paperplane_fill, size: 12),
                label: const Text('Send Files', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSendFilesCard() {
    final transfer = _activeTransfer;
    final isStreaming = transfer != null && !transfer.isCompleted && !transfer.isFailed;

    return SonomaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: CordaTheme.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CordaTheme.borderSubtle),
                ),
                child: const Icon(CupertinoIcons.arrow_up_doc_fill, color: CordaTheme.accentBlue, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Drop or click to send files',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Supports photos, videos & documents',
                      style: TextStyle(fontSize: 11, color: CordaTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 34,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CordaTheme.surfaceSubtle,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: CordaTheme.borderSubtle),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isPicking ? null : _pickAndSendFiles,
                  child: _isPicking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Choose Files', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),

          if (isStreaming) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        transfer.filename,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                    Text(
                      '${(transfer.progress * 100).toInt()}%',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: CordaTheme.accentBlue),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: transfer.progress,
                    backgroundColor: CordaTheme.surfaceSubtle,
                    color: CordaTheme.accentBlue,
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${transfer.formattedSpeed} • ${transfer.formattedBytes}',
                  style: const TextStyle(fontSize: 10, color: CordaTheme.textSecondary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClipboardCard() {
    final event = _lastClipboardEvent;

    if (event == null) {
      return SonomaCard(
        padding: const EdgeInsets.all(14),
        child: const Row(
          children: [
            Icon(CupertinoIcons.doc_on_clipboard, size: 16, color: CordaTheme.textMuted),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Clipboard sync is active. Copy text on your Mac or Android to sync automatically.',
                style: TextStyle(fontSize: 12, color: CordaTheme.textSecondary, height: 1.3),
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

    return SonomaCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.doc_on_clipboard_fill, size: 14, color: CordaTheme.accentBlue),
                  const SizedBox(width: 6),
                  Text(
                    event.sourcePackage.isNotEmpty ? event.sourcePackage : 'Continuity Clipboard',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF142E1B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF23552D)),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(radius: 2.5, backgroundColor: CordaTheme.mintGreen),
                    SizedBox(width: 4),
                    Text(
                      'Synced',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: CordaTheme.mintGreen),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: CordaTheme.surfaceSubtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: CordaTheme.borderSubtle),
            ),
            child: Text(
              event.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.white, height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${event.text.length} chars • $dateStr',
                style: const TextStyle(fontSize: 10, color: CordaTheme.textMuted),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: event.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to Android clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: const Row(
                  children: [
                    Icon(CupertinoIcons.doc_on_doc, size: 12, color: CordaTheme.accentBlue),
                    SizedBox(width: 4),
                    Text('Copy Again', style: TextStyle(fontSize: 11, color: CordaTheme.accentBlue, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveredDevicesList() {
    return Column(
      children: _discoveredDevices.map((dev) {
        return SonomaCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CordaTheme.surfaceSubtle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CordaTheme.borderSubtle),
                ),
                child: const Icon(CupertinoIcons.macwindow, color: CordaTheme.accentBlue, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dev.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                    ),
                    Text(
                      '${dev.host}:${dev.port}',
                      style: const TextStyle(fontSize: 11, color: CordaTheme.textSecondary, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 32,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CordaTheme.accentBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _showPairWithDiscoveredDeviceDialog(dev),
                  child: const Text('Pair', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFooterActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: CordaTheme.accentBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QRScannerScreen()),
              );
            },
            icon: const Icon(CupertinoIcons.qrcode_viewfinder, size: 16),
            label: const Text('Pair Device with QR Code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 38,
          child: TextButton.icon(
            onPressed: _showManualPairDialog,
            icon: const Icon(CupertinoIcons.keyboard, size: 14, color: CordaTheme.textSecondary),
            label: const Text('Pair Manually via IP & PIN', style: TextStyle(fontSize: 12, color: CordaTheme.textSecondary)),
          ),
        ),
      ],
    );
  }
}
