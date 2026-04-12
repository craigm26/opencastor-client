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
