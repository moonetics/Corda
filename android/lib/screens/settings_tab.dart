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
      backgroundColor: CordaTheme.canvasBg,
      appBar: AppBar(
        backgroundColor: CordaTheme.canvasBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshStatus,
          color: CordaTheme.accentBlue,
          backgroundColor: CordaTheme.surfaceCard,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // SECTION 1: Files & Storage
              _buildSectionTitle('FILES & STORAGE'),
              const SizedBox(height: 8),
              SonomaCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: CordaTheme.surfaceSubtle,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: CordaTheme.borderSubtle),
                          ),
                          child: const Icon(CupertinoIcons.folder_fill, color: CordaTheme.accentBlue, size: 18),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Download Destination',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Incoming files from Mac will be saved here',
                                style: TextStyle(fontSize: 11, color: CordaTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF142E1B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF23552D)),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(color: CordaTheme.mintGreen, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: CordaTheme.surfaceSubtle,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: CordaTheme.borderSubtle),
                      ),
                      child: const Row(
                        children: [
                          Icon(CupertinoIcons.archivebox, size: 14, color: CordaTheme.textMuted),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Download/Corda',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Auto-Accept Transfers',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Stream directly from trusted Macs without prompting',
                                style: TextStyle(fontSize: 11, color: CordaTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        CupertinoSwitch(
                          value: _autoAccept,
                          activeTrackColor: CordaTheme.accentBlue,
                          onChanged: (val) {
                            setState(() => _autoAccept = val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // SECTION 2: Continuity & Sync Preferences
              _buildSectionTitle('CONTINUITY PREFERENCES'),
              const SizedBox(height: 8),
              SonomaCard(
                padding: const EdgeInsets.all(16),
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
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Subtle micro-vibration when items are synchronized',
                                style: TextStyle(fontSize: 11, color: CordaTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        CupertinoSwitch(
                          value: _hapticEnabled,
                          activeTrackColor: CordaTheme.accentBlue,
                          onChanged: (val) {
                            setState(() => _hapticEnabled = val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: CordaTheme.surfaceSubtle,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: CordaTheme.borderSubtle),
                          ),
                          child: const Icon(CupertinoIcons.doc_on_clipboard_fill, color: CordaTheme.accentBlue, size: 18),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Instant Clipboard Sync',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Detect global clipboard changes in the background',
                                style: TextStyle(fontSize: 11, color: CordaTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _permissions.accessibility
                                ? const Color(0xFF142E1B)
                                : const Color(0xFF2B2215),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _permissions.accessibility
                                  ? const Color(0xFF23552D)
                                  : const Color(0xFF5C4316),
                            ),
                          ),
                          child: Text(
                            _permissions.accessibility ? 'Active' : 'Action Needed',
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

              const SizedBox(height: 20),

              // SECTION 3: System Services & Permissions
              _buildSectionTitle('BACKGROUND PERMISSIONS'),
              const SizedBox(height: 8),
              SonomaCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildServiceTile(
                      icon: CupertinoIcons.waveform_path_ecg,
                      title: 'Background Sync',
                      subtitle: _isServiceRunning ? 'Syncing actively in background' : 'Background service paused',
                      isPositive: _isServiceRunning,
                      statusText: _isServiceRunning ? 'Active' : 'Paused',
                      trailing: CupertinoSwitch(
                        value: _isServiceRunning,
                        activeTrackColor: CordaTheme.accentBlue,
                        onChanged: (val) => _toggleService(val),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    _buildServiceTile(
                      icon: CupertinoIcons.doc_on_clipboard_fill,
                      title: 'Clipboard Sync',
                      subtitle: _permissions.accessibility
                          ? 'Automatic copy detection active'
                          : 'Tap to enable in accessibility settings',
                      isPositive: _permissions.accessibility,
                      statusText: _permissions.accessibility ? 'Active' : 'Setup',
                      onTap: () async {
                        await PlatformBridge.instance.openAccessibilitySettings();
                      },
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    _buildServiceTile(
                      icon: CupertinoIcons.layers_alt_fill,
                      title: 'Quick Sync',
                      subtitle: _permissions.overlay
                          ? 'Instant in-app copy capture active'
                          : 'Tap to grant in system settings',
                      isPositive: _permissions.overlay,
                      statusText: _permissions.overlay ? 'Active' : 'Setup',
                      onTap: () async {
                        await PlatformBridge.instance.openOverlaySettings();
                      },
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    _buildServiceTile(
                      icon: CupertinoIcons.battery_charging,
                      title: 'Background Activity',
                      subtitle: _permissions.batteryIgnored
                          ? 'Unrestricted background running'
                          : 'Tap to prevent Android from sleeping Corda',
                      isPositive: _permissions.batteryIgnored,
                      statusText: _permissions.batteryIgnored ? 'Unrestricted' : 'Optimized',
                      onTap: () async {
                        await PlatformBridge.instance.openBatterySettings();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Canonical Brand Footer
              Center(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/images/logo_corda.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Corda',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'v1.0.0 • Private Local Sync',
                      style: TextStyle(
                        fontSize: 11,
                        color: CordaTheme.textMuted,
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
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isPositive ? const Color(0xFF142E1B) : const Color(0xFF2B2215),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isPositive ? const Color(0xFF23552D) : const Color(0xFF5C4316),
            ),
          ),
          child: Icon(
            icon,
            size: 16,
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
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: CordaTheme.textSecondary),
              ),
            ],
          ),
        ),
        if (trailing != null)
          trailing
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isPositive ? const Color(0xFF142E1B) : const Color(0xFF2B2215),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isPositive ? const Color(0xFF23552D) : const Color(0xFF5C4316),
              ),
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
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: tile,
        ),
      );
    }
    return tile;
  }
}
