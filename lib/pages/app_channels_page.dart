import 'package:flutter/material.dart';
import '../controllers/whitelist_controller.dart';

class AppChannelsPage extends StatefulWidget {
  final AppInfo app;
  final WhitelistController controller;

  const AppChannelsPage({
    super.key,
    required this.app,
    required this.controller,
  });

  @override
  State<AppChannelsPage> createState() => _AppChannelsPageState();
}

class _AppChannelsPageState extends State<AppChannelsPage> {
  List<ChannelInfo>? _channels;
  Set<String> _enabledChannels = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final channels =
        await widget.controller.getChannels(widget.app.packageName);
    final enabled =
        await widget.controller.getEnabledChannels(widget.app.packageName);
    if (mounted) {
      setState(() {
        _channels = channels;
        _enabledChannels = enabled;
        _loading = false;
      });
    }
  }

  bool _isEnabled(String channelId) =>
      _enabledChannels.isEmpty || _enabledChannels.contains(channelId);

  Future<void> _toggle(String channelId, bool value) async {
    final all = _channels ?? [];
    Set<String> newSet;

    if (_enabledChannels.isEmpty) {
      // 当前"全部生效"，关闭某个渠道 → 保存其余所有渠道
      if (!value) {
        newSet =
            all.map((c) => c.id).where((id) => id != channelId).toSet();
      } else {
        return;
      }
    } else {
      newSet = Set.from(_enabledChannels);
      if (value) {
        newSet.add(channelId);
      } else {
        newSet.remove(channelId);
      }
      // 全部重新勾选 → 重置为空（全部生效）
      if (all.isNotEmpty && newSet.length == all.length) newSet = {};
    }

    setState(() => _enabledChannels = newSet);
    await widget.controller.setEnabledChannels(
        widget.app.packageName, newSet);
  }

  String _importanceLabel(int importance) => switch (importance) {
        0 => '无',
        1 => '极低',
        2 => '低',
        3 => '默认',
        4 || 5 => '高',
        _ => '未知',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final channels = _channels ?? [];
    final allEnabled = _enabledChannels.isEmpty;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            backgroundColor: cs.surface,
            centerTitle: false,
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    widget.app.icon,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.app.appName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (channels.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_off_outlined,
                        size: 48, color: cs.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text('未找到通知渠道',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(
                      '该应用尚未创建通知渠道，或无法读取',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  allEnabled
                      ? '对全部 ${channels.length} 个渠道生效'
                      : '已选 ${_enabledChannels.length} / ${channels.length} 个渠道',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final ch = channels[index];
                    final isFirst = index == 0;
                    final isLast = index == channels.length - 1;
                    final radius = BorderRadius.vertical(
                      top: isFirst ? const Radius.circular(16) : Radius.zero,
                      bottom:
                          isLast ? const Radius.circular(16) : Radius.zero,
                    );
                    final enabled = _isEnabled(ch.id);

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: cs.surfaceContainerHighest,
                          borderRadius: radius,
                          child: InkWell(
                            borderRadius: radius,
                            onTap: () => _toggle(ch.id, !enabled),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(ch.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge),
                                        if (ch.description.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            ch.description,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color:
                                                        cs.onSurfaceVariant),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        const SizedBox(height: 2),
                                        Text(
                                          '重要性：${_importanceLabel(ch.importance)}  ·  ${ch.id}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  color: cs.onSurfaceVariant
                                                      .withValues(alpha: 0.7)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                      value: enabled,
                                      onChanged: (v) => _toggle(ch.id, v)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (!isLast)
                          Divider(
                            height: 1,
                            thickness: 1,
                            indent: 16,
                            color:
                                cs.outlineVariant.withValues(alpha: 0.4),
                          ),
                      ],
                    );
                  },
                  childCount: channels.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
