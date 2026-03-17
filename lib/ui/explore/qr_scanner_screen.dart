import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// QR scanner screen for scanning castor install QR codes.
///
/// Scans codes in the format:
///   castor install opencastor.com/config/<id>
///
/// On success, navigates to /explore/:id for confirmation before installing.
///
/// Platform notes:
///   - Requires camera permission (handled by mobile_scanner package)
///   - Falls back to manual URL entry if camera unavailable
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _manualCtrl = TextEditingController();
  bool _useManual = false;
  String? _error;

  static const _prefix = 'castor install opencastor.com/config/';
  static const _altPrefix = 'https://opencastor.com/config/';

  String? _extractConfigId(String raw) {
    raw = raw.trim();
    if (raw.startsWith(_prefix)) {
      return raw.substring(_prefix.length).split(' ').first;
    }
    if (raw.startsWith(_altPrefix)) {
      return raw.substring(_altPrefix.length).split('/').first;
    }
    // Plain ID
    if (RegExp(r'^[a-z0-9-]{4,30}$').hasMatch(raw)) return raw;
    return null;
  }

  void _handleScanned(String raw) {
    final id = _extractConfigId(raw);
    if (id != null && mounted) {
      context.go('/explore/$id');
    } else {
      setState(() => _error = 'Not a valid OpenCastor config QR code');
    }
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Config QR'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _useManual = !_useManual),
            child: Text(_useManual ? 'Camera' : 'Type URL'),
          ),
        ],
      ),
      body: _useManual ? _ManualEntry(
        controller: _manualCtrl,
        error: _error,
        onSubmit: _handleScanned,
      ) : _CameraPlaceholder(
        onManualFallback: () => setState(() => _useManual = true),
        // TODO: swap this placeholder with mobile_scanner MobileScanner widget
        // when mobile_scanner is added to pubspec.yaml:
        //
        //   MobileScanner(
        //     onDetect: (capture) {
        //       final barcode = capture.barcodes.firstOrNull;
        //       if (barcode?.rawValue != null) _handleScanned(barcode!.rawValue!);
        //     },
        //   )
      ),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder({required this.onManualFallback});
  final VoidCallback onManualFallback;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: cs.primary, width: 2),
              borderRadius: BorderRadius.circular(16),
              color: cs.surfaceContainerHighest,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_scanner, size: 64, color: cs.primary),
                const SizedBox(height: 12),
                Text(
                  'Camera scanner\ncoming soon',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: onManualFallback,
            child: const Text('Enter URL or ID manually'),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan QR codes from opencastor.com/config/:id',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ManualEntry extends StatelessWidget {
  const _ManualEntry({
    required this.controller,
    required this.error,
    required this.onSubmit,
  });
  final TextEditingController controller;
  final String? error;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter a config ID or URL',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Config ID or URL',
              hintText: 'e.g. bob-pi4-oakd or opencastor.com/config/...',
              border: const OutlineInputBorder(),
              errorText: error,
            ),
            onSubmitted: onSubmit,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => onSubmit(controller.text),
              child: const Text('Open Config'),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Accepted formats:\n'
            '• castor install opencastor.com/config/<id>\n'
            '• https://opencastor.com/config/<id>\n'
            '• Plain config ID (e.g. bob-pi4-oakd)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
