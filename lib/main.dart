import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HyperIsland',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomePage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '主页',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Home Page
// ─────────────────────────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const platform = MethodChannel('com.example.hyperisland/test');

  double _progress = 0.0;
  bool _isSending = false;
  bool? _moduleActive; // null = loading
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkModuleActive();
  }

  Future<void> _checkModuleActive() async {
    try {
      final bool active = await platform.invokeMethod('isModuleActive');
      setState(() => _moduleActive = active);
    } catch (_) {
      setState(() => _moduleActive = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendTestNotification(String type) async {
    setState(() => _isSending = true);
    try {
      switch (type) {
        case 'progress':
          await platform.invokeMethod('showProgress', {
            'title': '下载测试',
            'fileName': 'test_file.apk',
            'progress': _progress.toInt(),
            'speed': '5.2 MB/s',
            'remainingTime': '00:05',
          });
          break;
        case 'complete':
          await platform.invokeMethod('showComplete', {
            'title': '下载完成',
            'fileName': 'test_file.apk',
          });
          break;
        case 'failed':
          await platform.invokeMethod('showFailed', {
            'title': '下载失败',
            'fileName': 'test_file.apk',
            'error': '网络连接超时',
          });
          break;
        case 'indeterminate':
          await platform.invokeMethod('showIndeterminate', {
            'title': '准备中',
            'content': '正在连接服务器...',
          });
          break;
        case 'custom':
          await platform.invokeMethod('showCustom', {
            'type': 'custom_notification',
            'title': '自定义通知',
            'content': '这是一个自定义的灵动岛通知',
            'icon': 'android.R.drawable.ic_dialog_info',
          });
          break;
      }
    } on PlatformException catch (_) {
      // ignore
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _startProgressDemo() {
    _progress = 0.0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        _progress += 5.0;
        if (_progress >= 100) {
          _progress = 100;
          timer.cancel();
          _sendTestNotification('complete');
        } else {
          _sendTestNotification('progress');
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('HyperIsland'),
            backgroundColor: cs.surface,
            centerTitle: false,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Module Status Card ──
                _ModuleStatusCard(active: _moduleActive),
                const SizedBox(height: 16),

                // ── Test Controls ──
                _SectionLabel('通知测试'),
                const SizedBox(height: 8),
                if (_progress > 0 && _progress < 100)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ProgressCard(progress: _progress),
                  ),
                _TestButtons(
                  isSending: _isSending,
                  onStartDemo: _startProgressDemo,
                  onIndeterminate: () => _sendTestNotification('indeterminate'),
                  onComplete: () => _sendTestNotification('complete'),
                  onFailed: () => _sendTestNotification('failed'),
                  onCustom: () => _sendTestNotification('custom'),
                ),
                const SizedBox(height: 24),

                // ── Notes ──
                _SectionLabel('注意事项'),
                const SizedBox(height: 8),
                const _NotesCard(),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleStatusCard extends StatelessWidget {
  final bool? active; // null = loading
  const _ModuleStatusCard({required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (active == null) {
      return Card(
        elevation: 0,
        color: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 16),
              Text('正在检测模块状态...'),
            ],
          ),
        ),
      );
    }

    final bool isActive = active!;
    final color = isActive ? Colors.green : cs.error;
    final bgColor = isActive
        ? Colors.green.withValues(alpha: 0.12)
        : cs.errorContainer;

    return Card(
      elevation: 0,
      color: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isActive ? Icons.check_circle : Icons.cancel,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '模块状态',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: color.withValues(alpha: 0.8),
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isActive ? '已激活' : '未激活',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (!isActive) ...[
                    const SizedBox(height: 4),
                    Text(
                      '请在 LSPosed 中启用本模块',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: color.withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final double progress;
  const _ProgressCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('下载进度',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant)),
                Text('${progress.toInt()}%',
                    style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestButtons extends StatelessWidget {
  final bool isSending;
  final VoidCallback onStartDemo;
  final VoidCallback onIndeterminate;
  final VoidCallback onComplete;
  final VoidCallback onFailed;
  final VoidCallback onCustom;

  const _TestButtons({
    required this.isSending,
    required this.onStartDemo,
    required this.onIndeterminate,
    required this.onComplete,
    required this.onFailed,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: isSending ? null : onStartDemo,
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('开始进度演示'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _OutlinedActionButton(
                icon: Icons.hourglass_empty,
                label: '不确定进度',
                onPressed: isSending ? null : onIndeterminate,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OutlinedActionButton(
                icon: Icons.check_circle_outline,
                label: '下载完成',
                onPressed: isSending ? null : onComplete,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _OutlinedActionButton(
                icon: Icons.error_outline,
                label: '下载失败',
                onPressed: isSending ? null : onFailed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OutlinedActionButton(
                icon: Icons.notifications_outlined,
                label: '自定义通知',
                onPressed: isSending ? null : onCustom,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OutlinedActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _OutlinedActionButton(
      {required this.icon, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      '此页面仅用于测试是否支持超级岛，并不代表实际效果',
      '请在 HyperCeiler 中关闭系统界面和小米服务框架的焦点通知白名单',
      '实际使用请在 LSPosed 管理器中激活，转到应用商店/下载管理使用',
    ];

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: items
              .map(
                (text) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.arrow_right,
                          size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(text,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
    );
  }
}

// ─────────────────────────────────────────────
// Settings Page
// ─────────────────────────────────────────────

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('设置'),
            backgroundColor: cs.surface,
            centerTitle: false,
          ),
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.construction_outlined,
                      size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text(
                    '暂无设置',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
