/// Fetches the latest OpenCastor runtime release from GitHub.
///
/// Caches the result in-memory for 1 hour to avoid hammering the API.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

class GitHubReleaseService {
  static const _url =
      'https://api.github.com/repos/craigm26/OpenCastor/releases/latest';
  static const _cacheDuration = Duration(hours: 1);

  static String? _cached;
  static DateTime? _cachedAt;

  /// Returns the tag name of the latest release (e.g. `"2026.3.17.1"`),
  /// or `null` if the request fails.
  ///
  /// Strips a leading `v` if present so comparisons against
  /// `robot.opencastorVersion` work correctly.
  static Future<String?> getLatestVersion() async {
    final now = DateTime.now();
    if (_cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheDuration) {
      return _cached;
    }

    try {
      final resp = await http
          .get(Uri.parse(_url), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      var tag = json['tag_name'] as String?;
      if (tag == null) return null;
      if (tag.startsWith('v')) tag = tag.substring(1);

      _cached = tag;
      _cachedAt = now;
      return tag;
    } catch (_) {
      return null;
    }
  }
}
