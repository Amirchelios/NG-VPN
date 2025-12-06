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

// Cancellation token class for auto-select operations
class AutoSelectCancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

class AutoSelectUtil {
  static const String _pingBatchSizeKey = 'ping_batch_size';
  static const String _savedPingsKey = 'saved_pings';
  static const Duration _pingCacheDuration = Duration(minutes: 10);

  /// Get ping batch size from shared preferences (increased default for faster testing)
  static Future<int> getPingBatchSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int batchSize =
          prefs.getInt(_pingBatchSizeKey) ?? 10; // Increased default to 10
      // Ensure the value is between 1 and 20 for faster testing
      if (batchSize < 1) return 1;
      if (batchSize > 20) return 20; // Increased max to 20
      return batchSize;
    } catch (e) {
      return 10; // Increased default value
    }
  }

  /// Run auto-select algorithm to find the best server with optimized settings
  static Future<AutoSelectResult> runAutoSelect(
    List<V2RayConfig> configs,
    V2RayService v2rayService, {
    void Function(String)? onStatusUpdate,
    AutoSelectCancellationToken? cancellationToken,
  }) async {
    try {
      final cachedPings = await _loadCachedPings();
      final Map<String, _CachedPing> workingCache = Map.of(cachedPings);

      V2RayConfig? selectedConfig;
      int? bestPing;

      // Try to reuse fresh cached ping results first
      for (final config in configs) {
        final cached = workingCache[config.id];
        if (cached != null && cached.isFresh && cached.ping > 0) {
          if (bestPing == null || cached.ping < bestPing) {
            selectedConfig = config;
            bestPing = cached.ping;
          }
        }
      }

      if (selectedConfig != null && bestPing != null && bestPing < 120) {
        onStatusUpdate?.call(
          'Using cached server ${selectedConfig.remark} (${bestPing}ms)',
        );
        return AutoSelectResult(
          selectedConfig: selectedConfig,
          bestPing: bestPing,
        );
      }

      // Get batch size (increased for faster testing)
      final int batchSize = await getPingBatchSize();
      debugPrint('Using auto-select batch size: $batchSize');

      // Notify about starting
      onStatusUpdate?.call(
        'Testing ${configs.length} servers in batches of $batchSize...',
      );

      bestPing ??= 10000; // Start with a high value

      // Determine which configs actually need fresh ping tests
      final List<V2RayConfig> pendingConfigs = configs.where((config) {
        final cached = workingCache[config.id];
        if (cached == null) return true;
        if (!cached.isFresh) return true;
        if (cached.ping <= 0) return true;
        return false;
      }).toList();

      // Prioritize ones with historically better ping
      pendingConfigs.sort((a, b) {
        final cachedA = workingCache[a.id];
        final cachedB = workingCache[b.id];
        final pingA = cachedA?.ping ?? 100000;
        final pingB = cachedB?.ping ?? 100000;
        return pingA.compareTo(pingB);
      });

      int testedOffset = 0;
      while (testedOffset < pendingConfigs.length) {
        if (cancellationToken?.isCancelled == true) {
          return AutoSelectResult(errorMessage: 'Auto-select cancelled');
        }

        final int serversToTest =
            min(batchSize, pendingConfigs.length - testedOffset);
        final int actualServersToTest = max(1, serversToTest);

        final List<V2RayConfig> batchConfigs = pendingConfigs.sublist(
          testedOffset,
          min(testedOffset + actualServersToTest, pendingConfigs.length),
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
          const Duration(seconds: 6),
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
            onStatusUpdate?.call('⚡ ${config.remark}: ${delay}ms');
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
            onStatusUpdate?.call('✖ ${config.remark}: Failed');
            workingCache[config.id] = _CachedPing(ping: -1);
          }
        }

        if (selectedConfig != null && (bestPing ?? 10000) < 200) {
          onStatusUpdate?.call(
            'Found good server (${bestPing}ms), stopping batch testing...',
          );
          break;
        }

        testedOffset += actualServersToTest;
      }

      await _saveCachedPings(workingCache);

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
