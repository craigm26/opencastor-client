/// ViewModel for the Hardware Components screen.
///
/// Exposes the [componentsProvider] stream that feeds [ComponentsScreen].
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live stream of hardware components for [rrn] from Firestore
/// `robots/{rrn}/components` subcollection.
final componentsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, rrn) {
  return FirebaseFirestore.instance
      .collection('robots')
      .doc(rrn)
      .collection('components')
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()
            ..sort((a, b) =>
                (a['type'] as String? ?? '').compareTo(b['type'] as String? ?? '')));
});
