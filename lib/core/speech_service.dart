/// SpeechService — wraps speech_to_text with graceful web degradation.
///
/// On web: speech recognition is not available via the speech_to_text package;
/// calls return false / no-op and callers show a user-facing message.
///
/// Usage:
///   final svc = SpeechService();
///   await svc.initialize();
///   svc.startListening(onResult: (text) => setState(() => _input = text));
///   svc.stopListening();
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  bool _listening = false;

  bool get isListening => _listening;

  /// Returns true if STT is available on this platform.
  bool get isAvailableOnPlatform => !kIsWeb;

  /// Initialize the speech recognizer. Returns true on success.
  Future<bool> initialize() async {
    if (kIsWeb) return false;
    if (_initialized) return true;
    _initialized = await _stt.initialize(
      onError: (_) => _listening = false,
      onStatus: (status) {
        if (status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) {
          _listening = false;
        }
      },
    );
    return _initialized;
  }

  /// Start listening and call [onResult] with partial/final recognized text.
  /// Call [onDone] when recognition ends (timeout or stop).
  Future<void> startListening({
    required void Function(String text) onResult,
    void Function()? onDone,
  }) async {
    if (kIsWeb || !_initialized) return;
    _listening = true;
    await _stt.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
        if (result.finalResult) {
          _listening = false;
          onDone?.call();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      localeId: 'en_US',
      listenOptions: SpeechListenOptions(partialResults: true),
    );
  }

  /// Stop listening early.
  Future<void> stopListening() async {
    if (kIsWeb) return;
    _listening = false;
    await _stt.stop();
  }

  /// Dispose the service.
  void dispose() {
    _stt.cancel();
  }
}
