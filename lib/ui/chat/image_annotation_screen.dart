/// ImageAnnotationScreen — WhatsApp-style image annotation before sending.
///
/// Push this screen after picking an image; it returns an [ImageAnnotationResult]
/// via [Navigator.pop] that contains the image bytes and optional annotation text.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Returned by [ImageAnnotationScreen] via [Navigator.pop].
class ImageAnnotationResult {
  final Uint8List imageBytes;
  final String annotation;

  const ImageAnnotationResult({
    required this.imageBytes,
    required this.annotation,
  });
}

class ImageAnnotationScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const ImageAnnotationScreen({super.key, required this.imageBytes});

  @override
  State<ImageAnnotationScreen> createState() => _ImageAnnotationScreenState();
}

class _ImageAnnotationScreenState extends State<ImageAnnotationScreen> {
  final _captionCtrl = TextEditingController();

  static const _quickLabels = [
    ('🔧', 'Mechanical'),
    ('📦', 'Object'),
    ('⚠️', 'Issue'),
    ('🎯', 'Target'),
    ('📍', 'Location'),
  ];

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  void _appendLabel(String label) {
    final current = _captionCtrl.text;
    if (current.isEmpty) {
      _captionCtrl.text = label;
    } else {
      _captionCtrl.text = '$current, $label';
    }
    _captionCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _captionCtrl.text.length),
    );
  }

  void _submit() {
    Navigator.of(context).pop(ImageAnnotationResult(
      imageBytes: widget.imageBytes,
      annotation: _captionCtrl.text.trim(),
    ));
  }

  void _attachWithoutCaption() {
    Navigator.of(context).pop(ImageAnnotationResult(
      imageBytes: widget.imageBytes,
      annotation: '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Annotate Image'),
        actions: [
          TextButton(
            onPressed: _submit,
            child: Text(
              'Send',
              style: TextStyle(
                  color: cs.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Image preview ──────────────────────────────────────────────
            Expanded(
              child: Container(
                color: Colors.black,
                width: double.infinity,
                child: Image.memory(
                  widget.imageBytes,
                  fit: BoxFit.contain,
                ),
              ),
            ),

            // ── Annotation area ────────────────────────────────────────────
            Container(
              color: cs.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Caption text field
                  TextField(
                    controller: _captionCtrl,
                    decoration: InputDecoration(
                      hintText: 'Add a caption…',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 10),

                  // Quick label chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _quickLabels
                        .map(
                          (pair) => ActionChip(
                            label: Text('${pair.$1} ${pair.$2}'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _appendLabel(pair.$2),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),

                  // Attach without caption
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _attachWithoutCaption,
                      child: const Text('Attach without caption'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
