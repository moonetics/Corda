import 'dart:async';
import 'package:flutter/services.dart';

class PermissionStatusModel {
  final bool accessibility;
  final bool batteryIgnored;
  final bool notification;
  final bool overlay;

  const PermissionStatusModel({
    required this.accessibility,
    required this.batteryIgnored,
    required this.notification,
    this.overlay = false,
  });

  bool get isAllGranted => accessibility && batteryIgnored && notification && overlay;

  factory PermissionStatusModel.fromMap(Map<dynamic, dynamic> map) {
    return PermissionStatusModel(
      accessibility: map['accessibility'] as bool? ?? false,
      batteryIgnored: map['batteryIgnored'] as bool? ?? false,
      notification: map['notification'] as bool? ?? false,
      overlay: map['overlay'] as bool? ?? false,
    );
  }
}

class ClipboardEventModel {
  final String text;
  final int timestamp;
  final bool isSensitive;
  final String sourcePackage;

  const ClipboardEventModel({
    required this.text,
    required this.timestamp,
    required this.isSensitive,
    required this.sourcePackage,
  });

  factory ClipboardEventModel.fromMap(Map<dynamic, dynamic> map) {
    return ClipboardEventModel(
      text: map['text'] as String? ?? '',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      isSensitive: map['isSensitive'] as bool? ?? false,
      sourcePackage: map['sourcePackage'] as String? ?? '',
    );
  }
}

class DiscoveredDeviceModel {
  final String id;
  final String name;
  final String host;
  final int port;
  final String fingerprint;
  final int lastSeen;

  const DiscoveredDeviceModel({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.lastSeen,
  });

  factory DiscoveredDeviceModel.fromMap(Map<dynamic, dynamic> map) {
    return DiscoveredDeviceModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'MacBook',
      host: map['host'] as String? ?? '',
      port: (map['port'] as num?)?.toInt() ?? 54321,
      fingerprint: map['fingerprint'] as String? ?? '',
      lastSeen: (map['lastSeen'] as num?)?.toInt() ?? 0,
    );
  }
}

class TransferEventModel {
  final String transferId;
  final String fileName;
  final String direction;
  final int fileIndex;
  final int totalFiles;
  final int progressPercent;
  final double speedMBs;
  final bool isCompleted;

  const TransferEventModel({
    required this.transferId,
    required this.fileName,
    required this.direction,
    required this.fileIndex,
    required this.totalFiles,
    required this.progressPercent,
    required this.speedMBs,
    required this.isCompleted,
  });

  double get progress => (progressPercent.clamp(0, 100)) / 100.0;
  String get filename => fileName;
  bool get isFailed => false;
  String get formattedSpeed => '${speedMBs.toStringAsFixed(1)} MB/s';
  String get formattedBytes => '$progressPercent%';

  factory TransferEventModel.fromMap(Map<dynamic, dynamic> map) {
    return TransferEventModel(
      transferId: map['transferId'] as String? ?? '',
      fileName: map['fileName'] as String? ?? 'File',
      direction: map['direction'] as String? ?? 'incoming',
      fileIndex: (map['fileIndex'] as num?)?.toInt() ?? 0,
      totalFiles: (map['totalFiles'] as num?)?.toInt() ?? 1,
      progressPercent: (map['progressPercent'] as num?)?.toInt() ?? 0,
      speedMBs: (map['speedMBs'] as num?)?.toDouble() ?? 0.0,
      isCompleted: map['isCompleted'] as bool? ?? false,
    );
  }
}

class BatteryStatusModel {
  final int level;
  final bool isCharging;
  final String powerSource;
  final int timestamp;

  const BatteryStatusModel({
    required this.level,
    required this.isCharging,
    required this.powerSource,
    required this.timestamp,
  });

  factory BatteryStatusModel.fromMap(Map<dynamic, dynamic> map) {
    return BatteryStatusModel(
      level: (map['level'] as num?)?.toInt() ?? 100,
      isCharging: map['isCharging'] as bool? ?? false,
      powerSource: map['powerSource'] as String? ?? 'battery',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
    );
  }
}

class OtpEventModel {
  final String serviceName;
  final String code;
  final int expiresIn;
  final int timestamp;

  const OtpEventModel({
    required this.serviceName,
    required this.code,
    required this.expiresIn,
    required this.timestamp,
  });

  factory OtpEventModel.fromMap(Map<dynamic, dynamic> map) {
    return OtpEventModel(
      serviceName: map['serviceName'] as String? ?? 'Service',
      code: map['code'] as String? ?? '',
      expiresIn: (map['expiresIn'] as num?)?.toInt() ?? 60,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
    );
  }
}

class PlatformBridge {
  static const MethodChannel _channel = MethodChannel('com.corda.app/channel');
  static const EventChannel _clipboardEventChannel =
      EventChannel('com.corda.app/clipboard_events');
  static const EventChannel _discoveryEventChannel =
      EventChannel('com.corda.app/discovery_events');
  static const EventChannel _transferEventChannel =
      EventChannel('com.corda.app/transfer_events');
  static const EventChannel _isolationEventChannel =
      EventChannel('com.corda.app/isolation_events');
  static const EventChannel _batteryEventChannel =
      EventChannel('com.corda.app/battery_events');
  static const EventChannel _otpEventChannel =
      EventChannel('com.corda.app/otp_events');

  static final PlatformBridge instance = PlatformBridge._internal();
  PlatformBridge._internal();

  Stream<ClipboardEventModel>? _clipboardStream;
  Stream<DiscoveredDeviceModel>? _discoveryStream;
  Stream<TransferEventModel>? _transferStream;
  Stream<bool>? _apIsolationStream;
  Stream<BatteryStatusModel>? _batteryStream;
  Stream<OtpEventModel>? _otpStream;

  Future<PermissionStatusModel> checkPermissions() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('checkPermissions');
      if (res != null) {
        return PermissionStatusModel.fromMap(res);
      }
    } catch (_) {}
    return const PermissionStatusModel(
      accessibility: false,
      batteryIgnored: false,
      notification: false,
    );
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  Future<void> openBatterySettings() async {
    try {
      await _channel.invokeMethod('openBatterySettings');
    } catch (_) {}
  }

  Future<void> openOverlaySettings() async {
    try {
      await _channel.invokeMethod('openOverlaySettings');
    } catch (_) {}
  }

  Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (_) {}
  }

  Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (_) {}
  }

  Future<bool> isServiceRunning() async {
    try {
      final res = await _channel.invokeMethod<bool>('isServiceRunning');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> triggerHaptic() async {
    try {
      await _channel.invokeMethod('triggerHaptic');
    } catch (_) {}
  }

  Future<Map<String, dynamic>> pairDevice({
    required String host,
    required int port,
    required String pin,
    required String fingerprint,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('pairDevice', {
        'host': host,
        'port': port,
        'pin': pin,
        'fingerprint': fingerprint,
      });
      if (res != null) {
        return {
          'success': res['success'] as bool? ?? false,
          'message': res['message'] as String? ?? '',
        };
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
    return {'success': false, 'message': 'Failed to connect to Mac'};
  }

  Stream<ClipboardEventModel> get clipboardStream {
    _clipboardStream ??= _clipboardEventChannel
        .receiveBroadcastStream()
        .map((data) => ClipboardEventModel.fromMap(data as Map<dynamic, dynamic>))
        .handleError((_) => null);
    return _clipboardStream!;
  }

  Stream<DiscoveredDeviceModel> get discoveryStream {
    _discoveryStream ??= _discoveryEventChannel
        .receiveBroadcastStream()
        .map((data) => DiscoveredDeviceModel.fromMap(data as Map<dynamic, dynamic>))
        .handleError((_) => null);
    return _discoveryStream!;
  }

  Future<bool> sendFile(String filePath) async {
    try {
      final res = await _channel.invokeMethod<bool>('sendFile', {'filePath': filePath});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Stream<TransferEventModel> get transferStream {
    _transferStream ??= _transferEventChannel
        .receiveBroadcastStream()
        .map((data) => TransferEventModel.fromMap(data as Map<dynamic, dynamic>))
        .handleError((_) => null);
    return _transferStream!;
  }

  Stream<bool> get apIsolationStream {
    _apIsolationStream ??= _isolationEventChannel
        .receiveBroadcastStream()
        .map((data) => data as bool? ?? false)
        .handleError((_) => false);
    return _apIsolationStream!;
  }

  Stream<BatteryStatusModel> get batteryStream {
    _batteryStream ??= _batteryEventChannel
        .receiveBroadcastStream()
        .map((data) => BatteryStatusModel.fromMap(data as Map<dynamic, dynamic>))
        .handleError((_) => null);
    return _batteryStream!;
  }

  Stream<OtpEventModel> get otpStream {
    _otpStream ??= _otpEventChannel
        .receiveBroadcastStream()
        .map((data) => OtpEventModel.fromMap(data as Map<dynamic, dynamic>))
        .handleError((_) => null);
    return _otpStream!;
  }

  Future<BatteryStatusModel?> getBatteryStatus() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getBatteryStatus');
      if (res != null) {
        return BatteryStatusModel.fromMap(res);
      }
    } catch (_) {}
    return null;
  }

  Future<List<TrustedDeviceModel>> getTrustedDevices() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('getTrustedDevices');
      if (res != null) {
        return res
            .map((e) => TrustedDeviceModel.fromMap(e as Map<dynamic, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> unpairDevice(String id) async {
    try {
      final res = await _channel.invokeMethod<bool>('unpairDevice', {'id': id});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getConnectionStatus() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getConnectionStatus');
      if (res != null) {
        return {
          'isConnected': res['isConnected'] as bool? ?? false,
          'connectedHost': res['connectedHost'] as String? ?? '',
          'connectedPort': (res['connectedPort'] as num?)?.toInt() ?? 0,
        };
      }
    } catch (_) {}
    return {'isConnected': false, 'connectedHost': '', 'connectedPort': 0};
  }

  Future<List<String>> pickFiles() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('pickFiles');
      if (res != null) {
        return res.cast<String>();
      }
    } catch (_) {}
    return [];
  }

  Future<NotificationSettingsModel> getNotificationSettings() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getNotificationSettings');
      if (res != null) {
        return NotificationSettingsModel.fromMap(res);
      }
    } catch (_) {}
    return const NotificationSettingsModel(masterEnabled: true, apps: []);
  }

  Future<bool> setNotificationMasterEnabled(bool enabled) async {
    try {
      final res = await _channel.invokeMethod<bool>('setNotificationMasterEnabled', {'enabled': enabled});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setNotificationPackageAllowed(String packageName, bool allowed) async {
    try {
      final res = await _channel.invokeMethod<bool>('setNotificationPackageAllowed', {
        'packageName': packageName,
        'allowed': allowed,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<InstalledAppModel>> getInstalledApps() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (res != null) {
        return res
            .map((e) => InstalledAppModel.fromMap(e as Map<dynamic, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> addNotificationPackage(String packageName, String appName) async {
    try {
      final res = await _channel.invokeMethod<bool>('addNotificationPackage', {
        'packageName': packageName,
        'appName': appName,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeNotificationPackage(String packageName) async {
    try {
      final res = await _channel.invokeMethod<bool>('removeNotificationPackage', {
        'packageName': packageName,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}

class InstalledAppModel {
  final String packageName;
  final String appName;
  final Uint8List? iconBytes;

  const InstalledAppModel({
    required this.packageName,
    required this.appName,
    this.iconBytes,
  });

  factory InstalledAppModel.fromMap(Map<dynamic, dynamic> map) {
    return InstalledAppModel(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
      iconBytes: map['iconBytes'] as Uint8List?,
    );
  }
}

class NotificationAppModel {
  final String packageName;
  final String appName;
  final bool isEnabled;
  final Uint8List? iconBytes;

  const NotificationAppModel({
    required this.packageName,
    required this.appName,
    required this.isEnabled,
    this.iconBytes,
  });

  factory NotificationAppModel.fromMap(Map<dynamic, dynamic> map) {
    return NotificationAppModel(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
      isEnabled: map['isEnabled'] as bool? ?? false,
      iconBytes: map['iconBytes'] as Uint8List?,
    );
  }
}

class NotificationSettingsModel {
  final bool masterEnabled;
  final List<NotificationAppModel> apps;

  const NotificationSettingsModel({
    required this.masterEnabled,
    required this.apps,
  });

  factory NotificationSettingsModel.fromMap(Map<dynamic, dynamic> map) {
    final rawApps = map['apps'] as List<dynamic>? ?? [];
    return NotificationSettingsModel(
      masterEnabled: map['masterEnabled'] as bool? ?? true,
      apps: rawApps.map((e) => NotificationAppModel.fromMap(e as Map<dynamic, dynamic>)).toList(),
    );
  }
}

class TrustedDeviceModel {
  final String id;
  final String name;
  final String platform;
  final String fingerprint;
  final String pairedAt;
  final bool isConnected;
  final String connectedHost;
  final int connectedPort;

  const TrustedDeviceModel({
    required this.id,
    required this.name,
    required this.platform,
    required this.fingerprint,
    required this.pairedAt,
    required this.isConnected,
    required this.connectedHost,
    required this.connectedPort,
  });

  factory TrustedDeviceModel.fromMap(Map<dynamic, dynamic> map) {
    return TrustedDeviceModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'MacBook',
      platform: map['platform'] as String? ?? 'macos',
      fingerprint: map['fingerprint'] as String? ?? '',
      pairedAt: map['pairedAt'] as String? ?? '',
      isConnected: map['isConnected'] as bool? ?? false,
      connectedHost: map['connectedHost'] as String? ?? '',
      connectedPort: (map['connectedPort'] as num?)?.toInt() ?? 0,
    );
  }
}

