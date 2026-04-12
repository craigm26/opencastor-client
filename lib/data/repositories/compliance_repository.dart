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
