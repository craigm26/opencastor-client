/// Consent Request Screen — RCAN v1.5 GAP-05 (Consent Wire Protocol)
///
/// Allows the authenticated user to request consent from another robot's owner.
/// Follows MVVM + Riverpod pattern — no business logic in build().
///
/// Flow:
///   1. User selects target robot RRN (text field or picker)
///   2. User selects requested scopes (checkboxes)
///   3. User sets expiry (1h / 24h / 7 days / permanent)
///   4. User taps "Send Request" → calls `requestConsent` Cloud Function
///      via [ConsentRepository.requestAccess]
///
/// See also: [PendingConsentScreen] for the receiving side.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../explore/qr_scanner_screen.dart' show parseRrnFromScan;
import '../../core/constants.dart';
import '../../data/models/robot.dart';
import '../../data/repositories/consent_repository.dart';
import '../../data/repositories/consent_repository_provider.dart';
import '../../data/repositories/robot_repository.dart';
import '../../ui/core/theme/app_theme.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;

// ── Providers ─────────────────────────────────────────────────────────────────

// Use the global wired-up provider
final _consentRepositoryProvider = consentRepositoryProvider;

final _myFleetProvider = StreamProvider<List<Robot>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  return ref.read(robotRepositoryProvider).watchFleet(uid);
});

// ── State ─────────────────────────────────────────────────────────────────────

/// All available RCAN v1.5 scopes (RCAN spec §11.2).
const _allScopes = ['discover', 'status', 'chat', 'control', 'safety'];

/// Duration options for consent expiry.
const _durationOptions = [
  (label: '1 hour', hours: 1),
  (label: '24 hours', hours: 24),
  (label: '7 days', hours: 168),
  (label: 'Permanent', hours: 0),
];

/// ViewModel state for the consent request form.
class _ConsentFormState {
  final String targetRrn;
  final Set<String> selectedScopes;
  final int durationHours; // 0 = permanent
  final String reason;
  final bool isSubmitting;
  final String? errorMessage;
  final bool isSuccess;

  const _ConsentFormState({
    this.targetRrn = '',
    this.selectedScopes = const {'status'},
    this.durationHours = 24,
    this.reason = '',
    this.isSubmitting = false,
    this.errorMessage,
    this.isSuccess = false,
  });

  _ConsentFormState copyWith({
    String? targetRrn,
    Set<String>? selectedScopes,
    int? durationHours,
    String? reason,
    bool? isSubmitting,
    String? errorMessage,
    bool? isSuccess,
  }) =>
      _ConsentFormState(
        targetRrn: targetRrn ?? this.targetRrn,
        selectedScopes: selectedScopes ?? this.selectedScopes,
        durationHours: durationHours ?? this.durationHours,
        reason: reason ?? this.reason,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        errorMessage: errorMessage,
        isSuccess: isSuccess ?? this.isSuccess,
      );
}

class _ConsentFormNotifier extends AutoDisposeNotifier<_ConsentFormState> {
  @override
  _ConsentFormState build() => const _ConsentFormState();

  void setTargetRrn(String rrn) =>
      state = state.copyWith(targetRrn: rrn.trim());

  void setReason(String reason) => state = state.copyWith(reason: reason);

  void setDuration(int hours) =>
      state = state.copyWith(durationHours: hours);

  void toggleScope(String scope) {
    final scopes = Set<String>.from(state.selectedScopes);
    if (scopes.contains(scope)) {
      scopes.remove(scope);
    } else {
      scopes.add(scope);
    }
    state = state.copyWith(selectedScopes: scopes);
  }

  /// Submit the consent request via [ConsentRepository.requestAccess].
  Future<void> submit({
    required String sourceRrn,
    required String sourceOwner,
    required String sourceRuri,
    required ConsentRepository repo,
  }) async {
    if (state.targetRrn.isEmpty) {
      state = state.copyWith(errorMessage: 'Please enter a target RRN');
      return;
    }
    if (state.selectedScopes.isEmpty) {
      state = state.copyWith(errorMessage: 'Select at least one scope');
      return;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: null);
    try {
      await repo.requestAccess(
        targetRrn: state.targetRrn,
        sourceRrn: sourceRrn,
        sourceOwner: sourceOwner,
        sourceRuri: sourceRuri,
        requestedScopes: state.selectedScopes.toList(),
        reason: state.reason.isEmpty
            ? 'Access requested via OpenCastor app'
            : state.reason,
        durationHours: state.durationHours,
      );
      state = state.copyWith(isSubmitting: false, isSuccess: true);
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.toString(),
      );
    }
  }
}

final _consentFormProvider =
    AutoDisposeNotifierProvider<_ConsentFormNotifier, _ConsentFormState>(
  _ConsentFormNotifier.new,
);

// ── Screen ────────────────────────────────────────────────────────────────────

class ConsentScreen extends ConsumerWidget {
  /// Optional RRN — when provided (from robot detail shortcut), shows a
  /// tabbed view with Request Access + Training Consent tabs.
  final String? rrn;
  const ConsentScreen({super.key, this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formState = ref.watch(_consentFormProvider);

    if (formState.isSuccess) {
      return _SuccessView(
        targetRrn: formState.targetRrn,
        onDone: () => context.pop(),
      );
    }

    // When accessed via robot detail shortcut (rrn provided), show tabs.
    if (rrn != null) {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Consent'),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Consent Docs',
                onPressed: () =>
                    launchUrl(Uri.parse(AppConstants.docsConsent)),
              ),
              TextButton(
                onPressed: () => context.push('/consent/pending'),
                child: const Text('Pending'),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Request Access'),
                Tab(text: 'Training Data'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _ConsentRequestForm(),
              ),
              _TrainingConsentTab(rrn: rrn!),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Robot Access'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Consent Docs',
            onPressed: () =>
                launchUrl(Uri.parse(AppConstants.docsConsent)),
          ),
          TextButton(
            onPressed: () =>
                context.push('/consent/pending'),
            child: const Text('Pending'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _ConsentRequestForm(),
      ),
    );
  }
}

// ── Training Consent Tab ──────────────────────────────────────────────────────

class _TrainingConsentTab extends StatelessWidget {
  final String rrn;
  const _TrainingConsentTab({required this.rrn});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('robots')
          .doc(rrn)
          .collection('consent')
          .doc('training')
          .collection('records')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No training consent records',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final consentId = data['consent_id'] as String? ?? docs[i].id;
            final grantedAt = data['granted_at'];
            String grantedLabel = 'Unknown date';
            if (grantedAt != null) {
              try {
                final dt = (grantedAt as dynamic).toDate() as DateTime;
                grantedLabel = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
              } catch (_) {}
            }
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(consentId, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text('Granted: $grantedLabel', style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline, color: cs.error),
                  tooltip: 'Revoke consent',
                  onPressed: () => docs[i].reference.delete(),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ConsentRequestForm extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ConsentRequestForm> createState() =>
      _ConsentRequestFormState();
}

class _ConsentRequestFormState
    extends ConsumerState<_ConsentRequestForm> {
  final _rrnCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _rrnCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  /// Open a bottom sheet with the QR scanner to read a robot's RRN.
  /// Parses formats: QR shows bare RRN, rcan:// URI, or opencastor.com URL.
  Future<void> _scanRrn(
      BuildContext context, _ConsentFormNotifier notifier) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _RrnScannerSheet(),
    );
    if (result != null && result.isNotEmpty && mounted) {
      _rrnCtrl.text = result;
      notifier.setTargetRrn(result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('RRN set: $result'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(_consentFormProvider);
    final notifier = ref.read(_consentFormProvider.notifier);
    final myFleet = ref.watch(_myFleetProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Text(
          'Request Access to a Robot',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'The target robot\'s owner will receive a notification '
          'to approve or deny your request.',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),

        // ── Source robot (my robot making the request) ─────────────────
        _SectionHeader(label: '1. Your Robot (Requester)'),
        const SizedBox(height: 8),
        myFleet.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Could not load fleet'),
          data: (robots) {
            if (robots.isEmpty) {
              return Text(
                'No robots in your fleet. Add a robot first.',
                style: TextStyle(color: cs.error),
              );
            }
            return _RobotPickerDropdown(
              robots: robots,
              label: 'Select your robot',
            );
          },
        ),
        const SizedBox(height: 20),

        // ── Target RRN ─────────────────────────────────────────────────
        _SectionHeader(label: '2. Target Robot RRN'),
        const SizedBox(height: 8),
        TextField(
          controller: _rrnCtrl,
          decoration: InputDecoration(
            hintText: 'RRN-000000000005',
            labelText: 'Target Robot RRN',
            border: const OutlineInputBorder(),
            prefixIcon:
                const Icon(Icons.precision_manufacturing_outlined),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner_outlined),
              tooltip: 'Scan robot QR code',
              onPressed: () => _scanRrn(context, notifier),
            ),
          ),
          onChanged: notifier.setTargetRrn,
        ),
        const SizedBox(height: 20),

        // ── Requested scopes ───────────────────────────────────────────
        _SectionHeader(label: '3. Requested Scopes'),
        const SizedBox(height: 4),
        Text(
          'Select only what you need. The owner sees exactly these scopes.',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        ..._allScopes.map((scope) => _ScopeCheckTile(
              scope: scope,
              selected: formState.selectedScopes.contains(scope),
              onChanged: (_) => notifier.toggleScope(scope),
            )),
        const SizedBox(height: 20),

        // ── Expiry ─────────────────────────────────────────────────────
        _SectionHeader(label: '4. Access Duration'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _durationOptions
              .map((opt) => ChoiceChip(
                    label: Text(opt.label),
                    selected: formState.durationHours == opt.hours,
                    onSelected: (_) => notifier.setDuration(opt.hours),
                  ))
              .toList(),
        ),
        const SizedBox(height: 20),

        // ── Reason ────────────────────────────────────────────────────
        _SectionHeader(label: '5. Reason (optional)'),
        const SizedBox(height: 8),
        TextField(
          controller: _reasonCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Why do you need access to this robot?',
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
          onChanged: notifier.setReason,
        ),
        const SizedBox(height: 24),

        // ── Error ──────────────────────────────────────────────────────
        if (formState.errorMessage != null) ...[
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              formState.errorMessage!,
              style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Submit ─────────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                formState.isSubmitting ? null : () => _submit(ref),
            icon: formState.isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(
                formState.isSubmitting ? 'Sending…' : 'Send Request'),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _submit(WidgetRef ref) async {
    final myFleet = ref.read(_myFleetProvider).asData?.value ?? [];
    if (myFleet.isEmpty) return;

    final sourceRobot = myFleet.first; // Use first robot as source
    final repo = ref.read(_consentRepositoryProvider);
    final user = FirebaseAuth.instance.currentUser;

    await ref.read(_consentFormProvider.notifier).submit(
          sourceRrn: sourceRobot.rrn,
          sourceOwner: user?.uid ?? '',
          sourceRuri: sourceRobot.ruri,
          repo: repo,
        );
  }
}

// ── Success view ──────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  final String targetRrn;
  final VoidCallback onDone;

  const _SuccessView({required this.targetRrn, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Sent')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 64, color: AppTheme.online),
              const SizedBox(height: 20),
              Text(
                'Consent request sent',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'The owner of $targetRrn will receive a notification '
                'to approve or deny your request.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: onDone,
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    );
  }
}

class _ScopeCheckTile extends StatelessWidget {
  final String scope;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  static const _descriptions = {
    'discover': 'Discover robot presence and network location',
    'status': 'Read robot status and telemetry',
    'chat': 'Send natural-language instructions',
    'control': 'Send physical control commands (arm, drive)',
    'safety': 'Send safety commands (ESTOP, RESUME)',
  };

  static const _scopeColors = {
    'control': Colors.red,
    'safety': Colors.deepOrange,
    'chat': Colors.blue,
    'status': Colors.teal,
    'discover': Colors.grey,
  };

  const _ScopeCheckTile({
    required this.scope,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = _scopeColors[scope] ?? Colors.grey;
    final desc = _descriptions[scope] ?? scope;
    final cs = Theme.of(context).colorScheme;

    return CheckboxListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      value: selected,
      onChanged: onChanged,
      title: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              scope,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      subtitle: Text(desc,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    );
  }
}

class _RobotPickerDropdown extends ConsumerStatefulWidget {
  final List<Robot> robots;
  final String label;
  const _RobotPickerDropdown({required this.robots, required this.label});

  @override
  ConsumerState<_RobotPickerDropdown> createState() =>
      _RobotPickerDropdownState();
}

class _RobotPickerDropdownState
    extends ConsumerState<_RobotPickerDropdown> {
  Robot? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.robots.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Robot>(
      value: _selected,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
      ),
      items: widget.robots
          .map((r) => DropdownMenuItem(
                value: r,
                child: Text('${r.name} (${r.rrn})'),
              ))
          .toList(),
      onChanged: (r) => setState(() => _selected = r),
    );
  }
}

// ── RRN Scanner bottom sheet ──────────────────────────────────────────────────

class _RrnScannerSheet extends StatefulWidget {
  const _RrnScannerSheet();

  @override
  State<_RrnScannerSheet> createState() => _RrnScannerSheetState();
}

class _RrnScannerSheetState extends State<_RrnScannerSheet> {
  final _manualCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final rrn = parseRrnFromScan(raw.trim());
    if (rrn != null) {
      Navigator.of(context).pop(rrn);
    } else {
      setState(() => _error = 'Could not find an RRN in "$raw"');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Text('Scan Robot QR Code',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'Point your camera at the robot\'s QR code display, '
            'or enter the RRN manually below.',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // Camera scanner (mobile_scanner on native, placeholder on web)
          SizedBox(
            width: double.infinity,
            height: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: kIsWeb
                  ? Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: cs.outlineVariant,
                            style: BorderStyle.solid),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_scanner,
                              size: 56, color: cs.onSurfaceVariant),
                          const SizedBox(height: 10),
                          Text(
                            'Camera scanner unavailable on web',
                            style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Use manual entry below',
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : MobileScanner(
                      onDetect: (capture) {
                        final barcode = capture.barcodes.firstOrNull;
                        if (barcode?.rawValue != null) {
                          _submit(barcode!.rawValue!);
                        }
                      },
                    ),
            ),
          ),

          const SizedBox(height: 20),

          // Manual entry fallback
          TextField(
            controller: _manualCtrl,
            autofocus: false,
            decoration: InputDecoration(
              labelText: 'Or enter RRN / URL manually',
              hintText: 'RRN-000000000005',
              border: const OutlineInputBorder(),
              errorText: _error,
              suffixIcon: IconButton(
                icon: const Icon(Icons.check_circle_outline),
                tooltip: 'Use this RRN',
                onPressed: () => _submit(_manualCtrl.text),
              ),
            ),
            onSubmitted: _submit,
            textInputAction: TextInputAction.done,
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Use This RRN'),
              onPressed: () => _submit(_manualCtrl.text),
            ),
          ),
        ],
      ),
    );
  }
}
