import 'package:logger/logger.dart';

/// Centralised logger for the OpenCastor client app.
///
/// Usage:
///   import 'package:opencastor_client/core/app_logger.dart';
///   log.d('debug message');
///   log.i('info message');
///   log.w('warning');
///   log.e('error', error: e, stackTrace: st);
///
/// Logs appear in the browser DevTools console under:
///   - Verbose (debug)
///   - Info
///   - Warnings
///   - Errors
final log = Logger(
  printer: PrettyPrinter(
    methodCount: 1,       // lines of call stack to show
    errorMethodCount: 5,  // lines for errors
    lineLength: 90,
    colors: false,        // colors break in browser console
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
  level: Level.debug,
);
