import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/telegram_proxy.dart';
import '../providers/telegram_proxy_provider.dart';
import '../widgets/background_gradient.dart';
import '../widgets/error_snackbar.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';
import '../services/wallpaper_service.dart';

class TelegramProxyScreen extends StatefulWidget {
  const TelegramProxyScreen({Key? key}) : super(key: key);

  @override
  State<TelegramProxyScreen> createState() => _TelegramProxyScreenState();
}

class _TelegramProxyScreenState extends State<TelegramProxyScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch proxies when screen is first loaded
    Future.microtask(() {
      Provider.of<TelegramProxyProvider>(context, listen: false).fetchProxies();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BackgroundGradient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(context.tr(TranslationKeys.telegramProxyTitle)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                Provider.of<TelegramProxyProvider>(
                  context,
                  listen: false,
                ).fetchProxies();
              },
              tooltip: context.tr(TranslationKeys.telegramProxyRefresh),
            ),
          ],
        ),
        body: Consumer2<TelegramProxyProvider, WallpaperService>(
          builder: (context, provider, wallpaperService, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.errorMessage.isNotEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 60,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr(TranslationKeys.telegramProxyErrorLoading),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      provider.errorMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        provider.fetchProxies();
                      },
                      child: Text(
                        context.tr(TranslationKeys.telegramProxyTryAgain),
                      ),
                    ),
                  ],
                ),
              );
            }

            if (provider.proxies.isEmpty) {
              return Center(
                child: Text(context.tr(TranslationKeys.telegramProxyNoProxies)),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.proxies.length,
              itemBuilder: (context, index) {
                final proxy = provider.proxies[index];
                return _buildProxyCard(
                  context,
                  proxy,
                  wallpaperService.isGlassBackgroundEnabled,
                  index < 5,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildProxyCard(
    BuildContext context,
    TelegramProxy proxy,
    bool isGlassBackground,
    bool isTopPick,
  ) {
    final measuredPing = proxy.measuredPing ?? proxy.ping;
    final hasValidPing = measuredPing > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: isGlassBackground
          ? AppTheme.cardDark.withOpacity(0.7)
          : AppTheme.cardDark,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with host and port
            Row(
              children: [
                Expanded(
                  child: Text(
                    proxy.host,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryGreen,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primaryBlue, width: 1),
                  ),
                  child: Text(
                    context.tr(
                      TranslationKeys.telegramProxyPort,
                      parameters: {'port': proxy.port.toString()},
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
            if (isTopPick)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt, color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      context.tr(TranslationKeys.telegramProxyFastPick),
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (isTopPick) const SizedBox(height: 12),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.speed,
                    color: hasValidPing ? Colors.greenAccent : Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr(
                      TranslationKeys.telegramProxyPing,
                      parameters: {'ping': hasValidPing ? '$measuredPing' : '--'},
                    ),
                    style: TextStyle(
                      color: hasValidPing
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const SizedBox(height: 12),

            // Action buttons
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.link, size: 20),
                  label: Text(
                    context.tr(TranslationKeys.telegramProxyCopyUrl),
                    style: const TextStyle(fontSize: 14),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: proxy.telegramHttpsUrl),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.tr(
                            TranslationKeys.telegramProxyUrlCopied,
                          ),
                        ),
                        backgroundColor: AppTheme.primaryBlue,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.telegram, size: 20),
                  label: Text(
                    context.tr(TranslationKeys.telegramProxyConnect),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final httpsUrl = Uri.parse(proxy.telegramHttpsUrl);
                    final tgUrl = Uri.parse(proxy.telegramUrl);
                    try {
                      if (await canLaunchUrl(httpsUrl)) {
                        await launchUrl(
                          httpsUrl,
                          mode: LaunchMode.externalApplication,
                        );
                        return;
                      }
                      if (await canLaunchUrl(tgUrl)) {
                        await launchUrl(
                          tgUrl,
                          mode: LaunchMode.externalApplication,
                        );
                        return;
                      }
                      ErrorSnackbar.show(
                        context,
                        context.tr(TranslationKeys.telegramProxyNotInstalled),
                      );
                    } catch (e) {
                      ErrorSnackbar.show(
                        context,
                        context.tr(
                          TranslationKeys.telegramProxyLaunchError,
                          parameters: {'error': e.toString()},
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
