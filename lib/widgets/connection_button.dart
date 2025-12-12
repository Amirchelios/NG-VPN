import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/v2ray_provider.dart';
import '../theme/app_theme.dart';
import '../utils/auto_select_util.dart';
import '../utils/app_localizations.dart';

class ConnectionButton extends StatefulWidget {
  final VoidCallback? onFocused;
  final bool bigMode;

  const ConnectionButton({
    super.key,
    this.onFocused,
    this.bigMode = false,
  });

  @override
  State<ConnectionButton> createState() => _ConnectionButtonState();
}

class _ConnectionButtonState extends State<ConnectionButton> {
  bool _isConfiguring = false;
  bool _isCancelling = false;
  bool _tapLocked = false;

  // Cancellation token for auto-select operation
  AutoSelectCancellationToken? _autoSelectCancellationToken;

  // Stream controller for status updates
  late final StreamController<String> _autoSelectStatusStream =
      StreamController<String>.broadcast();

  @override
  void dispose() {
    _autoSelectStatusStream.close();
    super.dispose();
  }

  // Helper method to handle async selection and connection
  Future<void> _connectToFirstServer(V2RayProvider provider) async {
    if (provider.configs.isNotEmpty) {
      await provider.selectConfig(provider.configs.first);
      await provider.connectToServer(
        provider.configs.first,
        provider.isProxyMode,
      );
    }
  }

  Future<void> _cancelCurrent(V2RayProvider provider) async {
    if (_isCancelling) return;
    setState(() {
      _isCancelling = true;
      _isConfiguring = false;
    });
    _autoSelectCancellationToken?.cancel();
    try {
      await provider.disconnect();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isCancelling = false;
      });
    }
  }

  // Helper method to run auto-select and then connect
  Future<void> _runAutoSelectAndConnect(
    BuildContext context,
    V2RayProvider provider,
  ) async {
    setState(() => _isConfiguring = true);

    // Create cancellation token for this auto-select operation
    _autoSelectCancellationToken = AutoSelectCancellationToken();

    // Show a loading dialog while auto-select is running with cancel button
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.secondaryDark,
        title: Text(context.tr(TranslationKeys.serverSelectionAutoSelect)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
            ),
            const SizedBox(height: 16),
            Text(context.tr(TranslationKeys.serverSelectionTestingServers)),
            const SizedBox(height: 8),
            StreamBuilder<String>(
              stream: _autoSelectStatusStream.stream,
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Cancel the auto-select operation
              _autoSelectCancellationToken?.cancel();
              Navigator.of(context).pop();
            },
            child: Text(
              context.tr('common.cancel'),
              style: const TextStyle(color: AppTheme.primaryGreen),
            ),
          ),
        ],
      ),
    );

    try {
      // Run auto-select (ProxyCloud-only, no shadowsocks) with cancellation.
      final result = await provider
          .runSimpleAutoSelect(
        cancellationToken: _autoSelectCancellationToken,
        onStatusUpdate: (message) => _autoSelectStatusStream.add(message),
      )
          .timeout(
        const Duration(seconds: 7),
        onTimeout: () => AutoSelectResult(
          selectedConfig: null,
          bestPing: null,
          errorMessage: 'timeout',
        ),
      );

      // Check if operation was cancelled
      if (result.errorMessage == 'Auto-select cancelled') {
        // Close the dialog
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('common.cancel')),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Close the dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (result.selectedConfig != null && result.bestPing != null) {
        // Select and connect to the best server
        await provider.selectConfig(result.selectedConfig!);
        await provider.connectToServer(
          result.selectedConfig!,
          provider.isProxyMode,
        );
      } else {
        // Fallback: connect to first available config to avoid being stuck
        if (provider.configs.isNotEmpty) {
          final fallback = provider.configs.first;
          await provider.selectConfig(fallback);
          await provider.connectToServer(fallback, provider.isProxyMode);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ?? 'سرور سریع پیدا نشد؛ اتصال به اولین سرور.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Auto-select failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      // Close the dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto-select error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isConfiguring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<V2RayProvider>(
      builder: (context, provider, _) {
        // Show loading state while initializing
        if (provider.isInitializing) {
          return Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.cardDark,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                strokeWidth: 4,
              ),
            ),
          );
        }

        final isConnected = provider.activeConfig != null;
        final isConnecting = provider.isConnecting;
        final selectedConfig = (provider.selectedConfig?.id ==
                V2RayProvider.smartModeConfigId)
            ? null
            : provider.selectedConfig;
        final hasConfigs = provider.configs.isNotEmpty;
        final isPreconfiguring = provider.isPreconfiguring;
        final isConfiguring =
            (_isConfiguring && !isConnecting && !isConnected) || isPreconfiguring;
        final isDisconnecting = isConnecting && isConnected;
        // Cancel درون خود دکمه انجام می‌شود، پس نمایش جداگانه نداریم
        final showCancel = false;
        final isBusy = isConnecting || isConfiguring || isDisconnecting;

        return GestureDetector(
          onTap: () async {
            widget.onFocused?.call();
            // اگر در حال اتصال/پیکربندی است، همین دکمه عمل کنسل را انجام دهد
            if ((isConnecting || isConfiguring) && !_isCancelling) {
              await _cancelCurrent(provider);
              return;
            }
            if (isBusy || provider.isInitializing || _tapLocked) {
              return;
            }
            _tapLocked = true;

            try {
              if (isConnected) {
                await provider.disconnect();
              } else if (selectedConfig != null) {
                // اتصال به سرور انتخاب‌شده
                await provider.connectToServer(
                  selectedConfig,
                  provider.isProxyMode,
                );
              } else if (hasConfigs) {
                // اگر پیش‌انتخاب وجود دارد همان را وصل کن، وگرنه انتخاب خودکار سریع
                final preselected = provider.preselectedConfig;
                if (preselected != null) {
                  await provider.selectConfig(preselected);
                  await provider.connectToServer(
                    preselected,
                    provider.isProxyMode,
                  );
                } else {
                  await _runAutoSelectAndConnect(context, provider);
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.tr(TranslationKeys.serverSelectorNoServers),
                    ),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${context.tr('home.connection_failed')}: ${e.toString()}',
                  ),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            } finally {
              _tapLocked = false;
            }
          },
          child: Container(
            width: widget.bigMode ? 190 : 175,
            height: widget.bigMode ? 190 : 175,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Ambient blur halo (bigger)
                Container(
                  width: widget.bigMode ? 225 : 210,
                  height: widget.bigMode ? 225 : 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _getButtonColor(
                          isConnected,
                          isConnecting,
                          isConfiguring,
                        ).withValues(alpha: 0.20),
                        blurRadius: 30,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                ),

                // Pulsing rings + dual-color blinks
                if (isConnecting || isConfiguring) ...[
                  ...List.generate(2, (i) {
                    final baseSize = widget.bigMode ? 160 : 148;
                    final start = baseSize + i * 14;
                    return Container(
                      width: start.toDouble(),
                      height: start.toDouble(),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _getButtonColor(
                            isConnected,
                            isConnecting,
                            isConfiguring,
                          ).withValues(alpha: 0.35 - i * 0.1),
                          width: 2.2 - i * 0.4,
                        ),
                      ),
                    )
                        .animate(
                          onPlay: (c) => c.repeat(reverse: true),
                        )
                        .scaleXY(
                          begin: 0.96,
                          end: 1.12 + i * 0.05,
                          duration: (900 + i * 200).ms,
                          curve: Curves.easeInOut,
                        )
                        .fadeIn(duration: 250.ms);
                  }),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue.withValues(alpha: 0.15),
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat())
                        .fadeIn(duration: 450.ms)
                        .fadeOut(duration: 450.ms),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withValues(alpha: 0.12),
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat())
                        .fadeIn(delay: 280.ms, duration: 450.ms)
                        .fadeOut(duration: 450.ms),
                  ),
                ],

                // Rotating sweep
                if (isConnecting || isConfiguring)
                  Container(
                    width: widget.bigMode ? 195 : 182,
                    height: widget.bigMode ? 195 : 182,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          _getButtonColor(
                            isConnected,
                            isConnecting,
                            isConfiguring,
                          ).withValues(alpha: 0.25),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat())
                      .rotate(duration: 2.seconds),

                // Secondary sweep for extra dynamism
                if (isConnecting || isConfiguring)
                  Container(
                    width: widget.bigMode ? 175 : 162,
                    height: widget.bigMode ? 175 : 162,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        startAngle: 0.4,
                        endAngle: 6.0,
                        colors: [
                          Colors.white.withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat())
                      .rotate(duration: 3.seconds, begin: 0.25, end: 1.25),

                // Main button with enhanced design
                _buildAnimatedCore(
                  isConnecting: isConnecting,
                  isConfiguring: isConfiguring,
                  isConnected: isConnected,
                  isDisconnecting: isDisconnecting,
                  hasConfigs: hasConfigs,
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
                            : () async => _cancelCurrent(provider),
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
          ),
        );
      },
    );
  }

  Color _getButtonColor(bool isConnected, bool isConnecting, bool isConfiguring) {
    if (isConnecting) return AppTheme.connectingBlue;
    if (isConfiguring) return Colors.amber;
    return isConnected ? AppTheme.connectedGreen : AppTheme.disconnectedRed;
  }

  List<Color> _getGradientColors(
    bool isConnected,
    bool isConnecting,
    bool isConfiguring,
  ) {
    if (isConnecting) {
      return [AppTheme.connectingBlue, AppTheme.connectingBlue.withOpacity(0.7)];
    }
    if (isConfiguring) {
      return [Colors.amber.shade400, Colors.amber.shade600];
    }
    if (isConnected) {
      return [AppTheme.connectedGreen, AppTheme.connectedGreen.withValues(alpha: 0.7)];
    }
    return [AppTheme.disconnectedRed, AppTheme.disconnectedRed.withValues(alpha: 0.7)];
  }

  IconData _getButtonIcon(bool isConnected, bool isConnecting, bool isConfiguring, bool isDisconnecting) {
    if (isDisconnecting) return Icons.power_off;
    if (isConnecting || isConfiguring) return Icons.sync;
    return isConnected ? Icons.power_off : Icons.power_settings_new;
  }

  String _getButtonText(
    bool isConnected,
    bool isConnecting,
    bool hasConfigs,
    bool isConfiguring,
    bool isDisconnecting,
  ) {
    if (isDisconnecting) return 'Disconnecting...';
    if (isConnecting) return 'Connecting...';
    if (isConfiguring) return 'در حال پیکربندی';
    if (isConnected) return 'Disconnect';
    if (hasConfigs) return 'Connect';
    return 'No Servers';
  }
  Widget _buildAnimatedCore({
    required bool isConnecting,
    required bool isConfiguring,
    required bool isConnected,
    required bool isDisconnecting,
    required bool hasConfigs,
  }) {
    final core = Container(
      width: widget.bigMode ? 185 : 165,
      height: widget.bigMode ? 185 : 165,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDisconnecting
              ? [Colors.orange, Colors.orange.withOpacity(0.7)]
              : _getGradientColors(
                  isConnected,
                  isConnecting,
                  isConfiguring,
                ),
        ),
        boxShadow: [
          BoxShadow(
            color: _getButtonColor(
              isConnected,
              isConnecting,
              isConfiguring,
            ).withOpacity(0.55),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Inner glow effect
          Container(
            width: widget.bigMode ? 170 : 150,
            height: widget.bigMode ? 170 : 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withOpacity(0.25),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Icon with label
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _getButtonIcon(isConnected, isConnecting, isConfiguring, isDisconnecting),
                color: Colors.white,
                size: widget.bigMode ? 56 : 52,
              ),
              const SizedBox(height: 8),
              Text(
                _getButtonText(
                  isConnected,
                  isConnecting,
                  hasConfigs,
                  isConfiguring,
                  isDisconnecting,
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              if (isConnecting || isConfiguring) ...[
                const SizedBox(height: 6),
                const Text(
                  'برای متوقف کردن فشار دهید',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),

          // Progress indicator when connecting/configuring
          if (isConnecting || isConfiguring)
            Positioned.fill(
              child: CircularProgressIndicator(
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.white,
                ),
                strokeWidth: 3,
              ),
            ),
        ],
      ),
    );

    if (isConnecting || isConfiguring || isDisconnecting) {
      return core
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(
            begin: 0.96,
            end: isDisconnecting ? 1.02 : 1.04,
            duration: 850.ms,
            curve: Curves.easeInOut,
          )
          .shimmer(delay: 0.ms, duration: 1300.ms, colors: [
            Colors.white.withOpacity(0.18),
            Colors.transparent,
          ]);
    }

    // Idle subtle breathing
    return core
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 0.99, end: 1.01, duration: 1800.ms, curve: Curves.easeInOut);
  }
}
