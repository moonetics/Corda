import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/platform_bridge.dart';
import '../theme/corda_theme.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _autoAccept = true;
  bool _hapticEnabled = true;
  bool _isServiceRunning = false;
  PermissionStatusModel _permissions = const PermissionStatusModel(
    accessibility: false,
    batteryIgnored: false,
    notification: false,
  );

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final perms = await PlatformBridge.instance.checkPermissions();
    final running = await PlatformBridge.instance.isServiceRunning();
    if (mounted) {
      setState(() {
        _permissions = perms;
        _isServiceRunning = running;
      });
    }
  }

  Future<void> _toggleService(bool value) async {
    if (value) {
      await PlatformBridge.instance.startForegroundService();
    } else {
      await PlatformBridge.instance.stopForegroundService();
    }
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refreshStatus,
          color: CordaTheme.aquaCyan,
          backgroundColor: CordaTheme.obsidianGlass,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: CordaTheme.aquaGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: CordaTheme.aquaCyan.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      CupertinoIcons.gear_alt_fill,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pengaturan',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Corda System & Preferences',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // SECTION 1: Berkas & Penyimpanan
              _buildSectionTitle('BERKAS & PENYIMPANAN'),
              const SizedBox(height: 10),
              LiquidGlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: CordaTheme.aquaPrimary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            CupertinoIcons.folder_fill,
                            color: CordaTheme.aquaCyan,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Lokasi Unduhan Berkas',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Berkas dari Mac disimpan ke folder ini',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: CordaTheme.mintGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: CordaTheme.mintGreen.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'Aktif',
                            style: TextStyle(
                              color: CordaTheme.mintGreen,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            CupertinoIcons.archivebox_fill,
                            size: 16,
                            color: Colors.white38,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Download/Corda',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: CordaTheme.aquaCyan,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Terima Berkas Otomatis',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Stream langsung dari Mac terpercaya tanpa konfirmasi',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        CupertinoSwitch(
                          value: _autoAccept,
                          activeTrackColor: CordaTheme.aquaPrimary,
                          onChanged: (val) {
                            setState(() => _autoAccept = val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // SECTION 2: Preferensi Sinkronisasi & Umpan Balik
              _buildSectionTitle('PREFERENSI SINKRONISASI'),
              const SizedBox(height: 10),
              LiquidGlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Haptic Feedback',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Getaran mikro halus saat teks/berkas tersinkron',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        CupertinoSwitch(
                          value: _hapticEnabled,
                          activeTrackColor: CordaTheme.aquaPrimary,
                          onChanged: (val) {
                            setState(() => _hapticEnabled = val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: CordaTheme.aquaCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            CupertinoIcons.doc_on_clipboard_fill,
                            color: CordaTheme.aquaCyan,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sinkronisasi Clipboard Instan',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Mendengarkan event copy global di background',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (_permissions.accessibility
                                    ? CordaTheme.mintGreen
                                    : CordaTheme.amberWarning)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _permissions.accessibility ? 'Aktif' : 'Perlu Izin',
                            style: TextStyle(
                              color: _permissions.accessibility
                                  ? CordaTheme.mintGreen
                                  : CordaTheme.amberWarning,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // SECTION 3: Layanan Sistem (System Services)
              _buildSectionTitle('STATUS LAYANAN ANDROID'),
              const SizedBox(height: 10),
              LiquidGlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _buildServiceTile(
                      icon: CupertinoIcons.waveform_path_ecg,
                      title: 'Foreground Service',
                      subtitle: _isServiceRunning
                          ? 'Service berjalan di background'
                          : 'Service terhenti',
                      isPositive: _isServiceRunning,
                      statusText: _isServiceRunning ? 'Berjalan' : 'Berhenti',
                      trailing: CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: _isServiceRunning
                            ? CordaTheme.roseDanger.withValues(alpha: 0.2)
                            : CordaTheme.aquaPrimary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        onPressed: () => _toggleService(!_isServiceRunning),
                        child: Text(
                          _isServiceRunning ? 'Hentikan' : 'Mulai',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _isServiceRunning
                                ? CordaTheme.roseDanger
                                : CordaTheme.aquaCyan,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 12),
                    _buildServiceTile(
                      icon: CupertinoIcons.eye_fill,
                      title: 'Aksesibilitas (Clipboard)',
                      subtitle: _permissions.accessibility
                          ? 'Izin clipboard sistem aktif'
                          : 'Ketuk untuk membuka setelan',
                      isPositive: _permissions.accessibility,
                      statusText: _permissions.accessibility ? 'Diberikan' : 'Belum Aktif',
                      onTap: () async {
                        await PlatformBridge.instance.openAccessibilitySettings();
                      },
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 12),
                    _buildServiceTile(
                      icon: CupertinoIcons.battery_charging,
                      title: 'Optimasi Baterai',
                      subtitle: _permissions.batteryIgnored
                          ? 'Dikecualikan dari pembatasan'
                          : 'Ketuk untuk kecualikan Corda',
                      isPositive: _permissions.batteryIgnored,
                      statusText: _permissions.batteryIgnored ? 'Diabaikan' : 'Dibatasi',
                      onTap: () async {
                        await PlatformBridge.instance.openBatterySettings();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Branding footer
              Center(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/images/corda_logo_icon.png',
                      width: 44,
                      height: 44,
                    ),
                    const SizedBox(height: 8),
                    ShaderMask(
                      shaderCallback: (bounds) => CordaTheme.aquaGradient.createShader(bounds),
                      child: const Text(
                        'CORDA',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v1.0.0 (Sonoma Liquid Edition) • TLS 1.3 E2EE',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
              ),
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

  Widget _buildServiceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isPositive,
    required String statusText,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final tile = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isPositive ? CordaTheme.mintGreen : CordaTheme.amberWarning)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isPositive ? CordaTheme.mintGreen : CordaTheme.amberWarning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          trailing
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isPositive ? CordaTheme.mintGreen : CordaTheme.amberWarning)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: isPositive ? CordaTheme.mintGreen : CordaTheme.amberWarning,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: tile,
        ),
      );
    }
    return tile;
  }
}
