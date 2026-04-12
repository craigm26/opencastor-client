import 'package:flutter_test/flutter_test.dart';
import 'package:opencastor_client/data/models/compliance.dart';

void main() {
  group('ComplianceStatus.fromJson', () {
    test('parses compliant status', () {
      final json = {
        'rrn': 'RRN-000000000001',
        'compliance_status': 'compliant',
        'fria_submitted_at': '2026-04-10T12:00:00Z',
        'sig_verified': true,
        'overall_pass': true,
        'prerequisite_waived': false,
      };
      final s = ComplianceStatus.fromJson(json);
      expect(s.rrn, 'RRN-000000000001');
      expect(s.complianceStatus, 'compliant');
      expect(s.friaSubmittedAt, '2026-04-10T12:00:00Z');
      expect(s.sigVerified, isTrue);
      expect(s.overallPass, isTrue);
      expect(s.prerequisiteWaived, isFalse);
    });

    test('handles null fria_submitted_at', () {
      final json = {
        'rrn': 'RRN-000000000001',
        'compliance_status': 'no_fria',
        'fria_submitted_at': null,
        'sig_verified': false,
        'overall_pass': false,
        'prerequisite_waived': false,
      };
      final s = ComplianceStatus.fromJson(json);
      expect(s.friaSubmittedAt, isNull);
      expect(s.complianceStatus, 'no_fria');
    });
  });

  group('FriaDocument.fromJson', () {
    test('parses document with conformance', () {
      final json = {
        'schema': 'rcan-fria-v1',
        'generated_at': '2026-04-12T00:00:00Z',
        'system': {'rrn': 'RRN-000000000001', 'rcan_version': '3.0'},
        'deployment': {'annex_iii_basis': 'high-risk', 'prerequisite_waived': false},
        'signing_key': {'alg': 'ml-dsa-65', 'kid': 'k1', 'public_key': 'AAAA'},
        'sig': {'alg': 'ml-dsa-65', 'kid': 'k1', 'value': 'BBBB'},
        'conformance': {
          'score': 0.95,
          'pass_count': 19,
          'warn_count': 1,
          'fail_count': 0,
        },
      };
      final doc = FriaDocument.fromJson(json);
      expect(doc.schema, 'rcan-fria-v1');
      expect(doc.conformance, isNotNull);
      expect(doc.conformance!.passCount, 19);
      expect(doc.conformance!.failCount, 0);
      expect(doc.conformance!.score, closeTo(0.95, 0.001));
    });

    test('parses document without conformance', () {
      final json = {
        'schema': 'rcan-fria-v1',
        'generated_at': '2026-04-12T00:00:00Z',
        'system': <String, dynamic>{},
        'deployment': <String, dynamic>{},
        'signing_key': {'alg': 'ml-dsa-65', 'kid': 'k1', 'public_key': 'AAAA'},
        'sig': <String, dynamic>{},
        'conformance': null,
      };
      final doc = FriaDocument.fromJson(json);
      expect(doc.conformance, isNull);
    });
  });
}
