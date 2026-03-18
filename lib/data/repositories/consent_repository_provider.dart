/// Global Riverpod provider for [ConsentRepository].
///
/// Returns the [FirestoreConsentService] concrete implementation.
/// Import this instead of defining a local throw-stub provider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/consent_repository.dart';
import '../services/firestore_consent_service.dart';

final consentRepositoryProvider = Provider<ConsentRepository>(
  (ref) => FirestoreConsentService(),
);
