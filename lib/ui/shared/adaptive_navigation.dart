/// Adaptive scaffold that adjusts navigation layout based on screen width.
///
/// - Mobile (< 600dp):  NavigationBar at bottom
/// - Tablet (600-1200dp): NavigationRail on left
/// - Desktop/Web (> 1200dp): NavigationDrawer on left
library;

import 'package:flutter/material.dart';

class AdaptiveScaffold extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onDestinationSelected;
  final Widget body;
  final List<NavigationDestination> destinations;
  final Widget? floatingActionButton;

  const AdaptiveScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    required this.destinations,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= 1200) {
      return _DrawerLayout(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        body: body,
        destinations: destinations,
        floatingActionButton: floatingActionButton,
      );
    } else if (width >= 600) {
      return _RailLayout(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        body: body,
        destinations: destinations,
        floatingActionButton: floatingActionButton,
      );
    } else {
      return _BottomBarLayout(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        body: body,
        destinations: destinations,
        floatingActionButton: floatingActionButton,
      );
    }
  }
}

// ── Mobile: bottom NavigationBar ─────────────────────────────────────────────

class _BottomBarLayout extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onDestinationSelected;
  final Widget body;
  final List<NavigationDestination> destinations;
  final Widget? floatingActionButton;

  const _BottomBarLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    required this.destinations,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

// ── Tablet: NavigationRail on left ───────────────────────────────────────────

class _RailLayout extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onDestinationSelected;
  final Widget body;
  final List<NavigationDestination> destinations;
  final Widget? floatingActionButton;

  const _RailLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    required this.destinations,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            labelType: NavigationRailLabelType.selected,
            destinations: destinations
                .map(
                  (d) => NavigationRailDestination(
                    icon: d.icon,
                    selectedIcon: d.selectedIcon ?? d.icon,
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

// ── Desktop/Web: NavigationDrawer on left ────────────────────────────────────

class _DrawerLayout extends StatelessWidget {
  final int selectedIndex;
  final void Function(int) onDestinationSelected;
  final Widget body;
  final List<NavigationDestination> destinations;
  final Widget? floatingActionButton;

  const _DrawerLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    required this.destinations,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          // Permanent side drawer
          Container(
            width: 280,
            color: cs.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OpenCastor',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                ...destinations.asMap().entries.map(
                  (entry) {
                    final i = entry.key;
                    final d = entry.value;
                    final selected = i == selectedIndex;
                    return ListTile(
                      selected: selected,
                      selectedTileColor: cs.secondaryContainer,
                      leading:
                          selected ? (d.selectedIcon ?? d.icon) : d.icon,
                      title: Text(d.label),
                      onTap: () => onDestinationSelected(i),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
