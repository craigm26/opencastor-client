/// OC-M-01 — the stop button must not manufacture a stop-acknowledged.
///
/// A Firestore write returning is a QUEUE acceptance. Until a dispatch result
/// comes back, the app knows nothing about motion, and the snackbar has to say
/// so. These tests pin the shipped copy: queued says "queued", and no ESTOP
/// message in the app ever says "halted".
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opencastor_client/ui/core/theme/app_theme.dart';
import 'package:opencastor_client/ui/shared/estop_feedback.dart';

/// Pumps the real production snackbar and taps the button that shows it.
Future<void> _showEstopSnackBar(WidgetTester tester, EstopAck ack) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ScaffoldMessenger.of(context)
                .showSnackBar(buildEstopSnackBar(ack)),
            child: const Text('ESTOP'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ESTOP'));
  await tester.pump(); // schedule the snackbar
  await tester.pump(const Duration(milliseconds: 750)); // finish its entrance
}

String _snackBarText(WidgetTester tester) {
  final snack = find.byType(SnackBar);
  expect(snack, findsOneWidget);
  final text = find.descendant(of: snack, matching: find.byType(Text));
  expect(text, findsOneWidget);
  return tester.widget<Text>(text).data!;
}

void main() {
  group('ESTOP snackbar copy', () {
    testWidgets('a queued write says queued and never halted',
        (tester) async {
      await _showEstopSnackBar(tester, EstopAck.queued);

      final message = _snackBarText(tester);
      expect(message.toLowerCase(), contains('queued'));
      expect(message.toLowerCase(), isNot(contains('halted')));
      expect(message.toLowerCase(), isNot(contains('robot halted')));
    });

    testWidgets('an acknowledged dispatch result says stop confirmed',
        (tester) async {
      await _showEstopSnackBar(tester, EstopAck.confirmed);

      final message = _snackBarText(tester).toLowerCase();
      expect(message, contains('confirmed'));
      expect(message, isNot(contains('not confirmed')));
      expect(message, isNot(contains('halted')));
    });

    testWidgets('a stop_not_confirmed result says NOT confirmed, in estop red',
        (tester) async {
      await _showEstopSnackBar(tester, EstopAck.notConfirmed);

      final message = _snackBarText(tester);
      expect(message, contains('NOT confirmed'));
      expect(message.toLowerCase(), isNot(contains('halted')));

      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.backgroundColor, equals(AppTheme.estop));
    });

    testWidgets('only the unconfirmed state gets the estop colour',
        (tester) async {
      for (final ack in [EstopAck.queued, EstopAck.confirmed]) {
        await _showEstopSnackBar(tester, ack);
        final snack = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snack.backgroundColor, isNot(equals(AppTheme.estop)),
            reason: '$ack must not borrow the alarm colour');
      }
    });
  });

  group('ack_qos parsing', () {
    test('acknowledged is the only value that means confirmed', () {
      expect(estopAckFromQos('acknowledged'), EstopAck.confirmed);
    });

    test('stop_not_confirmed is surfaced, not swallowed', () {
      expect(estopAckFromQos('stop_not_confirmed'), EstopAck.notConfirmed);
    });

    test('a missing or unknown ack_qos is queued, never confirmed', () {
      expect(estopAckFromQos(null), EstopAck.queued);
      expect(estopAckFromQos('queued'), EstopAck.queued);
      expect(estopAckFromQos('ack'), EstopAck.queued);
      expect(estopAckFromQos(''), EstopAck.queued);
      // The pre-fix bridge wrote this field before dispatch. Even if a stale
      // document still carries something odd, it must not read as a stop.
      expect(estopAckFromQos('ACKNOWLEDGED'), EstopAck.queued);
    });
  });

  group('no ESTOP message claims the robot halted', () {
    test('every state', () {
      for (final ack in EstopAck.values) {
        expect(estopAckMessage(ack).toLowerCase(), isNot(contains('halted')),
            reason: '$ack must not claim motion ceased');
      }
    });
  });
}
