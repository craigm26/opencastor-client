import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/hub_config.dart';
import 'explore_view_model.dart';

class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(exploreFilterProvider);
    final configs = ref.watch(exploreConfigsProvider(filter));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_outlined),
            tooltip: 'Scan QR code',
            onPressed: () => context.push('/explore/scan'),
          ),
        ],
      ),
      body: Column(
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
                    label: Text(f.name[0].toUpperCase() + f.name.substring(1)),
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
      ),
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
              // Type badge + star
              Row(
                children: [
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
        data: (config) => _ConfigDetail(config: config),
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

    return SingleChildScrollView(
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

  // ignore: prefer_final_fields
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
        type.toUpperCase(),
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
