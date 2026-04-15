import 'package:flutter_test/flutter_test.dart';
import 'package:opencastor_client/data/models/task_doc.dart';

void main() {
  group('TaskDoc.fromMap', () {
    test('parses all fields', () {
      final doc = TaskDoc.fromMap('task-abc', {
        'type': 'pick_place',
        'target': 'red lego',
        'destination': 'bowl',
        'status': 'running',
        'phase': 'APPROACH',
        'frame_b64': 'abc123',
        'detected_objects': ['red lego', 'bowl'],
        'error': null,
        'confirmed': false,
        'created_at': '2026-04-14T12:00:00Z',
        'updated_at': '2026-04-14T12:00:01Z',
      });

      expect(doc.taskId, equals('task-abc'));
      expect(doc.target, equals('red lego'));
      expect(doc.destination, equals('bowl'));
      expect(doc.status, equals('running'));
      expect(doc.phase, equals('APPROACH'));
      expect(doc.frameB64, equals('abc123'));
      expect(doc.detectedObjects, equals(['red lego', 'bowl']));
      expect(doc.confirmed, isFalse);
    });

    test('handles missing optional fields', () {
      final doc = TaskDoc.fromMap('task-xyz', {
        'type': 'pick_place',
        'target': 'cube',
        'destination': 'tray',
        'status': 'pending_confirmation',
        'phase': 'SCAN',
      });

      expect(doc.frameB64, isNull);
      expect(doc.detectedObjects, isEmpty);
      expect(doc.confirmed, isFalse);
      expect(doc.error, isNull);
    });
  });
}
