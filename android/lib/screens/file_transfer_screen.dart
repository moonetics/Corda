import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/platform_bridge.dart';
import '../theme/corda_theme.dart';

class FileTransferScreen extends StatefulWidget {
  const FileTransferScreen({super.key});

  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends State<FileTransferScreen> {
  StreamSubscription<TransferEventModel>? _transferSub;
  TransferEventModel? _activeTransfer;
  final List<TransferEventModel> _completedTransfers = [];
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _listenToTransfers();
  }

  void _listenToTransfers() {
    _transferSub = PlatformBridge.instance.transferStream.listen((event) {
      if (!mounted) return;
      setState(() {
        _activeTransfer = event;
        if (event.isCompleted) {
          _completedTransfers.insert(0, event);
          PlatformBridge.instance.triggerHaptic();
        }
      });
    });
  }

  @override
  void dispose() {
    _transferSub?.cancel();
    super.dispose();
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
            backgroundColor: CordaTheme.obsidianGlass,
            content: Row(
              children: [
                const Icon(CupertinoIcons.paperplane_fill, color: CordaTheme.aquaCyan, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Mengirim ${filePaths.length} berkas ke Mac...',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: CordaTheme.obsidianGlassBorder),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
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
                    CupertinoIcons.arrow_up_arrow_down_circle_fill,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Transfer Berkas',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Streaming Berkecepatan Tinggi via Wi-Fi Lokal',
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

            // Kirim Berkas Action Card
            LiquidGlassCard(
              glow: true,
              padding: const EdgeInsets.all(24),
              onTap: _isPicking ? null : _pickAndSendFiles,
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: CordaTheme.aquaGradient,
                      boxShadow: [
                        BoxShadow(
                          color: CordaTheme.aquaCyan.withValues(alpha: 0.4),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: _isPicking
                        ? const Center(
                            child: CupertinoActivityIndicator(
                              color: Colors.white,
                              radius: 14,
                            ),
                          )
                        : const Icon(
                            CupertinoIcons.cloud_upload_fill,
                            color: Colors.white,
                            size: 34,
                          ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Kirim Berkas ke Mac',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ketuk untuk memilih foto, video, arsip, atau dokumen',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.bolt_fill,
                          color: CordaTheme.aquaCyan,
                          size: 14,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Data Channel 54322 • Chunking 256KB',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: CordaTheme.aquaCyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Active Transfer Status Card
            _buildSectionTitle('STATUS STREAMING SAAT INI'),
            const SizedBox(height: 10),
            _buildActiveTransferCard(),

            const SizedBox(height: 24),

            // Riwayat Transfer
            _buildSectionTitle('RIWAYAT TRANSFER SESI INI'),
            const SizedBox(height: 10),
            _buildCompletedTransfersList(),
          ],
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

  Widget _buildActiveTransferCard() {
    final transfer = _activeTransfer;
    final isActive = transfer != null && !transfer.isCompleted;

    if (!isActive) {
      return LiquidGlassCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                CupertinoIcons.circle_grid_hex_fill,
                color: Colors.white38,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Saluran Streaming Siaga',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Menunggu pengiriman dari Mac atau Android',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: CordaTheme.mintGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Siap',
                style: TextStyle(
                  color: CordaTheme.mintGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isIncoming = transfer.direction == 'incoming';
    final progressFraction = (transfer.progressPercent / 100.0).clamp(0.0, 1.0);

    return LiquidGlassCard(
      glow: true,
      borderColor: CordaTheme.aquaCyan.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: CordaTheme.aquaGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isIncoming
                      ? CupertinoIcons.arrow_down_doc_fill
                      : CupertinoIcons.arrow_up_doc_fill,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isIncoming ? 'Menerima dari Mac' : 'Mengirim ke Mac',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${transfer.progressPercent}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: CordaTheme.aquaCyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progressFraction,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(CordaTheme.aquaCyan),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Berkas ${transfer.fileIndex + 1} dari ${transfer.totalFiles}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.speedometer,
                    size: 14,
                    color: CordaTheme.mintGreen,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${transfer.speedMBs.toStringAsFixed(1)} MB/s',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CordaTheme.mintGreen,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedTransfersList() {
    if (_completedTransfers.isEmpty) {
      return LiquidGlassCard(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: Column(
            children: [
              Icon(
                CupertinoIcons.tray_fill,
                size: 32,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 10),
              Text(
                'Belum ada riwayat transfer',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LiquidGlassCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: _completedTransfers.take(8).map((item) {
          final isIncoming = item.direction == 'incoming';
          return ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isIncoming ? CordaTheme.mintGreen : CordaTheme.aquaPrimary)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isIncoming ? CupertinoIcons.arrow_down : CupertinoIcons.arrow_up,
                color: isIncoming ? CordaTheme.mintGreen : CordaTheme.aquaCyan,
                size: 16,
              ),
            ),
            title: Text(
              item.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
            subtitle: Text(
              isIncoming ? 'Diterima di Download/Corda' : 'Terkirim ke Mac',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            trailing: const Icon(
              CupertinoIcons.checkmark_alt_circle_fill,
              color: CordaTheme.mintGreen,
              size: 20,
            ),
          );
        }).toList(),
      ),
    );
  }
}
