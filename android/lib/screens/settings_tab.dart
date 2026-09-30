import 'dart:async';
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
  bool _smartOtpEnabled = true;
  BatteryStatusModel? _batteryStatus;
  StreamSubscription<BatteryStatusModel>? _batterySub;
  NotificationSettingsModel _notificationSettings = const NotificationSettingsModel(masterEnabled: true, apps: []);
  PermissionStatusModel _permissions = const PermissionStatusModel(
    accessibility: false,
    batteryIgnored: false,
    notification: false,
  );

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _batterySub = PlatformBridge.instance.batteryStream.listen((status) {
      if (mounted) {
        setState(() => _batteryStatus = status);
      }
    });
  }

  @override
  void dispose() {
    _batterySub?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final perms = await PlatformBridge.instance.checkPermissions();
    final running = await PlatformBridge.instance.isServiceRunning();
    final battery = await PlatformBridge.instance.getBatteryStatus();
    final notifSettings = await PlatformBridge.instance.getNotificationSettings();
    if (mounted) {
      setState(() {
        _permissions = perms;
        _isServiceRunning = running;
        _batteryStatus = battery;
        _notificationSettings = notifSettings;
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

  Future<void> _toggleNotificationMaster(bool value) async {
    await PlatformBridge.instance.setNotificationMasterEnabled(value);
    final notif = await PlatformBridge.instance.getNotificationSettings();
    if (mounted) setState(() => _notificationSettings = notif);
  }

  Future<void> _toggleNotificationApp(String packageName, bool value) async {
    await PlatformBridge.instance.setNotificationPackageAllowed(packageName, value);
    final notif = await PlatformBridge.instance.getNotificationSettings();
    if (mounted) setState(() => _notificationSettings = notif);
  }

  Future<void> _addNotificationApp(String packageName, String appName) async {
    await PlatformBridge.instance.addNotificationPackage(packageName, appName);
    PlatformBridge.instance.triggerHaptic();
    final notif = await PlatformBridge.instance.getNotificationSettings();
    if (mounted) setState(() => _notificationSettings = notif);
  }

  Future<void> _removeNotificationApp(String packageName) async {
    await PlatformBridge.instance.removeNotificationPackage(packageName);
    PlatformBridge.instance.triggerHaptic();
    final notif = await PlatformBridge.instance.getNotificationSettings();
    if (mounted) setState(() => _notificationSettings = notif);
  }

  void _showAppPickerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AppPickerBottomSheet(
        existingPackages: _notificationSettings.apps.map((a) => a.packageName).toSet(),
        onAppSelected: (pkg, name) {
          _addNotificationApp(pkg, name);
        },
      ),
    );
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

              // SECTION 2.5: Smart Continuity (OTP & Battery)
              _buildSectionTitle('SMART CONTINUITY'),
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
                                'Smart OTP Forwarding',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Auto-detect OTP codes from SMS & apps to Mac (Privacy-First)',
                                style: TextStyle(fontSize: 11, color: CordaTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        CupertinoSwitch(
                          value: _smartOtpEnabled,
                          activeTrackColor: CordaTheme.accentBlue,
                          onChanged: (val) {
                            setState(() => _smartOtpEnabled = val);
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
                          child: Icon(
                            _batteryStatus?.isCharging == true
                                ? CupertinoIcons.bolt_fill
                                : CupertinoIcons.battery_75_percent,
                            color: _batteryStatus?.isCharging == true
                                ? CordaTheme.mintGreen
                                : CordaTheme.accentBlue,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Live Battery Monitor',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _batteryStatus != null
                                    ? '${_batteryStatus!.level}% • ${_batteryStatus!.isCharging ? "Charging (${_batteryStatus!.powerSource.toUpperCase()})" : "On Battery"}'
                                    : 'Syncing battery state with Mac Menu Bar',
                                style: const TextStyle(fontSize: 11, color: CordaTheme.textSecondary),
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
                          child: Text(
                            _batteryStatus != null ? '${_batteryStatus!.level}%' : 'Active',
                            style: const TextStyle(
                              color: CordaTheme.mintGreen,
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

              // SECTION 2.6: Notification Mirroring Whitelist
              _buildSectionTitle('NOTIFICATION MIRRORING WHITELIST'),
              const SizedBox(height: 8),
              SonomaCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mirror Phone Notifications',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Forward notifications from selected apps to Mac (Source-Side Filter)',
                                style: TextStyle(fontSize: 11, color: CordaTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        CupertinoSwitch(
                          value: _notificationSettings.masterEnabled,
                          activeTrackColor: CordaTheme.accentBlue,
                          onChanged: (val) => _toggleNotificationMaster(val),
                        ),
                      ],
                    ),
                    if (_notificationSettings.masterEnabled) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'APLIKASI TERDAFTAR (${_notificationSettings.apps.length})',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: CordaTheme.textMuted,
                            ),
                          ),
                          InkWell(
                            onTap: _showAppPickerModal,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0x1F0A84FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0x4D0A84FF)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(CupertinoIcons.plus, size: 12, color: CordaTheme.accentBlue),
                                  SizedBox(width: 4),
                                  Text(
                                    'Tambah Aplikasi',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: CordaTheme.accentBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_notificationSettings.apps.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                          child: Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: CordaTheme.surfaceSubtle,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: CordaTheme.borderSubtle),
                                  ),
                                  child: const Icon(CupertinoIcons.bell_slash, size: 20, color: CordaTheme.textMuted),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Belum ada aplikasi yang dipilih',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Ketuk "+ Tambah Aplikasi" untuk memilih aplikasi yang boleh meneruskan notifikasi ke Mac.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11, color: CordaTheme.textSecondary, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._notificationSettings.apps.map((app) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: app.iconBytes != null && app.iconBytes!.isNotEmpty
                                      ? Image.memory(
                                          app.iconBytes!,
                                          width: 32,
                                          height: 32,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: CordaTheme.surfaceSubtle,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: CordaTheme.borderSubtle),
                                          ),
                                          child: Center(
                                            child: Text(
                                              app.appName.isNotEmpty ? app.appName[0].toUpperCase() : '?',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        app.appName,
                                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.white),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        app.packageName,
                                        style: const TextStyle(fontSize: 10, color: CordaTheme.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                CupertinoSwitch(
                                  value: app.isEnabled,
                                  activeTrackColor: CordaTheme.accentBlue,
                                  onChanged: (val) => _toggleNotificationApp(app.packageName, val),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(CupertinoIcons.trash, size: 16, color: CordaTheme.textMuted),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  splashRadius: 18,
                                  onPressed: () => _removeNotificationApp(app.packageName),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
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
                      'v1.2.0 • Apple Continuity for Android',
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

class _AppPickerBottomSheet extends StatefulWidget {
  final Set<String> existingPackages;
  final Function(String packageName, String appName) onAppSelected;

  const _AppPickerBottomSheet({
    required this.existingPackages,
    required this.onAppSelected,
  });

  @override
  State<_AppPickerBottomSheet> createState() => _AppPickerBottomSheetState();
}

class _AppPickerBottomSheetState extends State<_AppPickerBottomSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<InstalledAppModel> _allApps = [];
  List<InstalledAppModel> _filteredApps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadApps();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    final apps = await PlatformBridge.instance.getInstalledApps();
    if (mounted) {
      setState(() {
        _allApps = apps.where((a) => !widget.existingPackages.contains(a.packageName)).toList();
        _filteredApps = List.from(_allApps);
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredApps = List.from(_allApps);
      } else {
        _filteredApps = _allApps.where((app) {
          final name = app.appName.toLowerCase();
          final pkg = app.packageName.toLowerCase();
          return name.contains(query) || pkg.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      decoration: const BoxDecoration(
        color: CordaTheme.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: CordaTheme.borderSubtle)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0x4D5A6072),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pilih Aplikasi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Pilih aplikasi untuk ditambahkan ke whitelist notifikasi',
                      style: TextStyle(
                        fontSize: 11,
                        color: CordaTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.xmark_circle_fill, color: CordaTheme.textMuted, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: CordaTheme.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: CordaTheme.borderSubtle),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  const Icon(CupertinoIcons.search, size: 16, color: CordaTheme.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Cari aplikasi terinstall...',
                        hintStyle: TextStyle(fontSize: 12, color: CordaTheme.textMuted),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(CupertinoIcons.clear_thick_circled, size: 16, color: CordaTheme.textMuted),
                      onPressed: () {
                        _searchCtrl.clear();
                      },
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CupertinoActivityIndicator(color: CordaTheme.accentBlue),
                  )
                : _filteredApps.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.search, size: 32, color: CordaTheme.textMuted),
                            const SizedBox(height: 8),
                            Text(
                              _searchCtrl.text.isEmpty
                                  ? 'Semua aplikasi terinstall sudah ditambahkan'
                                  : 'Tidak ada aplikasi yang cocok',
                              style: const TextStyle(fontSize: 12, color: CordaTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _filteredApps.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: 60),
                        itemBuilder: (context, index) {
                          final app = _filteredApps[index];
                          final pkg = app.packageName;
                          final name = app.appName.isNotEmpty ? app.appName : pkg;
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: app.iconBytes != null && app.iconBytes!.isNotEmpty
                                  ? Image.memory(
                                      app.iconBytes!,
                                      width: 36,
                                      height: 36,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: CordaTheme.surfaceSubtle,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: CordaTheme.borderSubtle),
                                      ),
                                      child: Center(
                                        child: Text(
                                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              pkg,
                              style: const TextStyle(fontSize: 10, color: CordaTheme.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0x1F0A84FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0x4D0A84FF)),
                              ),
                              child: const Text(
                                'Tambah',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: CordaTheme.accentBlue,
                                ),
                              ),
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onAppSelected(pkg, name);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
