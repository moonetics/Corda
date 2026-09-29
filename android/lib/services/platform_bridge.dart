import 'dart:async';
import 'package:flutter/services.dart';

class PermissionStatusModel {
  final bool accessibility;
  final bool batteryIgnored;
  final bool notification;

  const PermissionStatusModel({
    required this.accessibility,
    required this.batteryIgnored,
    required this.notification,
  });

  bool get isAllGranted => accessibility && batteryIgnored && notification;

  factory PermissionStatusModel.fromMap(Map<dynamic, dynamic> map) {
    return PermissionStatusModel(
      accessibility: map['accessibility'] as bool? ?? false,
      batteryIgnored: map['batteryIgnored'] as bool? ?? false,
      notification: map['notification'] as bool? ?? false,
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

class PlatformBridge {
  static const MethodChannel _channel = MethodChannel('com.corda.app/channel');
  static const EventChannel _clipboardEventChannel =
      EventChannel('com.corda.app/clipboard_events');
  static const EventChannel _discoveryEventChannel =
      EventChannel('com.corda.app/discovery_events');

  static final PlatformBridge instance = PlatformBridge._internal();
  PlatformBridge._internal();

  Stream<ClipboardEventModel>? _clipboardStream;
  Stream<DiscoveredDeviceModel>? _discoveryStream;

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
}
