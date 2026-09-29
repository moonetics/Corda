import 'dart:async';
import 'package:flutter/material.dart';
import '../services/platform_bridge.dart';
import '../theme/corda_theme.dart';
import 'onboarding_screen.dart';
import 'qr_scanner_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  PermissionStatusModel _permissions = const PermissionStatusModel(
    accessibility: false,
    batteryIgnored: false,
    notification: false,
  );

  bool _isServiceRunning = false;
  final List<DiscoveredDeviceModel> _discoveredDevices = [];
  ClipboardEventModel? _lastClipboardEvent;

  StreamSubscription<ClipboardEventModel>? _clipboardSub;
  StreamSubscription<DiscoveredDeviceModel>? _discoverySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDashboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clipboardSub?.cancel();
    _discoverySub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkHealth();
    }
  }

  Future<void> _initDashboard() async {
    await _checkHealth();
    final running = await PlatformBridge.instance.isServiceRunning();
    if (mounted) {
      setState(() => _isServiceRunning = running);
    }

    if (!running && _permissions.accessibility) {
      await PlatformBridge.instance.startForegroundService();
      if (mounted) {
        setState(() => _isServiceRunning = true);
      }
    }

    // Subscribe to clipboard events
    _clipboardSub = PlatformBridge.instance.clipboardStream.listen((event) {
      if (mounted) {
        setState(() {
          _lastClipboardEvent = event;
        });
      }
    });

    // Subscribe to mDNS discovery events
    _discoverySub = PlatformBridge.instance.discoveryStream.listen((device) {
      if (mounted) {
        setState(() {
          final index = _discoveredDevices.indexWhere((d) => d.id == device.id || d.host == device.host);
          if (index >= 0) {
            _discoveredDevices[index] = device;
          } else {
            _discoveredDevices.add(device);
          }
        });
      }
    });
  }

  Future<void> _checkHealth() async {
    final status = await PlatformBridge.instance.checkPermissions();
    if (mounted) {
      setState(() => _permissions = status);
    }
  }

  Future<void> _toggleService(bool value) async {
    if (value) {
      await PlatformBridge.instance.startForegroundService();
    } else {
      await PlatformBridge.instance.stopForegroundService();
    }
    final running = await PlatformBridge.instance.isServiceRunning();
    if (mounted) {
      setState(() => _isServiceRunning = running);
    }
  }

  void _showPairWithDiscoveredDeviceDialog(DiscoveredDeviceModel device) {
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.laptop_mac_rounded, color: CordaTheme.aquaPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pasangkan dengan ${device.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              const Text(
                'Masukkan 6-digit PIN yang tampil di jendela Menu Bar Mac Anda:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinController,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 6),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: TextStyle(letterSpacing: 6, color: Colors.grey.withValues(alpha: 0.5)),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
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
              child: const Text('Buka QR Scanner'),
            ),
            ElevatedButton(
              onPressed: () async {
                final pin = pinController.text.trim();
                if (pin.length == 6) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
                      _checkHealth();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.redAccent,
                          content: Text(result['message']?.toString() ?? 'Pairing gagal'),
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Pasangkan'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: CordaTheme.aquaGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.link_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Corda',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'Panduan Onboarding',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Status',
            onPressed: _checkHealth,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Slogan Banner Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer.withValues(alpha: 0.6),
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: CordaTheme.aquaPrimary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'The invisible cord between your Mac and Android',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sinkronisasi clipboard instan (< 200 ms) & transfer file Wi-Fi lokal berkecepatan tinggi.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Health Warning Banner (if accessibility disabled)
            if (!_permissions.accessibility) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CordaTheme.amberWarning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: CordaTheme.amberWarning.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: CordaTheme.amberWarning, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Aksesibilitas Belum Aktif',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: CordaTheme.amberWarning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Layanan Aksesibilitas diperlukan agar Corda dapat mendeteksi saat Anda menyalin teks di Android.',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CordaTheme.amberWarning,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(40),
                      ),
                      onPressed: () {
                        PlatformBridge.instance.openAccessibilitySettings();
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Aktifkan Aksesibilitas Sekarang'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Background Service Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _isServiceRunning ? CordaTheme.mintGreen : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isServiceRunning
                              ? 'Layanan Latar Belakang: Siaga'
                              : 'Layanan Latar Belakang: Dinonaktifkan',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Switch.adaptive(
                          value: _isServiceRunning,
                          activeTrackColor: CordaTheme.mintGreen,
                          onChanged: _toggleService,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isServiceRunning
                          ? 'Notifikasi hening (IMPORTANCE_MIN) aktif. Siaga mendengarkan copy event dan siaran mDNS.'
                          : 'Nyalakan saklar di atas untuk mengaktifkan sinkronisasi otomatis di latar belakang.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Discovered Mac Devices Card (NsdManager mDNS)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.wifi_tethering_rounded, size: 20, color: CordaTheme.aquaPrimary),
                        const SizedBox(width: 10),
                        Text(
                          'Perangkat Mac di Jaringan Lokal',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: CordaTheme.aquaPrimary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'mDNS _corda._tcp',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: CordaTheme.aquaPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_discoveredDevices.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: CordaTheme.aquaPrimary),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Mencari siaran Mac via mDNS... Pastikan Mac dan Android di Wi-Fi yang sama.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      ..._discoveredDevices.map((device) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: CordaTheme.aquaPrimary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: CordaTheme.aquaPrimary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.laptop_mac_rounded, color: CordaTheme.aquaPrimary, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      device.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                    Text(
                                      '${device.host}:${device.port}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                onPressed: () {
                                  _showPairWithDiscoveredDeviceDialog(device);
                                },
                                child: const Text('Pair'),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Quick Actions Card
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const QRScannerScreen()),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: CordaTheme.aquaGradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Pindai QR Mac',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pasangkan dengan Mac',
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Fitur transfer file akan aktif di Phase 5.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: CordaTheme.mintGreen,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.upload_file_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Kirim File ke Mac',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'P2P Wi-Fi Langsung',
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Live Clipboard Activity Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.content_copy_rounded, size: 20, color: CordaTheme.aquaCyan),
                        const SizedBox(width: 10),
                        Text(
                          'Aktivitas Salin Clipboard Terakhir',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        if (_lastClipboardEvent != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: CordaTheme.mintGreen.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Lolos Filter',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: CordaTheme.mintGreen,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_lastClipboardEvent == null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Belum ada teks yang disalin. Coba salin teks di browser atau aplikasi lain untuk melihat event tertangkap secara live.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _lastClipboardEvent!.text,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_lastClipboardEvent!.text.length} karakter',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  DateTime.fromMillisecondsSinceEpoch(_lastClipboardEvent!.timestamp)
                                      .toLocal()
                                      .toString()
                                      .split('.')
                                      .first,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
