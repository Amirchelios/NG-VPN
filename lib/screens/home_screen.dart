import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/v2ray_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/language_provider.dart';
import '../utils/app_localizations.dart';
import '../widgets/connection_button.dart';
import '../widgets/server_selector.dart';
import '../widgets/background_gradient.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import '../services/v2ray_service.dart';
import '../services/wallpaper_service.dart';
import '../utils/auto_select_util.dart';
import 'profile_activation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isAutoSelecting = false;
  _ConnectMode _connectMode = _ConnectMode.none;

  @override
  void initState() {
    super.initState();
    _urlController.text = '';

    // Listen for connection state changes
    final v2rayProvider = Provider.of<V2RayProvider>(context, listen: false);
    v2rayProvider.addListener(_onProviderChanged);
  }

  void _onProviderChanged() {
    final provider = Provider.of<V2RayProvider>(context, listen: false);
    // Sync UI focus with current connection state
    if (provider.isConnecting) return;
    if (provider.activeConfig?.id == V2RayProvider.smartModeConfigId) {
      setState(() => _connectMode = _ConnectMode.smart);
    } else if (provider.activeConfig != null) {
      setState(() => _connectMode = _ConnectMode.simple);
    } else {
      setState(() => _connectMode = _ConnectMode.none);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // Share V2Ray link to clipboard
  void _shareV2RayLink(BuildContext context) async {
    try {
      final provider = Provider.of<V2RayProvider>(context, listen: false);
      final activeConfig = provider.activeConfig;

      if (activeConfig != null && activeConfig.fullConfig.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: activeConfig.fullConfig));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  color: AppTheme.connectedGreen,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('home.v2ray_link_copied'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.cardDark,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('home.no_v2ray_config'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${context.tr('home.error_copying')}: ${e.toString()}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  // Check config method to test connectivity to Google
  Future<void> _checkConfig(V2RayProvider provider) async {
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Text(context.tr('home.checking_config')),
          ],
        ),
        backgroundColor: Colors.white,
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final startTime = DateTime.now();
      final response = await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              throw Exception(
                'Network timeout: Check your internet connection',
              );
            },
          );
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      // Close the loading snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (response.statusCode == 200) {
        // Show success message with ping time
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${context.tr('home.config_ok')} (${duration.inMilliseconds}ms)',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.connectedGreen,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${context.tr('home.config_not_working')} (${response.statusCode})',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Close the loading snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.red, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${context.tr('home.config_not_working')}: ${e.toString()}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _autoSelectAndConnect(V2RayProvider provider) async {
    if (_isAutoSelecting) return;

    setState(() {
      _isAutoSelecting = true;
    });

    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.secondaryDark,
          title: Text(context.tr('server_selection.auto_select')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
              ),
              const SizedBox(height: 16),
              Text(context.tr('server_selection.testing_servers')),
              const SizedBox(height: 8),
              StreamBuilder<String>(
                stream: Stream.periodic(const Duration(milliseconds: 500), (count) {
                  final messages = [
                    'Testing servers for fastest connection...',
                    'Analyzing server response times...',
                    'Finding optimal server...',
                    'Almost done...',
                  ];
                  return messages[count % messages.length];
                }),
                builder: (context, snapshot) {
                  return Text(
                    snapshot.data ?? 'Testing servers for fastest connection...',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  );
                },
              ),
            ],
          ),
        ),
      );

      // Get all configs
      final configs = provider.configs;
      if (configs.isEmpty) {
        if (mounted) {
          Navigator.of(context).pop(); // Close dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('server_selector.no_servers')),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Run auto-select algorithm
      final result = await AutoSelectUtil.runAutoSelect(
        configs,
        provider.v2rayService,
        onStatusUpdate: (message) {
          // We could update UI here if needed, but for now we'll just debug print
          debugPrint('Auto-select status: $message');
        },
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
      }

      if (result.selectedConfig != null && result.bestPing != null) {
        // Connect to the best server
        await provider.selectConfig(result.selectedConfig!);
        await provider.connectToServer(
          result.selectedConfig!,
          provider.isProxyMode,
        );
        final success = provider.errorMessage.isEmpty; // Check if connection was successful

        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${context.tr('server_selection.lowest_ping', parameters: {
                    'server': result.selectedConfig!.remark,
                    'ping': result.bestPing.toString(),
                  })} - Connected!',
                ),
                backgroundColor: AppTheme.connectedGreen,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.tr('server_selection.connect_failed', parameters: {
                    'server': result.selectedConfig!.remark,
                    'error': 'Connection failed',
                  }),
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ??
                    context.tr('server_selection.no_suitable_server'),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr('server_selection.error_updating')}: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAutoSelecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<ProfileProvider>();
    final hasProfile = profileProvider.hasValidProfile;
    final isInitializing = context.select<V2RayProvider, bool>(
      (provider) => provider.isInitializing,
    );
    final hasActiveConfig = context.select<V2RayProvider, bool>(
      (provider) => provider.activeConfig != null,
    );
    final v2rayProvider = context.read<V2RayProvider>();

    return Consumer<LanguageProvider>(
      builder: (context, languageProvider, child) {
        return Directionality(
          textDirection: languageProvider.textDirection,
          child: BackgroundGradient(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: Text(context.tr(TranslationKeys.homeTitle)),
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      final profileProvider =
                          Provider.of<ProfileProvider>(context, listen: false);
                      await profileProvider.refreshProfile();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.tr('home.updated'),
                          ),
                        ),
                      );
                    },
                    tooltip: context.tr(TranslationKeys.homeRefresh),
                  ),
                ],
              ),
              body: !hasProfile
                  ? _buildProfileRequiredView(context)
                  : Column(
                      children: [
                        Expanded(
                          child: isInitializing
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          AppTheme.primaryBlue,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        context.tr('common.loading'),
                                        style: const TextStyle(
                                          color: AppTheme.textGrey,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 20),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Consumer<V2RayProvider>(
                                          builder: (context, provider, _) =>
                                              _buildProfileCard(
                                            context,
                                            provider,
                                            profileProvider,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        FractionallySizedBox(
                                          widthFactor: 0.94,
                                          child: hasActiveConfig
                                              ? _buildConnectionStats(
                                                  v2rayProvider,
                                                )
                                              : const ServerSelector(),
                                        ),
                                        const SizedBox(height: 24),
                                        FractionallySizedBox(
                                          widthFactor: 0.85,
                                          child: _buildAnimatedConnectArea(),
                                        ),
                                        const SizedBox(height: 32),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileCard(
    BuildContext context,
    V2RayProvider provider,
    ProfileProvider profileProvider,
  ) {
    final profile = profileProvider.profile;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'پروفایل شما',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppTheme.primaryBlue.withOpacity(0.15),
                child: const Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.name ?? 'نام ثبت نشده',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'شماره: ${profile?.phone ?? '-'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textGrey,
                      ),
                    ),
                  ],
                ),
              ),
              if (profile != null)
                Text(
                  profile.expiryJalali,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildProfileInfoChip(
                icon: Icons.layers_outlined,
                label: 'وضعیت',
                value: profileProvider.hasValidProfile ? 'فعال' : 'غیرفعال',
              ),
            ],
          ),
          if (profile != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'روزهای باقی‌مانده',
                  style: TextStyle(
                    color: AppTheme.textGrey,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '${profile.remainingDays} روز',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: profile.remainingProgress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.primaryBlue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileInfoChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryBlue),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textGrey,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStats(V2RayProvider provider) {
    // Get the V2RayService instance
    final v2rayService = provider.v2rayService;

    // Use StreamBuilder to update the UI when statistics change
    return StreamBuilder(
      // Create a periodic stream to update the UI every 1 second for traffic and every 5 seconds for IP
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        // Refresh IP info every 5 seconds (when snapshot.data is multiple of 5)
        if (snapshot.hasData && snapshot.data! % 5 == 0) {
          if (v2rayService.activeConfig != null) {
            // Fetch IP info without showing loading indicator
            v2rayService.fetchIpInfo().catchError((error) {
              // Handle error silently
              debugPrint('Error refreshing IP info: $error');
            });
          }
        }

        final ipInfo = v2rayService.ipInfo;
        final upload = v2rayService.getFormattedUpload();
        final download = v2rayService.getFormattedDownload();
        final totalTraffic = v2rayService.getFormattedTotalTraffic();

        return Selector<WallpaperService, bool>(
          selector: (_, service) => service.isGlassBackgroundEnabled,
          builder: (context, isGlassBackground, __) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isGlassBackground
                    ? AppTheme.cardDark.withOpacity(0.7)
                    : AppTheme.cardDark,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        context.tr('home.connection_statistics'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          foregroundColor: AppTheme.primaryBlue,
                          backgroundColor: Colors.white.withOpacity(0.05),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => _checkConfig(provider),
                        icon: const Icon(Icons.shield_outlined, size: 16),
                        label: Text(
                          context.tr(TranslationKeys.homeCheckConfig),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMiniMetric(
                          icon: Icons.timer_outlined,
                          label: context.tr(TranslationKeys.homeConnectionTime),
                          primaryValue:
                              v2rayService.getFormattedConnectedTime(),
                          status: provider.isConnecting
                              ? context.tr(TranslationKeys.homeConnecting)
                              : context.tr(TranslationKeys.homeConnected),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMiniMetric(
                          icon: Icons.data_usage,
                          label: context.tr(TranslationKeys.homeTrafficUsage),
                          primaryValue: totalTraffic,
                          status:
                              '${context.tr(TranslationKeys.homeUpload)}: $upload',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMiniMetric(
                          icon: Icons.public,
                          label: context.tr(TranslationKeys.homeIpAddress),
                          primaryValue: ipInfo?.ip ?? '...',
                          status:
                              '${ipInfo?.country ?? '...'} • ${ipInfo?.city ?? '...'}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickMetric({
    required IconData icon,
    required String label,
    required String primaryValue,
    String? secondaryValue,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.primaryBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textGrey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              primaryValue,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (secondaryValue != null) ...[
              const SizedBox(height: 4),
              Text(
                secondaryValue,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textGrey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMetric({
    required IconData icon,
    required String label,
    required String primaryValue,
    required String status,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppTheme.primaryBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textGrey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              primaryValue,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              status,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileRequiredView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 80, color: Colors.white70),
            const SizedBox(height: 16),
            const Text(
              'برای استفاده از برنامه لازم است پروفایل اختصاصی خود را فعال کنید.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileActivationScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'فعال‌سازی پروفایل',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedConnectArea() {
    final provider = context.watch<V2RayProvider>();
    final isSmartActive =
        provider.activeConfig?.id == V2RayProvider.smartModeConfigId;
    final isConnecting = provider.isConnecting;
    final isAnyConnected = provider.activeConfig != null || isConnecting;

    // Keep UI focus consistent with actual state
    final focusedMode = isSmartActive
        ? _ConnectMode.smart
        : isAnyConnected
            ? _ConnectMode.simple
            : _connectMode;

    final bool showDual = focusedMode == _ConnectMode.none;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInBack,
      child: showDual
          ? Wrap(
              key: const ValueKey('dual'),
              alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 10,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConnectionButton(
                      onFocused: () {
                        setState(() => _connectMode = _ConnectMode.simple);
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'روش ساده',
                      style: TextStyle(
                        color: AppTheme.textGrey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SmartMethodButton(
                      onFocused: () {
                        setState(() => _connectMode = _ConnectMode.smart);
                      },
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(
                      width: 170,
                      child: Column(
                        children: [
                          Text(
                            'روش هوشمند',
                            style: TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'توییتر | اینستاگرام | یوتیوب',
                            style: TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Center(
              key: ValueKey(focusedMode),
              child: AnimatedScale(
                scale: 1.05,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: 1.0,
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutBack,
                    alignment: Alignment.center,
                    child: focusedMode == _ConnectMode.smart
                        ? SmartMethodButton(
                            onFocused: () {
                              setState(
                                () => _connectMode = _ConnectMode.smart,
                              );
                            },
                            bigMode: true,
                          )
                        : ConnectionButton(
                            onFocused: () {
                              setState(
                                () => _connectMode = _ConnectMode.simple,
                              );
                            },
                            bigMode: true,
                          ),
                  ),
                ),
              ),
            ),
    );
  }
}

enum _ConnectMode { none, simple, smart }
class SmartMethodButton extends StatefulWidget {
  final VoidCallback? onFocused;
  final bool bigMode;

  const SmartMethodButton({
    super.key,
    this.onFocused,
    this.bigMode = false,
  });

  @override
  State<SmartMethodButton> createState() => _SmartMethodButtonState();
}

class _SmartMethodButtonState extends State<SmartMethodButton> {
  bool _requested = false;
  bool _isCancelling = false;
  bool _tapLocked = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<V2RayProvider>(
      builder: (context, provider, _) {
        final isSmartActive =
            provider.activeConfig?.id == V2RayProvider.smartModeConfigId;
        final isConnecting = provider.isConnecting;
        final isDisconnecting = isConnecting && isSmartActive;
        final showCancel =
            _requested && isConnecting && !isSmartActive && !_isCancelling;

        // Reset request flag when connection flow ends
        if (!isConnecting && _requested) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _requested = false);
          });
        }

        return GestureDetector(
          onTap: () async {
            widget.onFocused?.call();
            if (isConnecting || _tapLocked) return;
            _tapLocked = true;
            setState(() {
              _requested = true;
            });
            if (isSmartActive) {
              await provider.disconnect();
            } else {
              await provider.connectSmartMode();
            }
            _tapLocked = false;
          },
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.bigMode ? 170 : 160,
                height: widget.bigMode ? 170 : 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _buttonColor(isSmartActive, isConnecting)
                          .withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
              if (isConnecting)
                ...List.generate(2, (i) {
                  final base = widget.bigMode ? 150 : 140;
                  final size = base + i * 12;
                  return Container(
                    width: size.toDouble(),
                    height: size.toDouble(),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _buttonColor(isSmartActive, isConnecting)
                            .withValues(alpha: 0.3 - i * 0.08),
                        width: 2 - i * 0.3,
                      ),
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(
                        begin: 0.95,
                        end: 1.08 + i * 0.03,
                        duration: 900.ms,
                      );
                }),
              if (isConnecting)
                Container(
                  width: widget.bigMode ? 150 : 140,
                  height: widget.bigMode ? 150 : 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        _buttonColor(isSmartActive, isConnecting)
                            .withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ).animate(onPlay: (c) => c.repeat()).rotate(duration: 2.5.seconds),
              _buildSmartCore(
                isSmartActive,
                isConnecting,
                isDisconnecting,
                widget.bigMode,
              ),
              if (showCancel)
                Positioned(
                  bottom: -50,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _isCancelling
                            ? null
                            : () async {
                                setState(() => _isCancelling = true);
                                try {
                                  await provider.disconnect();
                                } catch (_) {}
                                if (mounted) {
                                  setState(() {
                                    _isCancelling = false;
                                    _requested = false;
                                  });
                                }
                              },
                        child: AnimatedOpacity(
                          duration: 200.ms,
                          opacity: _isCancelling ? 0.5 : 1,
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red.withOpacity(0.9),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 7),
                                ),
                              ],
                              border: Border.all(
                                color: Colors.white.withOpacity(0.25),
                                width: 1.2,
                              ),
                            ),
                            child: _isCancelling
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Color _buttonColor(bool isActive, bool isConnecting) {
    if (isConnecting) return AppTheme.connectingBlue;
    return isActive ? AppTheme.connectedGreen : AppTheme.primaryBlue;
  }

  List<Color> _gradient(bool isActive, bool isConnecting, bool isDisconnecting) {
    if (isDisconnecting) {
      return [Colors.orange, Colors.orange.withOpacity(0.7)];
    }
    if (isConnecting) {
      return [AppTheme.connectingBlue, AppTheme.connectingBlue.withOpacity(0.7)];
    }
    if (isActive) {
      return [AppTheme.connectedGreen, AppTheme.connectedGreen.withOpacity(0.7)];
    }
    return [AppTheme.primaryBlue, AppTheme.primaryBlue.withOpacity(0.7)];
  }

  Widget _buildSmartCore(
      bool isActive, bool isConnecting, bool isDisconnecting, bool bigMode) {
    final core = Container(
      width: bigMode ? 155 : 145,
      height: bigMode ? 155 : 145,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: _gradient(isActive, isConnecting, isDisconnecting),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _buttonColor(isActive, isConnecting).withValues(alpha: 0.55),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: bigMode ? 140 : 130,
            height: bigMode ? 140 : 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withOpacity(0.2),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? Icons.shield : Icons.auto_awesome,
                color: Colors.white,
                size: 42,
              ),
              const SizedBox(height: 8),
              Text(
                isDisconnecting
                    ? 'Disconnecting...'
                    : isConnecting
                        ? 'Connecting...'
                        : isActive
                            ? 'قطع روش هوشمند'
                            : 'اتصال هوشمند',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (isConnecting || isDisconnecting)
            Positioned.fill(
              child: CircularProgressIndicator(
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
            ),
        ],
      ),
    );

    if (isConnecting || isDisconnecting) {
      return core
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 0.96, end: 1.04, duration: 850.ms, curve: Curves.easeInOut);
    }
    return core
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 0.99, end: 1.01, duration: 1800.ms, curve: Curves.easeInOut);
  }
}
