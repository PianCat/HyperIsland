import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('io.github.hyperisland/test');
const kPrefAppBlacklist = 'pref_app_blacklist';
const kPrefAppBlacklistStrategy = 'pref_app_blacklist_strategy';

class AppInfo {
  final String packageName;
  final String appName;
  final Uint8List icon;
  final bool isSystem;

  const AppInfo({
    required this.packageName,
    required this.appName,
    required this.icon,
    this.isSystem = false,
  });
}

class BlacklistController extends ChangeNotifier {
  List<AppInfo> _allApps = [];
  List<AppInfo> _sortedApps = [];
  Set<String> blacklistedPackages = {};
  String blacklistStrategy = 'skip'; // 'skip' 或 'disable'
  bool loading = true;
  String _searchQuery = '';
  bool showSystemApps = false;

  static const _gamePresets = {
    'com.tencent.tmgp.sgame',       // 王者荣耀
    'com.tencent.tmgp.pubgmhd',     // 和平精英
    'com.tencent.lolm',             // 英雄联盟手游
    'com.miHoYo.Yuanshen',          // 原神
    'com.miHoYo.ys.bilibili',       // 原神bilibili版
    'com.miHoYo.hkrpg',             // 崩坏：星穹铁道
    'com.tencent.tmgp.cf',          // 穿越火线
    'com.tencent.jkchess',          // 金铲铲之战
    'com.tencent.tmgp.speedmobile', //QQ飞车
  };

  BlacklistController() {
    _load();
  }

  void _resort() {
    _sortedApps = List<AppInfo>.from(_allApps)
      ..sort((a, b) {
        final aOn = blacklistedPackages.contains(a.packageName);
        final bOn = blacklistedPackages.contains(b.packageName);
        if (aOn != bOn) return aOn ? -1 : 1;
        return a.appName.compareTo(b.appName);
      });
  }

  List<AppInfo> get filteredApps {
    final q = _searchQuery.toLowerCase();
    Iterable<AppInfo> source = showSystemApps
        ? _sortedApps
        : _sortedApps.where((a) => !a.isSystem || blacklistedPackages.contains(a.packageName));
    if (q.isNotEmpty) {
      source = source.where((a) =>
          a.appName.toLowerCase().contains(q) ||
          a.packageName.toLowerCase().contains(q));
    }
    return source is List<AppInfo> ? source : source.toList();
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    loading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final csv = prefs.getString(kPrefAppBlacklist) ?? '';
      blacklistedPackages =
          csv.isEmpty ? {} : csv.split(',').where((s) => s.isNotEmpty).toSet();
      
      blacklistStrategy = prefs.getString(kPrefAppBlacklistStrategy) ?? 'skip';

      final rawList =
          await _channel.invokeMethod<List<dynamic>>(
              'getInstalledApps', {'includeSystem': true}) ?? [];
      const _excludedPackages = {
        'com.android.providers.downloads',
        'com.xiaomi.android.app.downloadmanager',
        'com.android.systemui',
      };
      _allApps = rawList
          .map((raw) {
            final map = Map<String, dynamic>.from(raw as Map);
            return AppInfo(
              packageName: map['packageName'] as String,
              appName: map['appName'] as String,
              icon: Uint8List.fromList((map['icon'] as List).cast<int>()),
              isSystem: map['isSystem'] as bool? ?? false,
            );
          })
          .where((a) => !_excludedPackages.contains(a.packageName))
          .toList();
      _resort();
    } catch (e) {
      debugPrint('BlacklistController._load error: $e');
    }

    loading = false;
    notifyListeners();
  }

  Future<void> setStrategy(String strategy) async {
    blacklistStrategy = strategy;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefAppBlacklistStrategy, strategy);
    notifyListeners();
  }

  Future<void> setBlacklisted(String packageName, bool enabled) async {
    if (enabled) {
      blacklistedPackages.add(packageName);
    } else {
      blacklistedPackages.remove(packageName);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefAppBlacklist, blacklistedPackages.join(','));
    notifyListeners();
  }

  void setSearch(String query) {
    _searchQuery = query;
    _resort();
    notifyListeners();
  }

  void setShowSystemApps(bool value) {
    showSystemApps = value;
    _resort();
    notifyListeners();
  }

  Future<void> enableAll() async {
    for (final a in filteredApps) blacklistedPackages.add(a.packageName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefAppBlacklist, blacklistedPackages.join(','));
    notifyListeners();
  }

  Future<void> disableAll() async {
    for (final a in filteredApps) blacklistedPackages.remove(a.packageName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefAppBlacklist, blacklistedPackages.join(','));
    notifyListeners();
  }

  Future<int> applyGamePreset() async {
    int addedCount = 0;
    for (final app in _allApps) {
      if (_gamePresets.contains(app.packageName) && !blacklistedPackages.contains(app.packageName)) {
        blacklistedPackages.add(app.packageName);
        addedCount++;
      }
    }
    if (addedCount > 0) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefAppBlacklist, blacklistedPackages.join(','));
      _resort();
      notifyListeners();
    }
    return addedCount;
  }

  Future<void> setBlacklistedBatch(List<String> packages, bool enabled) async {
    for (final pkg in packages) {
      if (enabled) {
        blacklistedPackages.add(pkg);
      } else {
        blacklistedPackages.remove(pkg);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefAppBlacklist, blacklistedPackages.join(','));
    notifyListeners();
  }
}
