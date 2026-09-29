import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/platform_bridge.dart';
import '../theme/corda_theme.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with SingleTickerProviderStateMixin {
  late MobileScannerController _controller;
  late AnimationController _animController;
  late Animation<double> _scanAnimation;

  bool _isProcessingCode = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessingCode) return;

    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.isNotEmpty) {
        setState(() => _isProcessingCode = true);
        PlatformBridge.instance.triggerHaptic();
        _handleScannedData(code);
        break;
      }
    }
  }

  void _handleScannedData(String rawData) {
    // Parse either corda://pair?id=...&name=...&fp=...&pin=... or raw string
    String deviceName = 'MacBook Pro';
    String deviceId = '';
    String fingerprint = '';
    String pin = '';
    String host = '';
    int port = 54321;

    if (rawData.startsWith('corda://pair')) {
      try {
        final uri = Uri.parse(rawData);
        deviceId = uri.queryParameters['id'] ?? '';
        deviceName = uri.queryParameters['name'] ?? 'MacBook';
        fingerprint = uri.queryParameters['fp'] ?? '';
        pin = uri.queryParameters['pin'] ?? '';
        host = uri.queryParameters['host'] ?? '';
        port = int.tryParse(uri.queryParameters['port'] ?? '54321') ?? 54321;
      } catch (_) {
        deviceName = rawData;
      }
    } else {
      pin = rawData;
    }

    _showPairConfirmation(
      deviceName: deviceName,
      deviceId: deviceId,
      fingerprint: fingerprint,
      pin: pin,
      host: host,
      port: port,
    );
  }

  void _showPairConfirmation({
    required String deviceName,
    required String deviceId,
    required String fingerprint,
    required String pin,
    String host = '',
    int port = 54321,
  }) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: CordaTheme.surfaceSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: CordaTheme.borderSubtle),
                      ),
                      child: const Icon(
                        Icons.laptop_mac_rounded,
                        color: CordaTheme.accentBlue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deviceName.isNotEmpty ? deviceName : 'Mac Discovered',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Pair Device',
                            style: TextStyle(fontSize: 12, color: CordaTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Allow this Mac to sync clipboard and transfer files securely with your phone.',
                  style: TextStyle(fontSize: 12, color: CordaTheme.textSecondary, height: 1.3),
                ),
                const SizedBox(height: 16),
                if (pin.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: CordaTheme.surfaceSubtle,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: CordaTheme.borderSubtle),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'VERIFICATION CODE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: CordaTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pin,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 6,
                            color: CordaTheme.accentBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: CordaTheme.borderSubtle),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            setState(() => _isProcessingCode = false);
                          },
                          child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CordaTheme.accentBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            final targetHost = host.isNotEmpty ? host : '127.0.0.1';

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
                                    Text('Connecting to $deviceName...'),
                                  ],
                                ),
                                duration: const Duration(seconds: 5),
                              ),
                            );

                            final result = await PlatformBridge.instance.pairDevice(
                              host: targetHost,
                              port: port,
                              pin: pin,
                              fingerprint: fingerprint,
                            );

                            if (mounted) {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              if (result['success'] == true) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: CordaTheme.mintGreen,
                                    content: Text('Successfully paired with $deviceName!'),
                                  ),
                                );
                                Navigator.of(context).pop(true);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: Colors.redAccent,
                                    content: Text(result['message']?.toString() ?? 'Pairing failed'),
                                  ),
                                );
                                setState(() => _isProcessingCode = false);
                              }
                            }
                          },
                          child: const Text('Pair', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showManualPinDialog() {
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.pin_rounded, color: CordaTheme.accentBlue),
              SizedBox(width: 10),
              Text('Enter 6-Digit PIN'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the 6-digit code shown in Corda on your Mac.',
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
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: TextStyle(
                    letterSpacing: 8,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CordaTheme.accentBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final pin = pinController.text.trim();
                if (pin.length == 6) {
                  Navigator.of(ctx).pop();
                  _showPairConfirmation(
                    deviceName: 'MacBook Pro (Manual PIN)',
                    deviceId: 'manual-pin',
                    fingerprint: '',
                    pin: pin,
                  );
                }
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Mobile Scanner Camera View
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Custom Viewfinder Overlay with Animated Aqua Laser
          AnimatedBuilder(
            animation: _scanAnimation,
            builder: (context, child) {
              return CustomPaint(
                painter: _ViewfinderOverlayPainter(
                  scanPercent: _scanAnimation.value,
                ),
                child: Container(),
              );
            },
          ),

          // Top Action Controls (Back, Flashlight, Switch Camera)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        child: IconButton(
                          icon: Icon(
                            _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                            color: _isTorchOn ? CordaTheme.amberWarning : Colors.white,
                          ),
                          onPressed: () async {
                            await _controller.toggleTorch();
                            setState(() {
                              _isTorchOn = !_isTorchOn;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        child: IconButton(
                          icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
                          onPressed: () => _controller.switchCamera(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom Prompt & Manual PIN Button
          Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, color: CordaTheme.accentBlue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Point camera at the QR code on your Mac',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _showManualPinDialog,
                    icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                    label: const Text('Enter PIN Manually (6-Digit)'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewfinderOverlayPainter extends CustomPainter {
  final double scanPercent;

  _ViewfinderOverlayPainter({required this.scanPercent});

  @override
  void paint(Canvas canvas, Size size) {
    const boxSize = 260.0;
    final left = (size.width - boxSize) / 2;
    final top = (size.height - boxSize) / 2.3;
    final rect = Rect.fromLTWH(left, top, boxSize, boxSize);

    // Dark semi-transparent background cutout
    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.62);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, bgPaint);

    // Border squircle with Aqua glow
    final borderPaint = Paint()
      ..color = CordaTheme.aquaPrimary.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)), borderPaint);

    // Corner accents
    final cornerPaint = Paint()
      ..color = CordaTheme.aquaCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    const cornerLength = 32.0;

    // Top-Left
    canvas.drawLine(Offset(left, top + 18), Offset(left, top + 18 + cornerLength), cornerPaint);
    canvas.drawLine(Offset(left + 18, top), Offset(left + 18 + cornerLength, top), cornerPaint);

    // Top-Right
    canvas.drawLine(Offset(left + boxSize, top + 18), Offset(left + boxSize, top + 18 + cornerLength), cornerPaint);
    canvas.drawLine(Offset(left + boxSize - 18, top), Offset(left + boxSize - 18 - cornerLength, top), cornerPaint);

    // Bottom-Left
    canvas.drawLine(Offset(left, top + boxSize - 18), Offset(left, top + boxSize - 18 - cornerLength), cornerPaint);
    canvas.drawLine(Offset(left + 18, top + boxSize), Offset(left + 18 + cornerLength, top + boxSize), cornerPaint);

    // Bottom-Right
    canvas.drawLine(Offset(left + boxSize, top + boxSize - 18), Offset(left + boxSize, top + boxSize - 18 - cornerLength), cornerPaint);
    canvas.drawLine(Offset(left + boxSize - 18, top + boxSize), Offset(left + boxSize - 18 - cornerLength, top + boxSize), cornerPaint);

    // Scanning animated laser line
    final laserY = top + (boxSize * scanPercent);
    final laserPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          CordaTheme.aquaPrimary.withValues(alpha: 0.0),
          CordaTheme.aquaCyan,
          CordaTheme.aquaPrimary.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(left + 10, laserY, boxSize - 20, 2))
      ..strokeWidth = 2.5;

    canvas.drawLine(Offset(left + 16, laserY), Offset(left + boxSize - 16, laserY), laserPaint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderOverlayPainter oldDelegate) {
    return oldDelegate.scanPercent != scanPercent;
  }
}
