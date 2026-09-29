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
          'File Transfers',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            // Send Files Action Card
            SonomaCard(
              padding: const EdgeInsets.all(20),
              onTap: _isPicking ? null : _pickAndSendFiles,
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: CordaTheme.surfaceSubtle,
                      shape: BoxShape.circle,
                      border: Border.all(color: CordaTheme.borderSubtle),
                    ),
                    child: _isPicking
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: CordaTheme.accentBlue),
                            ),
                          )
                        : const Icon(
                            CupertinoIcons.cloud_upload_fill,
                            color: CordaTheme.accentBlue,
                            size: 26,
                          ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Send Files to Mac',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tap to select photos, videos, archives, or documents',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: CordaTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: CordaTheme.surfaceSubtle,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: CordaTheme.borderSubtle),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.bolt_fill,
                          color: CordaTheme.mintGreen,
                          size: 12,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Direct TCP Port 54322 • 256KB Chunks',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: CordaTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Active Transfer Status Card
            _buildSectionTitle('ACTIVE STREAM'),
            const SizedBox(height: 8),
            _buildActiveTransferCard(),

            const SizedBox(height: 20),

            // Recent Session Transfers
            _buildSectionTitle('SESSION HISTORY'),
            const SizedBox(height: 8),
            _buildCompletedTransfersList(),
          ],
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

  Widget _buildActiveTransferCard() {
    final transfer = _activeTransfer;
    final isActive = transfer != null && !transfer.isCompleted;

    if (!isActive) {
      return SonomaCard(
        padding: const EdgeInsets.all(14),
        child: const Row(
          children: [
            Icon(CupertinoIcons.checkmark_circle, color: CordaTheme.textMuted, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No active file stream. Select a file above to begin sending.',
                style: TextStyle(
                  fontSize: 12,
                  color: CordaTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isIncoming = transfer.direction == 'inbound';
    final progressPct = (transfer.progress * 100).toInt();

    return SonomaCard(
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
                child: Icon(
                  isIncoming ? CupertinoIcons.arrow_down_doc_fill : CupertinoIcons.arrow_up_doc_fill,
                  color: CordaTheme.accentBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.filename,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isIncoming ? 'Receiving from Mac' : 'Sending to Mac',
                      style: const TextStyle(
                        fontSize: 11,
                        color: CordaTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$progressPct%',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: CordaTheme.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: transfer.progress,
              backgroundColor: CordaTheme.surfaceSubtle,
              valueColor: const AlwaysStoppedAnimation<Color>(CordaTheme.accentBlue),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                transfer.formattedBytes,
                style: const TextStyle(fontSize: 11, color: CordaTheme.textSecondary),
              ),
              Text(
                transfer.formattedSpeed,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: CordaTheme.mintGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedTransfersList() {
    if (_completedTransfers.isEmpty) {
      return SonomaCard(
        padding: const EdgeInsets.all(14),
        child: const Row(
          children: [
            Icon(CupertinoIcons.clock, color: CordaTheme.textMuted, size: 16),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Transferred files this session will appear here.',
                style: TextStyle(fontSize: 12, color: CordaTheme.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _completedTransfers.map((item) {
        final isSuccess = !item.isFailed;
        return SonomaCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                isSuccess ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.xmark_circle_fill,
                color: isSuccess ? CordaTheme.mintGreen : CordaTheme.roseDanger,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.filename,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.formattedBytes} • ${item.direction == 'inbound' ? 'From Mac' : 'To Mac'}',
                      style: const TextStyle(fontSize: 11, color: CordaTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(
                isSuccess ? 'Completed' : 'Failed',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSuccess ? CordaTheme.mintGreen : CordaTheme.roseDanger,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
