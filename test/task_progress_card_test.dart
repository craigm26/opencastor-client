import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opencastor_client/data/models/task_doc.dart';
import 'package:opencastor_client/ui/widgets/task_progress_card.dart';
import 'package:opencastor_client/ui/robot_detail/robot_detail_view_model.dart'
    show taskDocProvider;

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

  // Widget test helper — wraps widget in MaterialApp + ProviderScope with overrides
  Widget wrap(Widget child, List<Override> overrides) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('TaskProgressCard shows Run button when pending_confirmation',
      (tester) async {
    final task = TaskDoc(
      taskId: 't1',
      type: 'pick_place',
      target: 'red lego brick',
      destination: 'bowl',
      status: 'pending_confirmation',
      phase: 'SCAN',
      detectedObjects: const [],
      confirmed: false,
    );

    await tester.pumpWidget(wrap(
      const TaskProgressCard(rrn: 'RRN-1', taskId: 't1'),
      [
        taskDocProvider((rrn: 'RRN-1', taskId: 't1'))
            .overrideWith((_) => Stream.value(task)),
      ],
    ));
    await tester.pump();

    expect(find.text('Run'), findsOneWidget);
  });

  testWidgets('TaskProgressCard hides Run button when running', (tester) async {
    final task = TaskDoc(
      taskId: 't2',
      type: 'pick_place',
      target: 'cube',
      destination: 'box',
      status: 'running',
      phase: 'APPROACH',
      detectedObjects: const [],
      confirmed: true,
    );

    await tester.pumpWidget(wrap(
      const TaskProgressCard(rrn: 'RRN-1', taskId: 't2'),
      [
        taskDocProvider((rrn: 'RRN-1', taskId: 't2'))
            .overrideWith((_) => Stream.value(task)),
      ],
    ));
    await tester.pump();

    expect(find.text('Run'), findsNothing);
  });
}
