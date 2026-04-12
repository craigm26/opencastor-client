# Compliance UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add RCAN v3.0 compliance UI — new `ui/compliance/` feature with 6 screens, a `ComplianceRepository` backed by the rcan.dev API, and targeted updates to existing screens and version strings.

**Architecture:** MVVM pattern (Views → ViewModels → Repositories → Services). New `RcanComplianceService` calls `https://rcan.dev/api/v1` for compliance status and FRIA documents; existing Firestore data is untouched. New Riverpod `FutureProvider.family` providers are defined in `ui/compliance/compliance_view_model.dart`. Six flat `GoRoute` entries added to `lib/app.dart` alongside existing robot routes.

**Tech Stack:** Flutter 3.x, Dart 3.3+, Riverpod 2.5, go_router 17, http 1.2, Firebase Auth (existing)

---

## File Map

| Status | File | Purpose |
|--------|------|---------|
| Create | `lib/data/models/compliance.dart` | Dart models: ComplianceStatus, FriaDocument, FriaConformance, SafetyBenchmark, InstructionsForUse, PostMarketIncident, EuRegisterEntry |
| Create | `lib/data/repositories/compliance_repository.dart` | Abstract ComplianceRepository interface |
| Create | `lib/data/services/rcan_compliance_service.dart` | Implements ComplianceRepository via rcan.dev HTTP API |
| Create | `lib/data/repositories/compliance_repository_provider.dart` | Riverpod DI binding for ComplianceRepository |
| Create | `lib/ui/compliance/compliance_view_model.dart` | complianceStatusProvider + friaProvider |
| Create | `lib/ui/compliance/compliance_hub_screen.dart` | Hub: compliance status + nav to sub-screens |
| Create | `lib/ui/compliance/fria_screen.dart` | FRIA document viewer |
| Create | `lib/ui/compliance/safety_benchmark_screen.dart` | Safety benchmark / conformance viewer |
| Create | `lib/ui/compliance/ifu_screen.dart` | IFU placeholder screen |
| Create | `lib/ui/compliance/incidents_screen.dart` | Incidents placeholder screen |
| Create | `lib/ui/compliance/eu_register_screen.dart` | EU Register placeholder screen |
| Create | `test/compliance_models_test.dart` | Unit tests for fromJson parsing |
| Modify | `lib/core/constants.dart` | rcanVersion → "3.0", versionLabel update |
| Modify | `lib/data/models/robot.dart` | Add isRcanV30 getter |
| Modify | `lib/routes.dart` | Add 6 route constants + 6 helper functions |
| Modify | `lib/app.dart` | Add 6 GoRoute entries + imports |
| Modify | `lib/ui/robot_detail/compliance_report_screen.dart` | Wire complianceStatusProvider, add nav card |
| Modify | `lib/ui/robot_capabilities/conformance_screen.dart` | Add FRIA conformance card from friaProvider |

---

## Task 1: Data models

**Files:**
- Create: `lib/data/models/compliance.dart`
- Create: `test/compliance_models_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/compliance_models_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/craigm26/opencastor-client && flutter test test/compliance_models_test.dart 2>&1 | tail -10
```

Expected: FAIL — `compliance.dart` does not exist

- [ ] **Step 3: Create `lib/data/models/compliance.dart`**

```dart
/// RCAN v3.0 compliance data models (§22–§26).
///
/// All classes are immutable. JSON field names match the rcan.dev wire format
/// (snake_case). Dart fields use camelCase per Dart conventions.
library;

// ── Compliance Status ─────────────────────────────────────────────────────────

/// Summary compliance status for a robot from the rcan.dev /compliance endpoint.
class ComplianceStatus {
  final String rrn;
  /// One of: "compliant" | "provisional" | "non_compliant" | "no_fria"
  final String complianceStatus;
  /// ISO-8601 timestamp, or null if no FRIA submitted.
  final String? friaSubmittedAt;
  final bool sigVerified;
  final bool overallPass;
  final bool prerequisiteWaived;

  const ComplianceStatus({
    required this.rrn,
    required this.complianceStatus,
    required this.friaSubmittedAt,
    required this.sigVerified,
    required this.overallPass,
    required this.prerequisiteWaived,
  });

  factory ComplianceStatus.fromJson(Map<String, dynamic> json) {
    return ComplianceStatus(
      rrn: json['rrn'] as String,
      complianceStatus: json['compliance_status'] as String,
      friaSubmittedAt: json['fria_submitted_at'] as String?,
      sigVerified: (json['sig_verified'] as bool?) ?? false,
      overallPass: (json['overall_pass'] as bool?) ?? false,
      prerequisiteWaived: (json['prerequisite_waived'] as bool?) ?? false,
    );
  }
}

// ── FRIA Document (§22) ───────────────────────────────────────────────────────

/// Conformance scores embedded in a FRIA document.
class FriaConformance {
  /// Overall score, 0.0–1.0.
  final double score;
  final int passCount;
  final int warnCount;
  final int failCount;

  const FriaConformance({
    required this.score,
    required this.passCount,
    required this.warnCount,
    required this.failCount,
  });

  factory FriaConformance.fromJson(Map<String, dynamic> json) {
    return FriaConformance(
      score: (json['score'] as num).toDouble(),
      // Support both "pass_count" (rcan-py style) and "pass" (legacy)
      passCount: (json['pass_count'] ?? json['pass'] ?? 0) as int,
      warnCount: (json['warn_count'] ?? json['warn'] ?? 0) as int,
      failCount: (json['fail_count'] ?? json['fail'] ?? 0) as int,
    );
  }
}

/// A FRIA document as returned by GET /robots/:rrn/fria.
class FriaDocument {
  final String schema;
  final String generatedAt;
  final Map<String, dynamic> system;
  final Map<String, dynamic> deployment;
  final Map<String, dynamic> signingKey;
  final Map<String, dynamic> sig;
  /// null if conformance scores have not yet been computed.
  final FriaConformance? conformance;

  const FriaDocument({
    required this.schema,
    required this.generatedAt,
    required this.system,
    required this.deployment,
    required this.signingKey,
    required this.sig,
    required this.conformance,
  });

  factory FriaDocument.fromJson(Map<String, dynamic> json) {
    final conformanceJson = json['conformance'] as Map<String, dynamic>?;
    return FriaDocument(
      schema: (json['schema'] as String?) ?? '',
      generatedAt: (json['generated_at'] as String?) ?? '',
      system: (json['system'] as Map<String, dynamic>?) ?? {},
      deployment: (json['deployment'] as Map<String, dynamic>?) ?? {},
      signingKey: (json['signing_key'] as Map<String, dynamic>?) ?? {},
      sig: (json['sig'] as Map<String, dynamic>?) ?? {},
      conformance: conformanceJson != null
          ? FriaConformance.fromJson(conformanceJson)
          : null,
    );
  }
}

// ── Safety Benchmark (§23) ────────────────────────────────────────────────────

class SafetyBenchmark {
  final String protocol;
  final double score;
  final int passCount;
  final int failCount;
  final String runAt;
  final String rrn;

  const SafetyBenchmark({
    required this.protocol,
    required this.score,
    required this.passCount,
    required this.failCount,
    required this.runAt,
    required this.rrn,
  });

  factory SafetyBenchmark.fromJson(Map<String, dynamic> json) {
    return SafetyBenchmark(
      protocol: json['protocol'] as String,
      score: (json['score'] as num).toDouble(),
      passCount: (json['pass_count'] ?? json['pass'] ?? 0) as int,
      failCount: (json['fail_count'] ?? json['fail'] ?? 0) as int,
      runAt: json['run_at'] as String,
      rrn: json['rrn'] as String,
    );
  }
}

// ── Instructions for Use (§24) ────────────────────────────────────────────────

class InstructionsForUse {
  final String rrn;
  final String robotName;
  final String intendedUse;
  final String operatingEnvironment;
  final List<String> contraindications;
  final String version;
  final String issuedAt;

  const InstructionsForUse({
    required this.rrn,
    required this.robotName,
    required this.intendedUse,
    required this.operatingEnvironment,
    required this.contraindications,
    required this.version,
    required this.issuedAt,
  });

  factory InstructionsForUse.fromJson(Map<String, dynamic> json) {
    return InstructionsForUse(
      rrn: json['rrn'] as String,
      robotName: json['robot_name'] as String,
      intendedUse: json['intended_use'] as String,
      operatingEnvironment: json['operating_environment'] as String,
      contraindications: (json['contraindications'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      version: json['version'] as String,
      issuedAt: json['issued_at'] as String,
    );
  }
}

// ── Post-Market Incident (§25) ────────────────────────────────────────────────

class PostMarketIncident {
  final String rrn;
  final String incidentId;
  /// "low" | "medium" | "high" | "critical"
  final String severity;
  final String description;
  final String occurredAt;
  final String reportedAt;
  /// "open" | "under_review" | "resolved"
  final String status;

  const PostMarketIncident({
    required this.rrn,
    required this.incidentId,
    required this.severity,
    required this.description,
    required this.occurredAt,
    required this.reportedAt,
    required this.status,
  });

  factory PostMarketIncident.fromJson(Map<String, dynamic> json) {
    return PostMarketIncident(
      rrn: json['rrn'] as String,
      incidentId: json['incident_id'] as String,
      severity: json['severity'] as String,
      description: json['description'] as String,
      occurredAt: json['occurred_at'] as String,
      reportedAt: json['reported_at'] as String,
      status: json['status'] as String,
    );
  }
}

// ── EU Register Entry (§26) ───────────────────────────────────────────────────

class EuRegisterEntry {
  final String rrn;
  final String robotName;
  final String manufacturer;
  final String annexIiiBasis;
  final String? friaSubmittedAt;
  /// "compliant" | "provisional" | "non_compliant" | "no_fria"
  final String complianceStatus;
  final String registeredAt;

  const EuRegisterEntry({
    required this.rrn,
    required this.robotName,
    required this.manufacturer,
    required this.annexIiiBasis,
    required this.friaSubmittedAt,
    required this.complianceStatus,
    required this.registeredAt,
  });

  factory EuRegisterEntry.fromJson(Map<String, dynamic> json) {
    return EuRegisterEntry(
      rrn: json['rrn'] as String,
      robotName: json['robot_name'] as String,
      manufacturer: json['manufacturer'] as String,
      annexIiiBasis: json['annex_iii_basis'] as String,
      friaSubmittedAt: json['fria_submitted_at'] as String?,
      complianceStatus: json['compliance_status'] as String,
      registeredAt: json['registered_at'] as String,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /home/craigm26/opencastor-client && flutter test test/compliance_models_test.dart 2>&1 | tail -10
```

Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
cd /home/craigm26/opencastor-client && git add lib/data/models/compliance.dart test/compliance_models_test.dart && git commit -m "feat: add RCAN v3.0 compliance data models (§22–§26)"
```

---

## Task 2: Repository + service + DI provider

**Files:**
- Create: `lib/data/repositories/compliance_repository.dart`
- Create: `lib/data/services/rcan_compliance_service.dart`
- Create: `lib/data/repositories/compliance_repository_provider.dart`

No additional tests beyond analyze — HTTP calls cannot be tested without device/mocks not in this project's test setup.

- [ ] **Step 1: Create `lib/data/repositories/compliance_repository.dart`**

```dart
/// Abstract contract for RCAN v3.0 compliance data.
///
/// Concrete implementation: [RcanComplianceService].
/// DI binding: [complianceRepositoryProvider].
///
/// Depend on [ComplianceRepository], never on [RcanComplianceService] directly.
library;

import '../models/compliance.dart';

export '../models/compliance.dart';

abstract class ComplianceRepository {
  /// Fetch live compliance status for [rrn] from rcan.dev.
  Future<ComplianceStatus> getComplianceStatus(String rrn);

  /// Fetch the submitted FRIA document for [rrn].
  /// Returns null if no FRIA has been submitted (404 response).
  Future<FriaDocument?> getFriaDocument(String rrn);
}
```

- [ ] **Step 2: Create `lib/data/services/rcan_compliance_service.dart`**

```dart
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
```

- [ ] **Step 3: Create `lib/data/repositories/compliance_repository_provider.dart`**

```dart
/// Riverpod DI binding for [ComplianceRepository].
///
/// Swap the implementation here to use a mock in tests.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'compliance_repository.dart';
import '../services/rcan_compliance_service.dart';

export 'compliance_repository.dart';

final complianceRepositoryProvider = Provider<ComplianceRepository>(
  (_) => const RcanComplianceService(),
);
```

- [ ] **Step 4: Run analyze to verify no errors**

```bash
cd /home/craigm26/opencastor-client && flutter analyze lib/data/repositories/compliance_repository.dart lib/data/services/rcan_compliance_service.dart lib/data/repositories/compliance_repository_provider.dart 2>&1 | tail -10
```

Expected: No issues found

- [ ] **Step 5: Commit**

```bash
cd /home/craigm26/opencastor-client && git add lib/data/repositories/compliance_repository.dart lib/data/services/rcan_compliance_service.dart lib/data/repositories/compliance_repository_provider.dart && git commit -m "feat: add ComplianceRepository + RcanComplianceService (rcan.dev API)"
```

---

## Task 3: ViewModel

**Files:**
- Create: `lib/ui/compliance/compliance_view_model.dart`

- [ ] **Step 1: Create `lib/ui/compliance/compliance_view_model.dart`**

```dart
/// ViewModel for all compliance screens.
///
/// Providers defined here:
///   - [complianceStatusProvider] — live compliance status from rcan.dev
///   - [friaProvider]            — FRIA document from rcan.dev (null = not submitted)
///
/// All compliance screens import providers from this file.
/// Views never call [complianceRepositoryProvider] directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/compliance_repository_provider.dart';

export '../../data/repositories/compliance_repository_provider.dart';

/// Fetches compliance status for [rrn] from rcan.dev.
final complianceStatusProvider =
    FutureProvider.family<ComplianceStatus, String>((ref, rrn) {
  return ref.read(complianceRepositoryProvider).getComplianceStatus(rrn);
});

/// Fetches the FRIA document for [rrn] from rcan.dev.
/// Returns null if no FRIA has been submitted.
final friaProvider =
    FutureProvider.family<FriaDocument?, String>((ref, rrn) {
  return ref.read(complianceRepositoryProvider).getFriaDocument(rrn);
});
```

- [ ] **Step 2: Run analyze**

```bash
cd /home/craigm26/opencastor-client && flutter analyze lib/ui/compliance/compliance_view_model.dart 2>&1 | tail -5
```

Expected: No issues found

- [ ] **Step 3: Commit**

```bash
cd /home/craigm26/opencastor-client && git add lib/ui/compliance/compliance_view_model.dart && git commit -m "feat: add compliance Riverpod providers (complianceStatusProvider, friaProvider)"
```

---

## Task 4: Hub screen + routes

**Files:**
- Create: `lib/ui/compliance/compliance_hub_screen.dart`
- Modify: `lib/routes.dart`
- Modify: `lib/app.dart`

- [ ] **Step 1: Create `lib/ui/compliance/compliance_hub_screen.dart`**

```dart
/// Compliance hub screen — status overview + navigation to sub-screens.
/// Route: /robot/:rrn/compliance
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/error_view.dart';
import '../shared/loading_view.dart';
import '../../routes.dart';
import 'compliance_view_model.dart';

class ComplianceHubScreen extends ConsumerWidget {
  final String rrn;
  const ComplianceHubScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(complianceStatusProvider(rrn));
    return Scaffold(
      appBar: AppBar(title: const Text('Compliance')),
      body: statusAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e.toString()),
        data: (status) => _HubBody(rrn: rrn, status: status),
      ),
    );
  }
}

class _HubBody extends StatelessWidget {
  final String rrn;
  final ComplianceStatus status;
  const _HubBody({required this.rrn, required this.status});

  Color _statusColor(BuildContext context, String s) => switch (s) {
        'compliant'     => Colors.green,
        'provisional'   => Colors.amber.shade700,
        'non_compliant' => Colors.red,
        _               => Colors.grey,
      };

  String _statusLabel(String s) => switch (s) {
        'compliant'     => 'Compliant',
        'provisional'   => 'Provisional',
        'non_compliant' => 'Non-compliant',
        'no_fria'       => 'No FRIA',
        _               => s,
      };

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status.complianceStatus);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status chip
        Center(
          child: Chip(
            label: Text(
              _statusLabel(status.complianceStatus),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
        const SizedBox(height: 8),
        if (status.friaSubmittedAt != null)
          Center(
            child: Text(
              'FRIA submitted: ${status.friaSubmittedAt}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          Center(
            child: Text(
              'No FRIA submitted',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
        const SizedBox(height: 24),
        // Navigation tiles
        _NavTile(
          icon: Icons.verified_user_outlined,
          title: 'FRIA Document',
          subtitle: 'Fundamental Rights Impact Assessment',
          onTap: () => context.push(AppRoutes.robotComplianceFriaFor(rrn)),
        ),
        _NavTile(
          icon: Icons.speed_outlined,
          title: 'Safety Benchmark',
          subtitle: 'Protocol conformance scores',
          onTap: () => context.push(AppRoutes.robotComplianceBenchmarkFor(rrn)),
        ),
        _NavTile(
          icon: Icons.menu_book_outlined,
          title: 'Instructions for Use',
          subtitle: 'Operator deployment guidelines',
          onTap: () => context.push(AppRoutes.robotComplianceIfuFor(rrn)),
        ),
        _NavTile(
          icon: Icons.report_problem_outlined,
          title: 'Post-Market Incidents',
          subtitle: 'Safety and performance incidents',
          onTap: () => context.push(AppRoutes.robotComplianceIncidentsFor(rrn)),
        ),
        _NavTile(
          icon: Icons.account_balance_outlined,
          title: 'EU Register Entry',
          subtitle: 'High-risk AI systems register',
          onTap: () => context.push(AppRoutes.robotComplianceEuRegisterFor(rrn)),
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
```

- [ ] **Step 2: Add route constants to `lib/routes.dart`**

In `lib/routes.dart`, inside the `abstract final class AppRoutes` block, add after the `robotComplianceReport` line:

```dart
  // ── Compliance hub + sub-screens (RCAN v3.0) ─────────────────────────────
  static const robotCompliance = '/robot/:rrn/compliance';
  static const robotComplianceFria = '/robot/:rrn/compliance/fria';
  static const robotComplianceBenchmark = '/robot/:rrn/compliance/benchmark';
  static const robotComplianceIfu = '/robot/:rrn/compliance/ifu';
  static const robotComplianceIncidents = '/robot/:rrn/compliance/incidents';
  static const robotComplianceEuRegister = '/robot/:rrn/compliance/eu-register';

  static String robotComplianceFor(String rrn) => '/robot/$rrn/compliance';
  static String robotComplianceFriaFor(String rrn) => '/robot/$rrn/compliance/fria';
  static String robotComplianceBenchmarkFor(String rrn) => '/robot/$rrn/compliance/benchmark';
  static String robotComplianceIfuFor(String rrn) => '/robot/$rrn/compliance/ifu';
  static String robotComplianceIncidentsFor(String rrn) => '/robot/$rrn/compliance/incidents';
  static String robotComplianceEuRegisterFor(String rrn) => '/robot/$rrn/compliance/eu-register';
```

- [ ] **Step 3: Add imports to `lib/app.dart`**

In `lib/app.dart`, after the existing compliance import:
```dart
import 'ui/robot_detail/compliance_report_screen.dart';
```
Add:
```dart
import 'ui/compliance/compliance_hub_screen.dart';
import 'ui/compliance/fria_screen.dart';
import 'ui/compliance/safety_benchmark_screen.dart';
import 'ui/compliance/ifu_screen.dart';
import 'ui/compliance/incidents_screen.dart';
import 'ui/compliance/eu_register_screen.dart';
```

- [ ] **Step 4: Add GoRoutes to `lib/app.dart`**

In `lib/app.dart`, after the existing `GoRoute` for `/robot/:rrn/compliance-report`:

```dart
          GoRoute(
            path: '/robot/:rrn/compliance',
            builder: (_, state) =>
                ComplianceHubScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance/fria',
            builder: (_, state) =>
                FriaScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance/benchmark',
            builder: (_, state) =>
                SafetyBenchmarkScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance/ifu',
            builder: (_, state) =>
                IfuScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance/incidents',
            builder: (_, state) =>
                IncidentsScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance/eu-register',
            builder: (_, state) =>
                EuRegisterScreen(rrn: state.pathParameters['rrn']!),
          ),
```

- [ ] **Step 5: Run analyze**

```bash
cd /home/craigm26/opencastor-client && flutter analyze lib/ui/compliance/compliance_hub_screen.dart lib/routes.dart lib/app.dart 2>&1 | tail -10
```

Expected: No issues (some screens don't exist yet — that's OK, they'll be created in Tasks 5 and 6)

Note: analyze will fail until all imported screen files exist. Proceed to Tasks 5 and 6 before running analyze on `app.dart`.

- [ ] **Step 6: Commit (after Tasks 5 and 6 complete)**

Defer this commit to after Task 6 so analyze passes cleanly.

---

## Task 5: FRIA screen + Safety Benchmark screen

**Files:**
- Create: `lib/ui/compliance/fria_screen.dart`
- Create: `lib/ui/compliance/safety_benchmark_screen.dart`

- [ ] **Step 1: Create `lib/ui/compliance/fria_screen.dart`**

```dart
/// FRIA document viewer screen.
/// Route: /robot/:rrn/compliance/fria
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/error_view.dart';
import '../shared/loading_view.dart';
import 'compliance_view_model.dart';

class FriaScreen extends ConsumerWidget {
  final String rrn;
  const FriaScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friaAsync = ref.watch(friaProvider(rrn));
    return Scaffold(
      appBar: AppBar(title: const Text('FRIA Document')),
      body: friaAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e.toString()),
        data: (doc) => doc == null
            ? const _NoFriaView()
            : _FriaBody(doc: doc),
      ),
    );
  }
}

class _NoFriaView extends StatelessWidget {
  const _NoFriaView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No FRIA submitted',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Submit a FRIA document via the rcan.dev API to enable compliance tracking.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _FriaBody extends StatelessWidget {
  final FriaDocument doc;
  const _FriaBody({required this.doc});

  @override
  Widget build(BuildContext context) {
    final system = doc.system;
    final deployment = doc.deployment;
    final conformance = doc.conformance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'Document',
          children: [
            _Row('Schema', doc.schema),
            _Row('Generated', doc.generatedAt),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Robot System',
          children: [
            if (system['rrn'] != null) _Row('RRN', system['rrn'].toString()),
            if (system['robot_name'] != null) _Row('Name', system['robot_name'].toString()),
            if (system['rcan_version'] != null) _Row('RCAN', system['rcan_version'].toString()),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Deployment',
          children: [
            if (deployment['annex_iii_basis'] != null)
              _Row('Annex III basis', deployment['annex_iii_basis'].toString()),
            _Row(
              'Prerequisite waived',
              (deployment['prerequisite_waived'] == true) ? 'Yes' : 'No',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Signing Key',
          children: [
            _Row('Algorithm', (doc.signingKey['alg'] ?? '—').toString()),
            _Row('Key ID', (doc.signingKey['kid'] ?? '—').toString()),
          ],
        ),
        if (conformance != null) ...[
          const SizedBox(height: 12),
          _ConformanceCard(conformance: conformance),
        ] else ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Conformance scores not yet computed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

class _ConformanceCard extends StatelessWidget {
  final FriaConformance conformance;
  const _ConformanceCard({required this.conformance});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Conformance', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: conformance.score.clamp(0.0, 1.0),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text(
            '${(conformance.score * 100).toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CountChip(label: 'Pass', count: conformance.passCount, color: Colors.green),
              _CountChip(label: 'Warn', count: conformance.warnCount, color: Colors.amber.shade700),
              _CountChip(label: 'Fail', count: conformance.failCount, color: Colors.red),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 18)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const Divider(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create `lib/ui/compliance/safety_benchmark_screen.dart`**

```dart
/// Safety Benchmark screen — shows conformance scores from the FRIA document.
/// Route: /robot/:rrn/compliance/benchmark
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/error_view.dart';
import '../shared/loading_view.dart';
import 'compliance_view_model.dart';

class SafetyBenchmarkScreen extends ConsumerWidget {
  final String rrn;
  const SafetyBenchmarkScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friaAsync = ref.watch(friaProvider(rrn));
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Benchmark')),
      body: friaAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e.toString()),
        data: (doc) {
          if (doc == null) {
            return const _NoDataView(message: 'No FRIA document submitted — submit a FRIA to see safety benchmark results.');
          }
          final conformance = doc.conformance;
          if (conformance == null) {
            return const _NoDataView(message: 'FRIA submitted but conformance scores have not yet been computed.');
          }
          return _BenchmarkBody(conformance: conformance);
        },
      ),
    );
  }
}

class _NoDataView extends StatelessWidget {
  final String message;
  const _NoDataView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.speed_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _BenchmarkBody extends StatelessWidget {
  final FriaConformance conformance;
  const _BenchmarkBody({required this.conformance});

  @override
  Widget build(BuildContext context) {
    final total = conformance.passCount + conformance.warnCount + conformance.failCount;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Overall Score', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: conformance.score.clamp(0.0, 1.0),
                minHeight: 12,
                borderRadius: BorderRadius.circular(6),
                color: conformance.failCount == 0 ? Colors.green : Colors.orange,
              ),
              const SizedBox(height: 8),
              Text(
                '${(conformance.score * 100).toStringAsFixed(1)}% (${conformance.passCount}/$total checks passed)',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Results', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ResultColumn(
                    label: 'Pass',
                    count: conformance.passCount,
                    icon: Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  _ResultColumn(
                    label: 'Warn',
                    count: conformance.warnCount,
                    icon: Icons.warning_amber_outlined,
                    color: Colors.amber.shade700,
                  ),
                  _ResultColumn(
                    label: 'Fail',
                    count: conformance.failCount,
                    icon: Icons.cancel_outlined,
                    color: Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _ResultColumn extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  const _ResultColumn({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 4),
        Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
```

- [ ] **Step 3: Run analyze**

```bash
cd /home/craigm26/opencastor-client && flutter analyze lib/ui/compliance/fria_screen.dart lib/ui/compliance/safety_benchmark_screen.dart 2>&1 | tail -10
```

Expected: No issues found

- [ ] **Step 4: Commit (screens only — app.dart routes deferred to Task 6)**

```bash
cd /home/craigm26/opencastor-client && git add lib/ui/compliance/fria_screen.dart lib/ui/compliance/safety_benchmark_screen.dart && git commit -m "feat: add FriaScreen and SafetyBenchmarkScreen"
```

---

## Task 6: Placeholder screens + wire all routes

**Files:**
- Create: `lib/ui/compliance/ifu_screen.dart`
- Create: `lib/ui/compliance/incidents_screen.dart`
- Create: `lib/ui/compliance/eu_register_screen.dart`
- Wire routes: commit `lib/routes.dart` + `lib/app.dart` + `lib/ui/compliance/compliance_hub_screen.dart`

- [ ] **Step 1: Create `lib/ui/compliance/ifu_screen.dart`**

```dart
/// Instructions for Use placeholder screen.
/// Route: /robot/:rrn/compliance/ifu
///
/// IFU data will be populated when the rcan.dev IFU endpoint is available.
library;

import 'package:flutter/material.dart';
import '_placeholder_screen.dart';

class IfuScreen extends StatelessWidget {
  final String rrn;
  const IfuScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context) {
    return const CompliancePlaceholderScreen(
      title: 'Instructions for Use',
      icon: Icons.menu_book_outlined,
      message: 'Instructions for Use data will appear here once the IFU API endpoint is available on rcan.dev.',
    );
  }
}
```

- [ ] **Step 2: Create `lib/ui/compliance/incidents_screen.dart`**

```dart
/// Post-Market Incidents placeholder screen.
/// Route: /robot/:rrn/compliance/incidents
library;

import 'package:flutter/material.dart';
import '_placeholder_screen.dart';

class IncidentsScreen extends StatelessWidget {
  final String rrn;
  const IncidentsScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context) {
    return const CompliancePlaceholderScreen(
      title: 'Post-Market Incidents',
      icon: Icons.report_problem_outlined,
      message: 'Post-market incident reports will appear here once the incidents API endpoint is available on rcan.dev.',
    );
  }
}
```

- [ ] **Step 3: Create `lib/ui/compliance/eu_register_screen.dart`**

```dart
/// EU Register Entry placeholder screen.
/// Route: /robot/:rrn/compliance/eu-register
library;

import 'package:flutter/material.dart';
import '_placeholder_screen.dart';

class EuRegisterScreen extends StatelessWidget {
  final String rrn;
  const EuRegisterScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context) {
    return const CompliancePlaceholderScreen(
      title: 'EU Register Entry',
      icon: Icons.account_balance_outlined,
      message: 'EU high-risk AI systems register data will appear here once the EU register API endpoint is available on rcan.dev.',
    );
  }
}
```

- [ ] **Step 4: Create shared `lib/ui/compliance/_placeholder_screen.dart`**

```dart
/// Shared placeholder widget used by IFU, Incidents, and EU Register screens.
library;

import 'package:flutter/material.dart';

class CompliancePlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String message;
  const CompliancePlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Not yet available',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run full analyze**

```bash
cd /home/craigm26/opencastor-client && flutter analyze 2>&1 | tail -10
```

Expected: No issues found

- [ ] **Step 6: Run tests**

```bash
cd /home/craigm26/opencastor-client && flutter test 2>&1 | tail -10
```

Expected: All tests pass

- [ ] **Step 7: Commit all new compliance UI files + routes**

```bash
cd /home/craigm26/opencastor-client && git add \
  lib/ui/compliance/ifu_screen.dart \
  lib/ui/compliance/incidents_screen.dart \
  lib/ui/compliance/eu_register_screen.dart \
  lib/ui/compliance/_placeholder_screen.dart \
  lib/ui/compliance/compliance_hub_screen.dart \
  lib/routes.dart \
  lib/app.dart \
  && git commit -m "feat: add compliance hub + 5 sub-screens with routing (/robot/:rrn/compliance/*)"
```

---

## Task 7: Update existing screens + version strings

**Files:**
- Modify: `lib/core/constants.dart`
- Modify: `lib/data/models/robot.dart`
- Modify: `lib/ui/robot_detail/compliance_report_screen.dart`
- Modify: `lib/ui/robot_capabilities/conformance_screen.dart`

- [ ] **Step 1: Update `lib/core/constants.dart`**

Change the three version constants:

```dart
  static const String appVersion = '1.5.0';
  static const String rcanVersion = '3.0';
  static const String versionLabel = 'v1.5.0 · RCAN v3.0';
```

Leave `opencastorReleaseVersion` and all URLs unchanged.

- [ ] **Step 2: Add `isRcanV30` to `lib/data/models/robot.dart`**

After the existing `isRcanV21` getter (around line 320), add:

```dart
  /// True if the robot supports RCAN v3.0 or later.
  bool get isRcanV30 {
    if (rcanVersion == null) return false;
    final parts = rcanVersion!.split('.');
    if (parts.isEmpty) return false;
    final major = int.tryParse(parts[0]) ?? 0;
    return major >= 3;
  }
```

- [ ] **Step 3: Update `lib/ui/robot_detail/compliance_report_screen.dart`**

Add two imports after the existing imports:

```dart
import '../../ui/compliance/compliance_view_model.dart';
import '../../routes.dart';
```

Change `ComplianceReportScreen` from `ConsumerWidget` — it already is one. In the `build` method, add watching the new provider alongside the existing robot watch. Find the `data: (robot)` branch and change it to also read compliance status:

The screen's build method currently just calls `ref.watch(robotDetailProvider(rrn))`. Change the `data:` callback inside `_ComplianceReportView` to also show the live compliance status. The simplest change is in `_ComplianceReportView` — make it a `ConsumerWidget` and watch `complianceStatusProvider`:

Replace the existing `_ComplianceReportView` class definition:

```dart
class _ComplianceReportView extends ConsumerWidget {
  final Robot robot;
  const _ComplianceReportView({required this.robot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(complianceStatusProvider(robot.rrn));
    final liveStatus = statusAsync.asData?.value;
```

Then inside the existing `_buildReport()` method, find the RCAN version check entry (the one with `isRcanV21`) and update it:

Old:
```dart
      {
        'id':     'rcan_version',
        'status': robot.isRcanV21 ? 'pass' : 'warn',
        'detail': 'RCAN version: ${robot.rcanVersion ?? "unknown"}',
      },
```

New:
```dart
      {
        'id':     'rcan_version',
        'status': (liveStatus?.complianceStatus == 'compliant') ? 'pass'
            : (liveStatus?.complianceStatus == 'provisional') ? 'warn'
            : robot.isRcanV30 ? 'pass'
            : robot.isRcanV21 ? 'warn'
            : 'fail',
        'detail': liveStatus != null
            ? 'RCAN compliance: ${liveStatus.complianceStatus} (RCAN v${robot.rcanVersion ?? "unknown"})'
            : 'RCAN version: ${robot.rcanVersion ?? "unknown"}',
      },
```

At the very bottom of the `_ComplianceReportView` build method, before the final `],` of the ListView children, add a navigation card:

```dart
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('View Full Compliance'),
            subtitle: const Text('FRIA, Safety Benchmark, EU Register'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.robotComplianceFor(robot.rrn)),
          ),
```

- [ ] **Step 4: Update `lib/ui/robot_capabilities/conformance_screen.dart`**

Add import after existing imports:
```dart
import '../compliance/compliance_view_model.dart';
```

Change `ConformanceScreen` to watch `friaProvider`. In the `_ConformanceView` class, make it a `ConsumerWidget`:

Replace:
```dart
class _ConformanceView extends StatelessWidget {
  final Robot robot;
  const _ConformanceView({required this.robot});

  @override
  Widget build(BuildContext context) {
```

With:
```dart
class _ConformanceView extends ConsumerWidget {
  final Robot robot;
  const _ConformanceView({required this.robot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friaAsync = ref.watch(friaProvider(robot.rrn));
    final friaConformance = friaAsync.asData?.value?.conformance;
```

In the `ListView` children list, insert a FRIA conformance card BEFORE the existing `ConformanceCard`:

```dart
          if (friaConformance != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('FRIA Conformance (rcan.dev)', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: friaConformance.score.clamp(0.0, 1.0),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [
                        Text('${friaConformance.passCount}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 18)),
                        Text('Pass', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                      Column(children: [
                        Text('${friaConformance.warnCount}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade700, fontSize: 18)),
                        Text('Warn', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                      Column(children: [
                        Text('${friaConformance.failCount}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 18)),
                        Text('Fail', style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else if (friaAsync.isLoading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
          ],
```

- [ ] **Step 5: Run full analyze + tests**

```bash
cd /home/craigm26/opencastor-client && flutter analyze 2>&1 | tail -10 && flutter test 2>&1 | tail -5
```

Expected: No issues, all tests pass

- [ ] **Step 6: Commit**

```bash
cd /home/craigm26/opencastor-client && git add \
  lib/core/constants.dart \
  lib/data/models/robot.dart \
  lib/ui/robot_detail/compliance_report_screen.dart \
  lib/ui/robot_capabilities/conformance_screen.dart \
  && git commit -m "feat: wire compliance UI into existing screens, bump RCAN version to 3.0"
```

---

## Task 8: Final verification

**Files:** Read-only — no changes

- [ ] **Step 1: Run full flutter analyze**

```bash
cd /home/craigm26/opencastor-client && flutter analyze 2>&1 | grep -E "No issues|error|warning" | head -5
```

Expected: `No issues found!`

- [ ] **Step 2: Run all tests**

```bash
cd /home/craigm26/opencastor-client && flutter test 2>&1 | tail -5
```

Expected: All tests pass

- [ ] **Step 3: Verify new routes are registered**

```bash
grep -c "compliance" /home/craigm26/opencastor-client/lib/app.dart
```

Expected: ≥ 7 (6 new routes + 1 existing compliance-report import)

- [ ] **Step 4: Verify version string**

```bash
grep "rcanVersion\|versionLabel" /home/craigm26/opencastor-client/lib/core/constants.dart
```

Expected:
```
static const String rcanVersion = '3.0';
static const String versionLabel = 'v1.5.0 · RCAN v3.0';
```

- [ ] **Step 5: Confirm git log**

```bash
cd /home/craigm26/opencastor-client && git log --oneline -8
```

Expected: 7 new commits on top of the previous head.
