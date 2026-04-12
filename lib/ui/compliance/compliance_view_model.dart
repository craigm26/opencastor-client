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
