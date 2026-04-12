/// HTTP client for the rcan.dev compliance API.
///
/// Implements [ComplianceRepository] using the `http` package.
/// Base URL: https://rcan.dev/api/v1
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/compliance.dart';
import '../repositories/compliance_repository.dart';

class RcanComplianceService implements ComplianceRepository {
  static const _base = 'https://rcan.dev/api/v1';

  const RcanComplianceService();

  @override
  Future<ComplianceStatus> getComplianceStatus(String rrn) async {
    final uri = Uri.parse('$_base/robots/$rrn/compliance');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'rcan.dev /compliance returned ${response.statusCode} for $rrn',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ComplianceStatus.fromJson(json);
  }

  @override
  Future<FriaDocument?> getFriaDocument(String rrn) async {
    final uri = Uri.parse('$_base/robots/$rrn/fria');
    final response = await http.get(uri);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception(
        'rcan.dev /fria returned ${response.statusCode} for $rrn',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return FriaDocument.fromJson(json);
  }
}
