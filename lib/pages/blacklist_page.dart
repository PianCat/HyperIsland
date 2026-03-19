import 'package:flutter/material.dart';
import '../controllers/blacklist_controller.dart';
import '../l10n/app_localizations.dart';

class BlacklistPage extends StatefulWidget {
  const BlacklistPage({super.key});

  @override
  State<BlacklistPage> createState() => _BlacklistPageState();
}

class _BlacklistPageState extends State<BlacklistPage> {
  late final BlacklistController _ctrl;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final Set<String> _selectedPackages = {};
  bool _inSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _ctrl = BlacklistController();
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void deactivate() {
    _searchFocus.unfocus();
    super.deactivate();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _selectionMode => _inSelectionMode;

  void _enterSelectionMode([String? pkg]) {
    setState(() {
      _inSelectionMode = true;
      if (pkg != null) _selectedPackages.add(pkg);
    });
  }

  void _toggleSelection(String pkg) {
    setState(() {
      if (_selectedPackages.contains(pkg)) {
        _selectedPackages.remove(pkg);
      } else {
        _selectedPackages.add(pkg);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedPackages.addAll(_ctrl.filteredApps.map((a) => a.packageName));
    });
  }

  void _deselectAll() => setState(() => _selectedPackages.clear());

  void _selectEnabled() {
    setState(() {
      _selectedPackages.addAll(
        _ctrl.filteredApps
            .where((a) => _ctrl.blacklistedPackages.contains(a.packageName))
            .map((a) => a.packageName),
      );
    });
  }

  void _clearSelection() => setState(() {
        _selectedPackages.clear();
        _inSelectionMode = false;
      });

  Future<void> _enableSelected() async {
    if (_selectedPackages.isEmpty) return;
    await _ctrl.setBlacklistedBatch(_selectedPackages.toList(), true);
  }

  Future<void> _disableSelected() async {
    if (_selectedPackages.isEmpty) return;
    await _ctrl.setBlacklistedBatch(_selectedPackages.toList(), false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final apps = _ctrl.filteredApps;
    final enabledCount = _ctrl.blacklistedPackages.length;
    final allSelected = apps.isNotEmpty &&
        apps.every((a) => _selectedPackages.contains(a.packageName));

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _clearSelection();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: RefreshIndicator(
          onRefresh: _ctrl.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar.large(
                backgroundColor: cs.surface,
                centerTitle: false,
                automaticallyImplyLeading: !_selectionMode,
                leading: _selectionMode
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clearSelection,
                        tooltip: l10n.cancelSelection,
                      )
                    : null,
                title: _selectionMode
                    ? Text(l10n.selectedAppsCount(_selectedPackages.length))
                    : Text(l10n.navBlacklist),
                actions: _selectionMode
                    ? [
                        IconButton(
                          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                          tooltip: allSelected ? l10n.deselectAll : l10n.selectAll,
                          onPressed: allSelected ? _deselectAll : _selectAll,
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) async {
                            switch (value) {
                              case 'select_enabled':
                                _selectEnabled();
                              case 'enable':
                                await _enableSelected();
                              case 'disable':
                                await _disableSelected();
                            }
                          },
                          itemBuilder: (ctx) {
                            final ml = AppLocalizations.of(ctx)!;
                            return [
                              PopupMenuItem(
                                value: 'select_enabled',
                                child: Text(ml.selectEnabledApps),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'enable',
                                enabled: _selectedPackages.isNotEmpty,
                                child: Text(ml.batchEnable),
                              ),
                              PopupMenuItem(
                                value: 'disable',
                                enabled: _selectedPackages.isNotEmpty,
                                child: Text(ml.batchDisable),
                              ),
                            ];
                          },
                        ),
                      ]
                    : [
                        IconButton(
                          icon: const Icon(Icons.videogame_asset),
                          tooltip: l10n.presetGamesTitle,
                          onPressed: _ctrl.loading ? null : () async {
                            final count = await _ctrl.applyGamePreset();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.presetGamesSuccess(count))),
                              );
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.checklist_outlined),
                          tooltip: l10n.multiSelect,
                          onPressed: _ctrl.loading ? null : _enterSelectionMode,
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) async {
                            switch (value) {
                              case 'toggle_system':
                                _ctrl.setShowSystemApps(!_ctrl.showSystemApps);
                              case 'refresh':
                                await _ctrl.refresh();
                              case 'enable_all':
                                await _ctrl.enableAll();
                              case 'disable_all':
                                await _ctrl.disableAll();
                            }
                          },
                          itemBuilder: (ctx) {
                            final ml = AppLocalizations.of(ctx)!;
                            return [
                              CheckedPopupMenuItem<String>(
                                value: 'toggle_system',
                                checked: _ctrl.showSystemApps,
                                child: Text(ml.showSystemApps),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem<String>(
                                value: 'refresh',
                                child: Text(ml.refreshList),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem<String>(
                                value: 'enable_all',
                                child: Text(ml.enableAll),
                              ),
                              PopupMenuItem<String>(
                                value: 'disable_all',
                                child: Text(ml.disableAll),
                              ),
                            ];
                          },
                        ),
                      ],
              ),

              // 策略配置块
              if (!_selectionMode)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: SliverToBoxAdapter(
                    child: Card(
                      elevation: 0,
                      color: cs.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              l10n.blacklistStrategy,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          RadioListTile<String>(
                            title: Text(l10n.blacklistStrategySkip),
                            value: 'skip',
                            groupValue: _ctrl.blacklistStrategy,
                            onChanged: (v) {
                              if (v != null) _ctrl.setStrategy(v);
                            },
                          ),
                          RadioListTile<String>(
                            title: Text(l10n.blacklistStrategyDisable),
                            value: 'disable',
                            groupValue: _ctrl.blacklistStrategy,
                            onChanged: (v) {
                              if (v != null) _ctrl.setStrategy(v);
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),

              // 说明 + 搜索栏
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _ctrl.showSystemApps
                            ? l10n.blacklistedAppsCountWithSystem(enabledCount)
                            : l10n.blacklistedAppsCount(enabledCount),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      SearchBar(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        hintText: l10n.searchApps,
                        leading: const Icon(Icons.search),
                        trailing: [
                          if (_searchCtrl.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                _ctrl.setSearch('');
                              },
                            ),
                        ],
                        onChanged: _ctrl.setSearch,
                        onSubmitted: (_) => _searchFocus.unfocus(),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 内容区
              if (_ctrl.loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (apps.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      _searchCtrl.text.isEmpty ? l10n.noAppsFound : l10n.noMatchingApps,
                      style: TextStyle(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final app = apps[index];
                        final pkg = app.packageName;
                        return _AppTile(
                          app: app,
                          enabled: _ctrl.blacklistedPackages.contains(pkg),
                          onChanged: _selectionMode
                              ? null
                              : (v) => _ctrl.setBlacklisted(pkg, v ?? false),
                          onTap: _selectionMode
                              ? () => _toggleSelection(pkg)
                              : () {
                                  _ctrl.setBlacklisted(
                                      pkg, !_ctrl.blacklistedPackages.contains(pkg));
                                },
                          onLongPress: _selectionMode
                              ? null
                              : () => _enterSelectionMode(pkg),
                          isSelected: _selectedPackages.contains(pkg),
                          selectionMode: _selectionMode,
                          isFirst: index == 0,
                          isLast: index == apps.length - 1,
                        );
                      },
                      childCount: apps.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.enabled,
    required this.onChanged,
    required this.onTap,
    required this.isFirst,
    required this.isLast,
    this.selectionMode = false,
    this.isSelected = false,
    this.onLongPress,
  });

  final AppInfo app;
  final bool enabled;
  final ValueChanged<bool?>? onChanged;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final radius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(16) : Radius.zero,
      bottom: isLast ? const Radius.circular(16) : Radius.zero,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      app.icon,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.appName,
                          style: Theme.of(context).textTheme.bodyLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          app.packageName,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (selectionMode)
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => onTap(),
                    )
                  else
                    Checkbox(value: enabled, onChanged: onChanged),
                ],
              ),
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            indent: 74,
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
      ],
    );
  }
}
