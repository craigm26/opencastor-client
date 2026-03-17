/// SetupScreen — Route: /setup?robot=<name>&owner=<owner>
///
/// Purpose: User lands here from the QR code shown during `castor setup`.
/// Flow:
///   1. Sign in with Google button (if not signed in)
///   2. "Your Firebase UID is: GAi2kq961z..." (after sign-in)
///   3. Copy UID button → clipboard
///   4. "Paste this into your terminal to complete setup"
///   5. QR code of the UID (optional — shown if qr_flutter is available)
///   6. Deep link back: opencastor://setup?uid={firebase_uid}
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class SetupScreen extends StatefulWidget {
  final String? robotName;
  final String? ownerName;

  const SetupScreen({
    super.key,
    this.robotName,
    this.ownerName,
  });

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _copied = false;
  bool _signingIn = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final provider = GoogleAuthProvider();
      await FirebaseAuth.instance.signInWithPopup(provider);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _signingIn = false);
    }
  }

  Future<void> _copyUid(String uid) async {
    await Clipboard.setData(ClipboardData(text: uid));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenCastor Setup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/fleet');
            }
          },
        ),
      ),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final user = snapshot.data;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _SetupHeader(
                  robotName: widget.robotName,
                  ownerName: widget.ownerName,
                ),
                const SizedBox(height: 32),

                if (user == null) ...[
                  // Not signed in — show sign-in prompt
                  _SignInCard(
                    signingIn: _signingIn,
                    error: _error,
                    onSignIn: _signInWithGoogle,
                  ),
                ] else ...[
                  // Signed in — show UID
                  _UidCard(
                    uid: user.uid,
                    displayName: user.displayName,
                    email: user.email,
                    copied: _copied,
                    onCopy: () => _copyUid(user.uid),
                    onSignOut: () => FirebaseAuth.instance.signOut(),
                  ),
                  const SizedBox(height: 24),
                  _InstructionsCard(uid: user.uid),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _SetupHeader extends StatelessWidget {
  final String? robotName;
  final String? ownerName;

  const _SetupHeader({this.robotName, this.ownerName});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.smart_toy_outlined, size: 48, color: colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Connect Your Robot',
          style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (robotName != null || ownerName != null) ...[
          Wrap(
            spacing: 8,
            children: [
              if (robotName != null)
                Chip(
                  avatar: const Icon(Icons.precision_manufacturing, size: 16),
                  label: Text('Robot: $robotName'),
                ),
              if (ownerName != null)
                Chip(
                  avatar: const Icon(Icons.person, size: 16),
                  label: Text('Owner: $ownerName'),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'Sign in with Google to get your Firebase UID. '
          'Then paste it into your terminal to complete setup.',
          style: textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sign-in card
// ---------------------------------------------------------------------------

class _SignInCard extends StatelessWidget {
  final bool signingIn;
  final String? error;
  final VoidCallback onSignIn;

  const _SignInCard({
    required this.signingIn,
    required this.error,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.login,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Step 1: Sign in',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Sign in with Google to reveal your Firebase UID. '
              'This ID is your robot\'s secret credential — keep it safe.',
            ),
            const SizedBox(height: 20),
            if (error != null) ...[
              Text(
                error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: signingIn ? null : onSignIn,
                icon: signingIn
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.g_mobiledata, size: 24),
                label: Text(signingIn ? 'Signing in…' : 'Sign in with Google'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// UID card (shown after sign-in)
// ---------------------------------------------------------------------------

class _UidCard extends StatelessWidget {
  final String uid;
  final String? displayName;
  final String? email;
  final bool copied;
  final VoidCallback onCopy;
  final VoidCallback onSignOut;

  const _UidCard({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.copied,
    required this.onCopy,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signed in as ${displayName ?? email ?? 'user'}',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (email != null)
                        Text(
                          email!,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onSignOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Your Firebase UID',
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outline),
              ),
              child: SelectableText(
                uid,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCopy,
                icon: Icon(copied ? Icons.check : Icons.copy),
                label: Text(copied ? 'Copied!' : 'Copy UID'),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      copied ? Colors.green : colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Instructions card
// ---------------------------------------------------------------------------

class _InstructionsCard extends StatelessWidget {
  final String uid;

  const _InstructionsCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terminal, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Step 2: Complete Setup',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Go back to your terminal. When prompted for your setup token, paste the UID above.',
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '  Paste your setup token (Firebase UID): ',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade300,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    '  $uid',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '✅ After pasting, your robot will connect to the Fleet UI within 30 seconds.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
