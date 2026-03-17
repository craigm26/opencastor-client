/// Ecosystem Section — shown on the login screen below the sign-in card.
///
/// Displays cards for each OpenCastor ecosystem component with links.
/// Mobile: horizontally scrollable row. Wide screens: wrapped grid.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';

// ── Data ──────────────────────────────────────────────────────────────────────

class _EcosystemItem {
  final String emoji;
  final String name;
  final String description;
  final String? version;
  final String? installCommand;
  final List<({String label, String url})> links;

  const _EcosystemItem({
    required this.emoji,
    required this.name,
    required this.description,
    this.version,
    this.installCommand,
    required this.links,
  });
}

const _items = [
  _EcosystemItem(
    emoji: '🤖',
    name: 'OpenCastor',
    description: 'Robot runtime & AI brain',
    version: AppConstants.opencastorReleaseVersion,
    installCommand:
        'pip install opencastor==${AppConstants.opencastorReleaseVersion}',
    links: [
      (label: 'GitHub', url: AppConstants.opencastorGitHub),
      (label: 'Docs', url: AppConstants.docsRoot),
    ],
  ),
  _EcosystemItem(
    emoji: '📡',
    name: 'RCAN Protocol',
    description: 'Robot communication standard',
    version: 'v1.6 · 19 spec sections',
    links: [
      (label: 'Spec', url: AppConstants.rcanSpecUrl),
      (label: 'rcan.dev', url: AppConstants.rcanDevUrl),
    ],
  ),
  _EcosystemItem(
    emoji: '🗂️',
    name: 'Robot Registry Foundation',
    description: 'Robot identity & RRNs',
    links: [
      (label: 'RRF', url: AppConstants.rrfUrl),
      (label: 'Register', url: AppConstants.rrfRegisterUrl),
    ],
  ),
  _EcosystemItem(
    emoji: '🐍',
    name: 'rcan-py',
    description: 'Python SDK',
    version: '0.6.0',
    installCommand: 'pip install rcan==0.6.0',
    links: [
      (label: 'PyPI', url: AppConstants.rcanPyPypi),
      (label: 'GitHub', url: AppConstants.rcanPyGitHub),
    ],
  ),
  _EcosystemItem(
    emoji: '📦',
    name: 'rcan-ts',
    description: 'TypeScript SDK',
    version: '0.6.0',
    installCommand: 'npm install @continuonai/rcan@0.6.0',
    links: [
      (label: 'npm', url: AppConstants.rcanTsNpm),
      (label: 'GitHub', url: AppConstants.rcanTsGitHub),
    ],
  ),
];

// ── Widget ────────────────────────────────────────────────────────────────────

class EcosystemSection extends StatefulWidget {
  const EcosystemSection({super.key});

  @override
  State<EcosystemSection> createState() => _EcosystemSectionState();
}

class _EcosystemSectionState extends State<EcosystemSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        // Header — tappable to expand/collapse
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.hub_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Ecosystem',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: cs.primary,
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              // Wide (web/tablet): show 3-column wrap grid
              if (constraints.maxWidth >= 600) {
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _items
                      .map((item) => SizedBox(
                            width: (constraints.maxWidth - 20) / 3,
                            child: _EcosystemCard(item: item),
                          ))
                      .toList(),
                );
              }
              // Mobile: horizontal scroll
              return SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => SizedBox(
                    width: 200,
                    child: _EcosystemCard(item: _items[i]),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _EcosystemCard extends StatelessWidget {
  final _EcosystemItem item;
  const _EcosystemCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Emoji + name
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        item.description,
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Version pill
            if (item.version != null) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.version!,
                  style: TextStyle(
                      fontSize: 10,
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],

            // Install command
            if (item.installCommand != null) ...[
              const SizedBox(height: 4),
              Text(
                item.installCommand!,
                style: const TextStyle(
                    fontFamily: 'JetBrainsMono', fontSize: 9),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Links
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: item.links
                  .map((link) => _LinkChip(label: link.label, url: link.url))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  final String label;
  final String url;
  const _LinkChip({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      avatar: const Icon(Icons.open_in_new, size: 10),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      onPressed: () => launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication),
    );
  }
}
