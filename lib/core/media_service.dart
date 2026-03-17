/// MediaService — unified image picking for mobile + web.
///
/// Mobile: image_picker (camera + gallery)
/// Web:    file_picker with image filter (no camera on most web browsers)
library;

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

class MediaService {
  final ImagePicker _picker = ImagePicker();

  /// Pick an image. Returns raw bytes or null if user cancelled / error.
  ///
  /// [fromCamera] is ignored on web (opens file picker instead).
  Future<Uint8List?> pickImage({bool fromCamera = false}) async {
    try {
      if (kIsWeb) {
        return _pickFromFilePickerWeb();
      } else {
        return _pickFromImagePicker(fromCamera: fromCamera);
      }
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _pickFromImagePicker({required bool fromCamera}) async {
    final source = fromCamera ? ImageSource.camera : ImageSource.gallery;
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  Future<Uint8List?> _pickFromFilePickerWeb() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.first.bytes;
  }
}
