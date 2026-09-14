import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'code_classifier.dart';
import 'scan_result.dart';

void main() => runApp(const CannabisScannerApp());

class CannabisScannerApp extends StatelessWidget {
  const CannabisScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Paperplanes Package Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5E4E)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paperplanes Package Scanner')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Point the camera at the package. The scanner captures the '
                'UPC and the QR / Retail ID together, then combines them.',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan package'),
              onPressed: () async {
                final result =
                    await Navigator.of(context).push<NormalizedScanResult>(
                  MaterialPageRoute(builder: (_) => const ScannerPage()),
                );
                if (result != null && context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => ResultPage(result: result)),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Aggregating scanner: collects every code visible (QR + 1D), shows live
/// chips of captures, and finishes automatically once it has both a QR-side
/// code and a retail barcode (after a short grace window), or when the user
/// taps Done. Camera is stopped before navigating away.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: [
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
    ],
    detectionSpeed: DetectionSpeed.normal, // keep firing so we catch all codes
  );

  /// Captured codes, keyed by raw payload.
  final Map<String, Barcode> _captured = {};

  Timer? _graceTimer;
  bool _finishing = false;

  static const _graceWindow = Duration(milliseconds: 2500);

  bool get _hasQr => _captured.values.any((b) =>
      b.format == BarcodeFormat.qrCode || b.format == BarcodeFormat.dataMatrix);

  bool get _hasRetail => _captured.values.any((b) => const {
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
      }.contains(b.format));

  @override
  void dispose() {
    _graceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_finishing) return;
    var added = false;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      if (!_captured.containsKey(raw)) {
        _captured[raw] = b;
        added = true;
      }
    }
    if (!added) return;
    setState(() {});

    // Once we hold both halves (SKU + QR), give the camera a short grace
    // window to pick up any remaining codes, then finish automatically.
    if (_hasQr && _hasRetail) {
      _graceTimer ??= Timer(_graceWindow, _finish);
    }
  }

  Future<void> _finish() async {
    if (_finishing || _captured.isEmpty) return;
    _finishing = true;
    _graceTimer?.cancel();
    await _controller.stop(); // close the camera before leaving
    final result = await CodeClassifier.normalize(_captured.values);
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final chips = _captured.values
        .map((b) => CodeClassifier.classify(b))
        .toList()
      ..sort((a, b) => b.codeClass.index.compareTo(a.codeClass.index));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan package'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Center(
              child: Text(
                'Camera error: ${error.errorCode.name}\n'
                'Check that camera permission is granted.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          // Guidance + live capture chips.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (chips.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final c in chips)
                            Chip(
                              avatar: Icon(
                                c.isQr ? Icons.qr_code_2 : Icons.view_week,
                                size: 18,
                              ),
                              label: Text(c.codeClass.label),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Text(
                      _captured.isEmpty
                          ? 'Rotate the jar so both the QR code and the '
                            'barcode pass in front of the camera'
                          : _hasQr && _hasRetail
                              ? 'Got both — finishing…'
                              : _hasQr
                                  ? 'QR captured — now find the UPC barcode'
                                  : 'Barcode captured — now find the QR code',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _captured.isEmpty ? null : _finish,
                      child: Text('Done (${_captured.length})'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the normalized scan result: SKU identity, batch/COA info, and
/// every captured code with its classification and usefulness.
class ResultPage extends StatelessWidget {
  const ResultPage({super.key, required this.result});

  final NormalizedScanResult result;

  Future<void> _open(BuildContext context, Uri url) async {
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final batch = result.batch;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan result')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Product identity (SKU level) ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Product', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  if (result.hasProductIdentity) ...[
                    Text(result.productName!,
                        style: theme.textTheme.headlineSmall),
                    if (result.brand != null)
                      Text(result.brand!, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (result.category != null)
                      _InfoRow('Category', result.category!),
                    if (result.size != null) _InfoRow('Size', result.size!),
                    if (result.origin != null)
                      _InfoRow('Origin', result.origin!),
                    if (result.sku != null) _InfoRow('UPC', result.sku!),
                    if (result.description != null) ...[
                      const SizedBox(height: 8),
                      Text(result.description!),
                    ],
                  ] else if (result.sku != null) ...[
                    Text('Unknown SKU', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    SelectableText('UPC: ${result.sku}'),
                    const Text('Decoded, but not in the product database.'),
                  ] else ...[
                    Text('No retail barcode captured',
                        style: theme.textTheme.titleMedium),
                    const Text(
                        'Product identity comes from the UPC — rescan with '
                        'the barcode visible to identify the SKU.'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ---- Batch / regulated unit (QR level) ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Batch & lab data', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  if (batch.isEmpty)
                    const Text(
                        'No batch-level code captured. On NY packaging, the '
                        'Metrc Retail ID QR (or COA QR) carries lot, potency '
                        'and lab-result data — rescan with the QR visible.')
                  else ...[
                    if (batch.source != null)
                      _InfoRow('Source', batch.source!.label),
                    if (batch.lotId != null) _InfoRow('Lot ID', batch.lotId!),
                    const SizedBox(height: 8),
                    if (batch.retailIdUrl != null)
                      FilledButton.icon(
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text(
                            'Open Retail ID (batch, potency, COA)'),
                        onPressed: () => _open(context, batch.retailIdUrl!),
                      ),
                    if (batch.coaUrl != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Open Certificate of Analysis'),
                        onPressed: () => _open(context, batch.coaUrl!),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ---- Every captured code, ranked ----
          Text('Captured codes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final c in result.codes)
            Card(
              child: ListTile(
                leading: Icon(c.isQr ? Icons.qr_code_2 : Icons.view_week),
                title: Text(c.codeClass.label),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      c.rawValue,
                      maxLines: 2,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (c.notes != null)
                      Text(c.notes!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontStyle: FontStyle.italic)),
                  ],
                ),
                trailing: Chip(
                  label: Text(c.codeClass.usefulness),
                  visualDensity: VisualDensity.compact,
                ),
                onTap: c.url == null ? null : () => _open(context, c.url!),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
