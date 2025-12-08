import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:proxycloud/models/v2ray_config.dart';
import 'package:proxycloud/services/v2ray_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoSelectResult {
  final V2RayConfig? selectedConfig;
  final int? bestPing;
  final String? errorMessage;

  AutoSelectResult({this.selectedConfig, this.bestPing, this.errorMessage});
}

class AutoSelectCancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  void cancel() => _isCancelled = true;
}

class AutoSelectUtil {
  static const String _pingBatchSizeKey = 'ping_batch_size';
  static const String _savedPingsKey = 'saved_pings';
  static const String _lastBestKey = 'last_best_server';
  static const Duration _pingCacheDuration = Duration(hours: 24);

  static Future<int> getPingBatchSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int batchSize = prefs.getInt(_pingBatchSizeKey) ?? 10;
      if (batchSize < 1) return 1;
      if (batchSize > 20) return 20;
      return batchSize;
    } catch (_) {
      return 10;
    }
  }

  static Future<AutoSelectResult> runAutoSelect(
    List<V2RayConfig> configs,
    V2RayService v2rayService, {
    void Function(String)? onStatusUpdate,
    AutoSelectCancellationToken? cancellationToken,
    bool fastMode = false,
  }) async {
    try {
      final cachedPings = await _loadCachedPings();
      final Map<String, _CachedPing> workingCache = Map.of(cachedPings);

      // reuse last best if fresh
      final _CachedBest? lastBest = await _loadLastBest();
      if (lastBest != null) {
        V2RayConfig? cachedBestConfig;
        try {
          cachedBestConfig =
              configs.firstWhere((c) => c.id == lastBest.configId);
        } catch (_) {
          cachedBestConfig = null;
        }
        if (cachedBestConfig != null && lastBest.isFresh) {
          onStatusUpdate?.call(
            'Using previous best ${cachedBestConfig.remark} (${lastBest.ping}ms)',
          );
          return AutoSelectResult(
            selectedConfig: cachedBestConfig,
            bestPing: lastBest.ping,
          );
        }
      }

      V2RayConfig? selectedConfig;
      int? bestPing;

      // use fresh cached pings
      for (final config in configs) {
        final cached = workingCache[config.id];
        if (cached != null && cached.isFresh && cached.ping > 0) {
          if (bestPing == null || cached.ping < bestPing) {
            selectedConfig = config;
            bestPing = cached.ping;
          }
        }
      }

      if (!fastMode && selectedConfig != null && bestPing != null && bestPing < 120) {
        onStatusUpdate?.call(
          'Using cached server ${selectedConfig.remark} (${bestPing}ms)',
        );
        return AutoSelectResult(
          selectedConfig: selectedConfig,
          bestPing: bestPing,
        );
      }

      // need fresh tests
      final List<V2RayConfig> pendingConfigs = configs.where((config) {
        final cached = workingCache[config.id];
        if (cached == null) return true;
        if (!cached.isFresh) return true;
        if (cached.ping <= 0) return true;
        return false;
      }).toList();

      final int fastCap = fastMode ? 5 : pendingConfigs.length;
      final List<V2RayConfig> cappedPending =
          pendingConfigs.take(fastCap).toList();

      final int batchSize = fastMode ? 3 : await getPingBatchSize();
      debugPrint('Using auto-select batch size: $batchSize');

      onStatusUpdate?.call(
        fastMode
            ? 'Quick test ${cappedPending.length} servers...'
            : 'Testing ${configs.length} servers in batches of $batchSize...',
      );

      bestPing ??= 10000;

      // prioritize by cached ping
      pendingConfigs.sort((a, b) {
        final cachedA = workingCache[a.id];
        final cachedB = workingCache[b.id];
        final pingA = cachedA?.ping ?? 100000;
        final pingB = cachedB?.ping ?? 100000;
        return pingA.compareTo(pingB);
      });

      int testedOffset = 0;
      while (testedOffset < cappedPending.length) {
        if (cancellationToken?.isCancelled == true) {
          return AutoSelectResult(errorMessage: 'Auto-select cancelled');
        }

        final int serversToTest =
            min(batchSize, cappedPending.length - testedOffset);
        final int actualServersToTest = max(1, serversToTest);

        final List<V2RayConfig> batchConfigs = cappedPending.sublist(
          testedOffset,
          min(testedOffset + actualServersToTest, cappedPending.length),
        );

        onStatusUpdate?.call(
          'Testing batch ${testedOffset ~/ batchSize + 1}: ${batchConfigs.length} servers...',
        );

        final futures = <Future<MapEntry<V2RayConfig, int?>>>[];
        for (final config in batchConfigs) {
          if (cancellationToken?.isCancelled == true) {
            return AutoSelectResult(errorMessage: 'Auto-select cancelled');
          }

          futures.add(
            v2rayService
                .getServerDelay(config, cancellationToken: cancellationToken)
                .then((delay) => MapEntry(config, delay)),
          );
        }

        final List<MapEntry<V2RayConfig, int?>> results = await Future.wait(
          futures,
        ).timeout(
          fastMode ? const Duration(seconds: 3) : const Duration(seconds: 6),
          onTimeout: () {
            debugPrint('Auto-select batch timeout');
            return <MapEntry<V2RayConfig, int?>>[];
          },
        );

        for (final result in results) {
          if (cancellationToken?.isCancelled == true) {
            return AutoSelectResult(errorMessage: 'Auto-select cancelled');
          }

          final config = result.key;
          final delay = result.value;

          if (delay != null && delay >= 0) {
            onStatusUpdate?.call('✓ ${config.remark}: ${delay}ms');
            workingCache[config.id] = _CachedPing(ping: delay);

            if (delay < (bestPing ?? 10000)) {
              selectedConfig = config;
              bestPing = delay;

              if (delay < 100) {
                onStatusUpdate?.call(
                  'Found very fast server (${delay}ms), stopping early...',
                );
                break;
              }
            }
          } else {
            onStatusUpdate?.call('✗ ${config.remark}: Failed');
            workingCache[config.id] = _CachedPing(ping: -1);
          }
        }

        if (selectedConfig != null &&
            (bestPing ?? 10000) < (fastMode ? 400 : 200)) {
          onStatusUpdate?.call(
            'Found good server (${bestPing}ms), stopping batch testing...',
          );
          break;
        }

        testedOffset += actualServersToTest;
      }

      await _saveCachedPings(workingCache);
      if (selectedConfig != null && bestPing != null) {
        await _saveLastBest(selectedConfig.id, bestPing);
      }

      if (selectedConfig != null && bestPing != null) {
        return AutoSelectResult(
          selectedConfig: selectedConfig,
          bestPing: bestPing,
        );
      } else {
        return AutoSelectResult(errorMessage: 'No suitable server found');
      }
    } catch (e) {
      return AutoSelectResult(errorMessage: 'Error during auto-select: $e');
    }
  }

  static Future<Map<String, _CachedPing>> _loadCachedPings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_savedPingsKey);
      if (jsonString == null || jsonString.isEmpty) {
        return {};
      }
      final Map<String, dynamic> decoded = jsonDecode(jsonString);
      final Map<String, _CachedPing> cache = {};
      decoded.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final ping = value['ping'];
          final timestamp = value['timestamp'];
          if (ping is int && timestamp is int) {
            final cached = _CachedPing(
              ping: ping,
              timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
            );
            if (cached.isFresh) {
              cache[key] = cached;
            }
          }
        }
      });
      return cache;
    } catch (e) {
      debugPrint('Error loading cached pings: $e');
      return {};
    }
  }

  static Future<void> _saveCachedPings(
    Map<String, _CachedPing> cache,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> data = {};
      cache.forEach((key, value) {
        if (value.isFresh) {
          data[key] = value.toJson();
        }
      });
      await prefs.setString(_savedPingsKey, jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving cached pings: $e');
    }
  }

  static Future<_CachedBest?> _loadLastBest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_lastBestKey);
      if (jsonString == null || jsonString.isEmpty) return null;
      final Map<String, dynamic> decoded = jsonDecode(jsonString);
      final configId = decoded['configId'] as String?;
      final ping = decoded['ping'] as int?;
      final timestampMs = decoded['timestamp'] as int?;
      if (configId == null || ping == null || timestampMs == null) return null;
      return _CachedBest(
        configId: configId,
        ping: ping,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      );
    } catch (e) {
      debugPrint('Error loading last best server: $e');
      return null;
    }
  }

  static Future<void> _saveLastBest(String configId, int ping) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'configId': configId,
        'ping': ping,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_lastBestKey, jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving last best server: $e');
    }
  }
}

class _CachedPing {
  final int ping;
  final DateTime timestamp;

  _CachedPing({required this.ping, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  bool get isFresh =>
      DateTime.now().difference(timestamp) < AutoSelectUtil._pingCacheDuration;

  Map<String, dynamic> toJson() => {
        'ping': ping,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };
}

class _CachedBest {
  final String configId;
  final int ping;
  final DateTime timestamp;

  _CachedBest({
    required this.configId,
    required this.ping,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isFresh =>
      DateTime.now().difference(timestamp) < AutoSelectUtil._pingCacheDuration;
}
