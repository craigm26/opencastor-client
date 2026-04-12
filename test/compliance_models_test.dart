import 'package:flutter_test/flutter_test.dart';
import 'package:opencastor_client/data/models/compliance.dart';

void main() {
  group('ComplianceStatus.fromJson', () {
    test('parses rcan.dev API response (nested fria object)', () {
      // Actual shape returned by GET /api/v1/robots/:rrn/compliance
      final json = {
        'rrn': 'RRN-000000000001',
        'verification_tier': 'community',
        'compliance_status': 'compliant',
        'checked_at': '2026-04-12T00:00:00Z',
        'fria': {
          'submitted_at': '2026-04-10T12:00:00Z',
          'sig_verified': true,
          'annex_iii_basis': 'safety_component',
          'overall_pass': true,
          'prerequisite_waived': false,
        },
      };
      final s = ComplianceStatus.fromJson(json);
      expect(s.rrn, 'RRN-000000000001');
      expect(s.complianceStatus, 'compliant');
      expect(s.friaSubmittedAt, '2026-04-10T12:00:00Z');
      expect(s.sigVerified, isTrue);
      expect(s.overallPass, isTrue);
      expect(s.prerequisiteWaived, isFalse);
    });

    test('parses no_fria response (fria: null)', () {
      final json = {
        'rrn': 'RRN-000000000001',
        'verification_tier': 'community',
        'compliance_status': 'no_fria',
        'checked_at': '2026-04-12T00:00:00Z',
        'fria': null,
      };
      final s = ComplianceStatus.fromJson(json);
      expect(s.friaSubmittedAt, isNull);
      expect(s.complianceStatus, 'no_fria');
      expect(s.sigVerified, isFalse);
      expect(s.overallPass, isFalse);
    });

    test('falls back to flat keys when fria object absent', () {
      // Forward-compat: flat format in case API shape changes
      final json = {
        'rrn': 'RRN-000000000001',
        'compliance_status': 'provisional',
        'fria_submitted_at': '2026-04-10T12:00:00Z',
        'sig_verified': true,
        'overall_pass': true,
        'prerequisite_waived': true,
      };
      final s = ComplianceStatus.fromJson(json);
      expect(s.friaSubmittedAt, '2026-04-10T12:00:00Z');
      expect(s.complianceStatus, 'provisional');
      expect(s.prerequisiteWaived, isTrue);
    });
  });

  group('FriaDocument.fromJson', () {
    test('parses rcan.dev API response (document wrapper)', () {
      // Actual shape returned by GET /api/v1/robots/:rrn/fria
      final json = {
        'id': 1,
        'rrn': 'RRN-000000000001',
        'submitted_at': '2026-04-12T00:00:00Z',
        'sig_verified': true,
        'annex_iii_basis': 'safety_component',
        'overall_pass': true,
        'document': {
          'schema': 'rcan-fria-v1',
          'generated_at': '2026-04-12T00:00:00Z',
          'system': {'rrn': 'RRN-000000000001', 'rcan_version': '3.0'},
          'deployment': {'annex_iii_basis': 'safety_component', 'prerequisite_waived': false},
          'signing_key': {'alg': 'ml-dsa-65', 'kid': 'k1', 'public_key': 'AAAA'},
          'sig': {'alg': 'ml-dsa-65', 'kid': 'k1', 'value': 'BBBB'},
          'conformance': {
            'score': 0.95,
            'pass_count': 19,
            'warn_count': 1,
            'fail_count': 0,
          },
        },
      };
      final doc = FriaDocument.fromJson(json);
      expect(doc.schema, 'rcan-fria-v1');
      expect(doc.conformance, isNotNull);
      expect(doc.conformance!.passCount, 19);
      expect(doc.conformance!.failCount, 0);
      expect(doc.conformance!.score, closeTo(0.95, 0.001));
      expect(doc.system['rcan_version'], '3.0');
    });

    test('parses document without conformance', () {
      final json = {
        'id': 2,
        'rrn': 'RRN-000000000001',
        'submitted_at': '2026-04-12T00:00:00Z',
        'document': {
          'schema': 'rcan-fria-v1',
          'generated_at': '2026-04-12T00:00:00Z',
          'system': <String, dynamic>{},
          'deployment': <String, dynamic>{},
          'signing_key': {'alg': 'ml-dsa-65', 'kid': 'k1', 'public_key': 'AAAA'},
          'sig': <String, dynamic>{},
          'conformance': null,
        },
      };
      final doc = FriaDocument.fromJson(json);
      expect(doc.conformance, isNull);
    });

    test('falls back to root fields when document wrapper absent', () {
      // Forward-compat: direct inner document format
      final json = {
        'schema': 'rcan-fria-v1',
        'generated_at': '2026-04-12T00:00:00Z',
        'system': {'rrn': 'RRN-000000000001', 'rcan_version': '3.0'},
        'deployment': <String, dynamic>{},
        'signing_key': <String, dynamic>{},
        'sig': <String, dynamic>{},
        'conformance': null,
      };
      final doc = FriaDocument.fromJson(json);
      expect(doc.schema, 'rcan-fria-v1');
      expect(doc.conformance, isNull);
    });
  });
}
