/// Honest ESTOP feedback — OC-M-01.
///
/// A stop button must never claim that motion ceased on the strength of a
/// queue write. Writing a command document to Firestore proves one thing: the write
/// succeeded. It does not prove the cloud bridge picked the command up, that
/// the bridge dispatched it to the runtime, or that any motor stopped turning.
///
/// The app therefore has exactly three states to report:
///
///   * [EstopAck.queued]       — the command was accepted into the queue.
///                               Nothing is known about motion.
///   * [EstopAck.confirmed]    — a dispatch result came back: either the
///                               robot's own LAN API answered 2xx, or the
///                               bridge wrote `ack_qos: acknowledged` onto the
///                               command document from its dispatch result.
///   * [EstopAck.notConfirmed] — the stop was dispatched and no acknowledgement
///                               arrived (the bridge wrote
///                               `ack_qos: stop_not_confirmed`, or the
///                               acknowledgement deadline passed here).
///
/// The copy in [estopAckMessage] is the externally checkable artifact: none of
/// it claims motion ceased, and a confirmation reports what came back from the
/// dispatch, not what the hardware did.
library;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// What the app actually knows about a stop it sent.
enum EstopAck { queued, confirmed, notConfirmed }

/// How long the app waits for an acknowledgement before it says so out loud.
///
/// This is the PHONE's own wait budget, not the bridge's. The bridge's
/// ESTOP_ACK_DEADLINE_S is 2 s and covers only its own write; this one has to
/// cover that plus the Firestore round trip back to the handset, so it is
/// deliberately longer. Staying silent past this point would leave the
/// optimistic "queued" message on screen forever, which reads as success;
/// saying "not confirmed" is the honest fallback.
const Duration kEstopAckDeadline = Duration(seconds: 10);

/// Maps the `ack_qos` field the cloud bridge writes onto a command document.
///
/// Anything unknown, missing, or still literally `queued` is [EstopAck.queued]:
/// absence of an acknowledgement is never evidence of a stop.
EstopAck estopAckFromQos(String? ackQos) {
  switch (ackQos) {
    case 'acknowledged':
      return EstopAck.confirmed;
    case 'stop_not_confirmed':
      return EstopAck.notConfirmed;
    default:
      return EstopAck.queued;
  }
}

/// The one place ESTOP result copy is written. Keep it literal.
String estopAckMessage(EstopAck ack) {
  switch (ack) {
    case EstopAck.queued:
      return 'ESTOP queued — stop not confirmed yet';
    case EstopAck.confirmed:
      return 'ESTOP stop confirmed by the robot';
    case EstopAck.notConfirmed:
      return 'ESTOP stop NOT confirmed — check the robot';
  }
}

/// The snackbar every ESTOP path shows. `notConfirmed` carries the estop colour
/// so an unconfirmed stop is the loudest thing on the screen.
SnackBar buildEstopSnackBar(EstopAck ack) {
  return SnackBar(
    key: estopSnackBarKey(ack),
    content: Text(estopAckMessage(ack)),
    backgroundColor:
        ack == EstopAck.notConfirmed ? AppTheme.estop : null,
    duration: ack == EstopAck.queued
        ? const Duration(seconds: 3)
        : const Duration(seconds: 5),
  );
}

/// Stable key per state so widget tests and screenshots can name them.
Key estopSnackBarKey(EstopAck ack) => Key('estop-snackbar-${ack.name}');
