import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/telegram_proxy.dart';

class TelegramProxyService {
  static const String proxyUrl =
      'https://raw.githubusercontent.com/hookzof/socks5_list/master/tg/mtproto.json';
  static const int _maxMeasuredTargets = 30;

  // Singleton pattern
  static final TelegramProxyService _instance =
      TelegramProxyService._internal();
  factory TelegramProxyService() => _instance;

  TelegramProxyService._internal();

  Future<List<TelegramProxy>> fetchProxies() async {
    try {
      final response = await http.get(Uri.parse(proxyUrl)).timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              throw Exception(
                'Network timeout: Check your internet connection',
              );
            },
          );

      if (response.statusCode == 200) {
        final proxies = parseTelegramProxies(response.body);
        return _measureAndSortProxies(proxies);
      } else {
        throw Exception('Failed to load proxies: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching proxies: $e');
    }
  }

  Future<List<TelegramProxy>> _measureAndSortProxies(
    List<TelegramProxy> proxies,
  ) async {
    final targets = proxies.take(_maxMeasuredTargets).toList();
    final futures = targets.map(
      (proxy) async {
        final ping = await _measurePing(proxy);
        return proxy.copyWith(measuredPing: ping);
      },
    );
    final measuredTargets = await Future.wait(futures);
    final combined = [
      ...measuredTargets,
      ...proxies.skip(_maxMeasuredTargets),
    ];
    combined.sort((a, b) {
      final pingA = a.measuredPing ?? a.ping;
      final pingB = b.measuredPing ?? b.ping;
      return _normalizePing(pingA).compareTo(_normalizePing(pingB));
    });
    return combined;
  }

  Future<int> _measurePing(TelegramProxy proxy) async {
    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(
        proxy.host,
        proxy.port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  int _normalizePing(int ping) {
    if (ping <= 0) {
      return 1 << 30;
    }
    return ping;
  }
}
