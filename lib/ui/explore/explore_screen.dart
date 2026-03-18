import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../data/models/hub_config.dart';
import '../../data/models/harness_config.dart';
import '../../ui/harness/harness_viewer.dart';
import 'explore_view_model.dart';
import 'social_view_model.dart';

class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(exploreFilterProvider);
    final configs = ref.watch(exploreConfigsProvider(filter));
    final cs = Theme.of(context).colorScheme;
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return DefaultTabController(
      length: isLoggedIn ? 3 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Explore'),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code_scanner_outlined),
              tooltip: 'Scan QR code',
              onPressed: () => context.push('/explore/scan'),
            ),
          ],
          bottom: isLoggedIn
              ? const TabBar(tabs: [
                  Tab(text: 'Discover'),
                  Tab(text: 'My Stars'),
                  Tab(text: 'My Configs'),
                ])
              : null,
        ),
        body: isLoggedIn
            ? TabBarView(children: [
                _DiscoverTab(filter: filter, configs: configs, ref: ref),
                const _MyStarsTab(),
                const _MyConfigsTab(),
              ])
            : _DiscoverTab(filter: filter, configs: configs, ref: ref),
      ),
    );
  }
}

class _DiscoverTab extends StatelessWidget {
  const _DiscoverTab(
      {required this.filter, required this.configs, required this.ref});
  final ExploreFilter filter;
  final AsyncValue<List<HubConfig>> configs;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // ── Filter chips ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: ExploreFilter.values.map((f) {
                final selected = filter == f;
                return FilterChip(
                  label: Text(_filterLabel(f)),
                  selected: selected,
                  onSelected: (_) =>
                      ref.read(exploreFilterProvider.notifier).state = f,
                  selectedColor: cs.primaryContainer,
                  checkmarkColor: cs.primary,
                );
              }).toList(),
            ),
          ),
        ),

        // ── Config grid ─────────────────────────────────────────────
        Expanded(
          child: configs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(exploreConfigsProvider(filter)),
            ),
            data: (items) => items.isEmpty
                ? _EmptyState(filter: filter)
                : RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(exploreConfigsProvider(filter)),
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 320,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: items.length,
                      itemBuilder: (ctx, i) =>
                          _ConfigCard(config: items[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ── My Stars tab ─────────────────────────────────────────────────────────────

class _MyStarsTab extends ConsumerWidget {
  const _MyStarsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stars = ref.watch(myStarsProvider);
    return stars.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (configs) => configs.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_border, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No starred configs yet'),
                  SizedBox(height: 6),
                  Text('Tap ★ on any config to save it here',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(myStarsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: configs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _ConfigListTile(config: configs[i]),
              ),
            ),
    );
  }
}

// ── My Configs tab ────────────────────────────────────────────────────────────

class _MyConfigsTab extends ConsumerWidget {
  const _MyConfigsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myConfigs = ref.watch(myConfigsProvider);
    return myConfigs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (configs) => configs.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload_file_outlined,
                      size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No uploaded configs yet'),
                  SizedBox(height: 6),
                  Text('Share a config from your robot\'s detail screen',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(myConfigsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: configs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _ConfigListTile(
                  config: configs[i],
                  showPublishButton: !(configs[i].isPublic),
                  onPublish: () async {
                    await publishFork(configs[i].id);
                    ref.invalidate(myConfigsProvider);
                  },
                ),
              ),
            ),
    );
  }
}

class _ConfigListTile extends StatelessWidget {
  const _ConfigListTile(
      {required this.config,
      this.showPublishButton = false,
      this.onPublish});
  final HubConfig config;
  final bool showPublishButton;
  final VoidCallback? onPublish;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: _TypeBadgeIcon(type: config.type),
        title: Text(config.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${config.rcanVersion} · ${config.provider} · ${config.installs} installs',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: showPublishButton
            ? TextButton(
                onPressed: onPublish,
                child: const Text('Publish'))
            : null,
        onTap: () => context.push('/explore/${config.id}'),
      ),
    );
  }
}

class _TypeBadgeIcon extends StatelessWidget {
  const _TypeBadgeIcon({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      'skill' => Icons.extension_outlined,
      'harness' => Icons.account_tree_outlined,
      _ => Icons.settings_outlined,
    };
    return CircleAvatar(
      backgroundColor:
          Theme.of(context).colorScheme.primaryContainer,
      child: Icon(icon,
          size: 18,
          color: Theme.of(context).colorScheme.onPrimaryContainer),
    );
  }
}

// ── Config card ───────────────────────────────────────────────────────────────

class _ConfigCard extends ConsumerWidget {
  const _ConfigCard({required this.config});
  final HubConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final starred = ref.watch(starredConfigsProvider).contains(config.id);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/explore/${config.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Official badge + type badge + star
              Row(
                children: [
                  if (config.isOfficial) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('⭐ Official',
                          style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _TypeBadge(type: config.type),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => toggleStar(config.id, ref),
                    child: Icon(
                      starred ? Icons.star : Icons.star_border,
                      size: 18,
                      color: starred ? Colors.amber : cs.outlineVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Title
              Text(
                config.title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),

              // Description
              if (config.description.isNotEmpty)
                Text(
                  config.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const Spacer(),

              // Tags row
              if (config.tags.isNotEmpty)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: config.tags
                      .take(3)
                      .map((t) => _TagChip(label: t))
                      .toList(),
                ),
              const SizedBox(height: 10),

              // Footer: RCAN version + stats
              Row(
                children: [
                  Text(
                    'RCAN ${config.rcanVersion}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                        ),
                  ),
                  const Spacer(),
                  Icon(Icons.download_outlined,
                      size: 13, color: cs.outlineVariant),
                  const SizedBox(width: 2),
                  Text(
                    '${config.installs}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: cs.outlineVariant),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.star_border, size: 13, color: cs.outlineVariant),
                  const SizedBox(width: 2),
                  Text(
                    '${config.stars}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: cs.outlineVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Install button
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => _copyInstall(context, config.installCmd),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Copy Install Command'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copyInstall(BuildContext context, String cmd) {
    Clipboard.setData(ClipboardData(text: cmd));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied: $cmd'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ── Config detail screen ──────────────────────────────────────────────────────

class ExploreDetailScreen extends ConsumerWidget {
  const ExploreDetailScreen({super.key, required this.configId});
  final String configId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(hubConfigDetailProvider(configId));
    final cs = Theme.of(context).colorScheme;
    final starred = ref.watch(starredConfigsProvider).contains(configId);

    return Scaffold(
      appBar: AppBar(
        title: configAsync.whenOrNull(data: (c) => Text(c.title)) ??
            const Text('Config'),
        actions: [
          if (configAsync.hasValue)
            IconButton(
              icon: Icon(starred ? Icons.star : Icons.star_border),
              color: starred ? Colors.amber : null,
              tooltip: starred ? 'Unstar' : 'Star',
              onPressed: () => toggleStar(configId, ref),
            ),
          if (configAsync.hasValue)
            IconButton(
              icon: const Icon(Icons.open_in_browser_outlined),
              tooltip: 'View on web',
              onPressed: () => launchUrl(
                Uri.parse(configAsync.value!.webUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (config) => SingleChildScrollView(
          child: Column(
            children: [
              _ConfigDetail(config: config),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: _SocialSection(config: config),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigDetail extends StatelessWidget {
  const _ConfigDetail({required this.config});
  final HubConfig config;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              _TypeBadge(type: config.type),
              const SizedBox(width: 8),
              Text('RCAN ${config.rcanVersion}',
                  style: tt.labelSmall?.copyWith(color: cs.primary)),
              const Spacer(),
              Icon(Icons.download_outlined, size: 14, color: cs.outlineVariant),
              const SizedBox(width: 2),
              Text('${config.installs}', style: tt.labelSmall),
              const SizedBox(width: 10),
              Icon(Icons.star_border, size: 14, color: cs.outlineVariant),
              const SizedBox(width: 2),
              Text('${config.stars}', style: tt.labelSmall),
              const SizedBox(width: 10),
              Icon(Icons.call_split_outlined,
                  size: 14, color: cs.outlineVariant),
              const SizedBox(width: 2),
              Text('${config.forks}', style: tt.labelSmall),
              const SizedBox(width: 10),
              Icon(Icons.chat_bubble_outline,
                  size: 14, color: cs.outlineVariant),
              const SizedBox(width: 2),
              Text('${config.commentCount}', style: tt.labelSmall),
            ],
          ),
          const SizedBox(height: 12),

          if (config.description.isNotEmpty) ...[
            Text(config.description,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
          ],

          // Tags
          if (config.tags.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: config.tags.map((t) => _TagChip(label: t)).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // ── Inline visual for harness / skill / preset ───────────────
          if (config.type == 'harness') ...[
            Text('Pipeline',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _HarnessPreview(config: config),
            const SizedBox(height: 16),
          ] else if (config.type == 'skill') ...[
            _SkillInfoCard(config: config),
            const SizedBox(height: 16),
          ] else ...[
            _PresetSummaryCard(config: config),
            const SizedBox(height: 16),
          ],

          // Metadata cards
          _MetaRow(items: [
            ('Provider', config.provider),
            ('Hardware', config.hardware),
            ('Author', config.authorName),
          ]),
          const SizedBox(height: 16),

          // Install command
          _InstallCard(config: config),
          const SizedBox(height: 16),

          // YAML content
          if (config.content != null) ...[
            Text('Config (${config.filename})',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 400),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  config.content!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy YAML'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: config.content!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('YAML copied'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Fork + Comments section (appended to detail) ──────────────────────────────

class _SocialSection extends ConsumerStatefulWidget {
  const _SocialSection({required this.config});
  final HubConfig config;

  @override
  ConsumerState<_SocialSection> createState() => _SocialSectionState();
}

class _SocialSectionState extends ConsumerState<_SocialSection> {
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final comments = ref.watch(commentsProvider(widget.config.id));
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),

        // ── Fork row ──────────────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.call_split_outlined, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('${widget.config.forks} forks',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const Spacer(),
            if (isLoggedIn)
              FilledButton.tonal(
                onPressed: () => _showForkDialog(context),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12)),
                child: const Text('Fork & Remix'),
              ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Comments ──────────────────────────────────────────────────
        Text('Comments (${widget.config.commentCount})',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),

        if (isLoggedIn) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Add a comment...',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  maxLines: 1,
                  onSubmitted: (_) => _submitComment(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _submitting ? null : _submitComment,
                icon: _submitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_outlined, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        comments.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Text('Could not load comments',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          data: (list) => list.isEmpty
              ? Text('No comments yet. Be the first!',
                  style: tt.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant))
              : Column(
                  children: list
                      .map((c) => _CommentTile(
                          comment: c, configId: widget.config.id))
                      .toList(),
                ),
        ),
      ],
    );
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await addComment(widget.config.id, text);
      _commentCtrl.clear();
      ref.invalidate(commentsProvider(widget.config.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'),
              behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showForkDialog(BuildContext ctx) async {
    String title = '${widget.config.title} (fork)';
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Fork Config'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Create a private copy of "${widget.config.title}" you can edit and publish.',
                style: Theme.of(dCtx).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                  labelText: 'Fork title', border: OutlineInputBorder()),
              controller: TextEditingController(text: title),
              onChanged: (v) => title = v,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Fork')),
        ],
      ),
    );

    if (confirmed != true || !ctx.mounted) return;

    try {
      final result = await forkConfig(
          widget.config.id, title, [...widget.config.tags, 'fork']);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: const Text('Forked! Find it in My Configs.'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
                label: 'View',
                onPressed: () => ctx.push('/explore/${result['id']}')),
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
              content: Text('Fork failed: $e'),
              behavior: SnackBarBehavior.floating),
        );
      }
    }
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({required this.comment, required this.configId});
  final HubComment comment;
  final String configId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isOwn = currentUid == comment.authorUid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primaryContainer,
            child: Text(
              comment.authorName.isNotEmpty
                  ? comment.authorName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                  fontSize: 11, color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.authorName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('MMM d').format(comment.createdAt),
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                    if (isOwn) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () async {
                          await deleteComment(configId, comment.id);
                          ref.invalidate(commentsProvider(configId));
                        },
                        child: Icon(Icons.delete_outline,
                            size: 14, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text,
                    style: const TextStyle(fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstallCard extends StatelessWidget {
  const _InstallCard({required this.config});
  final HubConfig config;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Install command',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  )),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  config.installCmd,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: cs.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: config.installCmd));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied!'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final String type;

  static const _colors = {
    'preset': Color(0xFF0ea5e9),
    'skill': Color(0xFF7c3aed),
    'harness': Color(0xFF059669),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[type] ?? const Color(0xFF6b7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        _typeDisplayLabel(type),
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color,
            letterSpacing: 0.5),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: cs.onSurfaceVariant)),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.items});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: items.map((item) {
        final (label, value) = item;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 10,
                        )),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});
  final ExploreFilter filter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.explore_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            filter == ExploreFilter.all
                ? 'No configs on the hub yet'
                : 'No ${filter.name}s yet',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Be the first to share one!',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text('Could not load hub', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            message.length > 80 ? '${message.substring(0, 80)}…' : message,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ── Display helpers ───────────────────────────────────────────────────────────

/// Human-readable label for the type badge (display only — Firestore value unchanged).
String _typeDisplayLabel(String type) {
  switch (type) {
    case 'preset':
      return 'CONFIG';
    case 'skill':
      return 'SKILL';
    case 'harness':
      return 'HARNESS';
    default:
      return type.toUpperCase();
  }
}

/// Human-readable label for filter chips.
String _filterLabel(ExploreFilter f) {
  switch (f) {
    case ExploreFilter.all:
      return 'All';
    case ExploreFilter.preset:
      return 'Community Configs';
    case ExploreFilter.skill:
      return 'Skills';
    case ExploreFilter.harness:
      return 'Harnesses';
  }
}

// ── Inline harness preview ────────────────────────────────────────────────────

class _HarnessPreview extends StatelessWidget {
  const _HarnessPreview({required this.config});
  final HubConfig config;

  HarnessConfig _buildHarnessConfig() {
    // yaml package not available — use defaults visual (same pipeline for all
    // harness configs). The visual pipeline is what matters for exploration.
    return HarnessConfig.defaults(robotRrn: config.robotRrn ?? config.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final harnessConfig = _buildHarnessConfig();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
        color: cs.surfaceContainerLowest,
      ),
      constraints: const BoxConstraints(maxHeight: 480),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: HarnessViewer(
          config: harnessConfig,
          // readOnly: no onEditLayer callback passed → edit buttons hidden
        ),
      ),
    );
  }
}

// ── Skill info card ───────────────────────────────────────────────────────────

class _SkillInfoCard extends StatelessWidget {
  const _SkillInfoCard({required this.config});
  final HubConfig config;

  static String _scope(String title) {
    final t = title.toLowerCase();
    if (t.contains('navigate') || t.contains('arm') || t.contains('manipulat')) {
      return 'control';
    }
    if (t.contains('camera') || t.contains('describe') || t.contains('vision')) {
      return 'status';
    }
    return 'chat';
  }

  static Color _scopeColor(String scope) {
    switch (scope) {
      case 'control':
        return const Color(0xFFef4444);
      case 'status':
        return const Color(0xFF0ea5e9);
      default:
        return const Color(0xFF7c3aed);
    }
  }

  static IconData _scopeIcon(String scope) {
    switch (scope) {
      case 'control':
        return Icons.gamepad_outlined;
      case 'status':
        return Icons.monitor_heart_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  static String _slashCommand(String title) {
    // Derive slash command from skill title/tags
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '/$slug';
  }

  static List<String> _bullets(String title) {
    final t = title.toLowerCase();
    if (t.contains('navigate')) {
      return [
        'Sends robot to a named waypoint or coordinates',
        'Supports obstacle-aware pathfinding',
        'Returns navigation status in real time',
      ];
    }
    if (t.contains('camera') || t.contains('describe')) {
      return [
        'Captures current camera frame',
        'Runs vision model to describe the scene',
        'Returns a natural-language description',
      ];
    }
    if (t.contains('arm') || t.contains('manipulat')) {
      return [
        'Moves arm to specified joint angles or pose',
        'Controls gripper open/close',
        'Supports pick-and-place primitives',
      ];
    }
    if (t.contains('web') || t.contains('lookup')) {
      return [
        'Searches the web for up-to-date information',
        'Returns summarised results to the agent',
      ];
    }
    if (t.contains('peer') || t.contains('coordinate')) {
      return [
        'Discovers other robots on the RCAN mesh',
        'Delegates sub-tasks to peer agents',
      ];
    }
    if (t.contains('code') || t.contains('review')) {
      return [
        'Analyses code files for bugs and style issues',
        'Outputs structured review comments',
      ];
    }
    return [
      'Extends robot capabilities via slash command',
      'Integrates with the RCAN skill pipeline',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final scope = _scope(config.title);
    final scopeColor = _scopeColor(scope);
    final cmd = _slashCommand(config.title);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scope badge row
          Row(
            children: [
              Icon(_scopeIcon(scope), size: 16, color: scopeColor),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scopeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scopeColor.withOpacity(0.35)),
                ),
                child: Text(
                  'RCAN scope: $scope',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: scopeColor,
                      letterSpacing: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // What this skill does
          Text('What this skill does',
              style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ..._bullets(config.title).map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ',
                        style: TextStyle(
                            color: scopeColor, fontWeight: FontWeight.w700)),
                    Expanded(
                        child: Text(b,
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant))),
                  ],
                ),
              )),
          const SizedBox(height: 12),

          // Example slash command
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 13, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  '$cmd <args>',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: cs.primary,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Preset / community-config summary card ────────────────────────────────────

class _PresetSummaryCard extends StatelessWidget {
  const _PresetSummaryCard({required this.config});
  final HubConfig config;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final chips = <(String, String, Color)>[
      if (config.provider.isNotEmpty)
        ('Provider', config.provider, const Color(0xFF0ea5e9)),
      if (config.hardware.isNotEmpty)
        ('Hardware', config.hardware, const Color(0xFF22c55e)),
      if (config.rcanVersion.isNotEmpty)
        ('RCAN', config.rcanVersion, const Color(0xFFa855f7)),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Robot Config',
              style:
                  tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips.map((chip) {
              final (label, value, color) = chip;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.35)),
                ),
                child: RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(
                          text: '$label: ',
                          style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w500)),
                      TextSpan(
                          text: value,
                          style: TextStyle(
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
