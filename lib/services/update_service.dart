import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:proxycloud/models/app_update.dart';
import '../utils/app_localizations.dart';

class UpdateService {
  UpdateService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 10),
              ),
            );

  static const String updateUrl =
      'https://raw.githubusercontent.com/code3-dev/ProxyCloud-GUI/refs/heads/main/config/mobile.json';
  static const Duration _cacheDuration = Duration(hours: 4);

  final Dio _dio;
  CancelToken? _activeToken;
  AppUpdate? _cachedUpdate;
  DateTime? _lastFetchedAt;

  /// Check for updates with short timeouts, caching and cancellation support.
  Future<AppUpdate?> checkForUpdates({bool forceRefresh = false}) async {
    final bool isCacheValid = _lastFetchedAt != null &&
        DateTime.now().difference(_lastFetchedAt!) < _cacheDuration;
    if (!forceRefresh && isCacheValid) {
      return _cachedUpdate;
    }

    _activeToken?.cancel('Superseded by a newer update request');
    final cancelToken = CancelToken();
    _activeToken = cancelToken;

    try {
      final response = await _dio.get<String>(
        updateUrl,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.plain,
          headers: const {'Cache-Control': 'no-cache'},
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final AppUpdate? update = AppUpdate.fromJsonString(response.data!);
        _lastFetchedAt = DateTime.now();
        if (update != null && update.hasUpdate()) {
          _cachedUpdate = update;
          return update;
        }
        _cachedUpdate = null;
      }
      return null;
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        debugPrint('Error checking for updates: ${e.message}');
      }
      return null;
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      return null;
    } finally {
      if (_activeToken == cancelToken) {
        _activeToken = null;
      }
    }
  }

  // Show update dialog
  void showUpdateDialog(BuildContext context, AppUpdate update) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(context.tr(TranslationKeys.updateServiceUpdateAvailable)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                TranslationKeys.updateServiceNewVersion,
                parameters: {'version': update.version},
              ),
            ),
            const SizedBox(height: 8),
            Text(update.messText),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr(TranslationKeys.updateServiceLater)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _launchUrl(update.url.trim());
            },
            child: Text(context.tr(TranslationKeys.updateServiceDownload)),
          ),
        ],
      ),
    );
  }

  // Launch URL
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
      // If context is available, we could show a localized error message
      // For now, keeping the debug print as it's mainly for development
    }
  }

  void cancelPendingRequest() {
    _activeToken?.cancel('Disposed');
    _activeToken = null;
  }

  void dispose() => cancelPendingRequest();
}
