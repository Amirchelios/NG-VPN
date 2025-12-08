import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/v2ray_config.dart';
import '../models/subscription.dart';
import '../services/v2ray_service.dart';
import '../services/server_service.dart';
import '../utils/auto_select_util.dart';

class V2RayProvider with ChangeNotifier, WidgetsBindingObserver {
  static const String smartModeConfigId = 'smart-mode-config';
  static const String _smartModeRemark = 'روش هوشمند';
  static const String _smartModeConfigJson = '''
{
  "remarks": "ServLess frag tlshello",
  "log": {
    "access": "",
    "error": "",
    "loglevel": "none",
    "dnsLog": false
  },
  "dns": {
    "tag": "dns",
    "hosts": {
      "cloudflare-dns.com": [
        "172.67.73.38",
        "104.19.155.92",
        "172.67.73.163",
        "104.18.155.42",
        "104.16.124.175",
        "104.16.248.249",
        "104.16.249.249",
        "104.26.13.8"
      ],
      "domain:youtube.com": ["google.com"]
    },
    "servers": ["https://cloudflare-dns.com/dns-query"]
  },
  "inbounds": [
    {
      "domainOverride": ["http", "tls"],
      "protocol": "socks",
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "port": 10808,
      "settings": {
        "auth": "noauth",
        "udp": true,
        "userLevel": 8
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "protocol": "http",
      "tag": "http-in",
      "listen": "127.0.0.1",
      "port": 10809,
      "settings": {
        "userLevel": 8
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "fragment-out",
      "domainStrategy": "UseIP",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "settings": {
        "fragment": {
          "packets": "tlshello",
          "length": "10-20",
          "interval": "10-20"
        }
      },
      "streamSettings": {
        "sockopt": {
          "tcpNoDelay": true,
          "tcpKeepAliveIdle": 100,
          "mark": 255,
          "domainStrategy": "UseIP"
        }
      }
    },
    {
      "protocol": "dns",
      "tag": "dns-out"
    },
    {
      "protocol": "vless",
      "tag": "fakeproxy-out",
      "domainStrategy": "",
      "settings": {
        "vnext": [
          {
            "address": "google.com",
            "port": 443,
            "users": [
              {
                "encryption": "none",
                "flow": "",
                "id": "UUID",
                "level": 8,
                "security": "auto"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": false,
          "alpn": ["h2", "http/1.1"],
          "fingerprint": "randomized",
          "publicKey": "",
          "serverName": "google.com",
          "shortId": "",
          "show": false,
          "spiderX": ""
        },
        "wsSettings": {
          "headers": {
            "Host": "google.com"
          },
          "path": "/"
        }
      },
      "mux": {
        "concurrency": 8,
        "enabled": false
      }
    }
  ],
  "policy": {
    "levels": {
      "8": {
        "connIdle": 300,
        "downlinkOnly": 1,
        "handshake": 4,
        "uplinkOnly": 1
      }
    },
    "system": {
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "inboundTag": ["socks-in", "http-in"],
        "type": "field",
        "port": "53",
        "outboundTag": "dns-out",
        "enabled": true
      },
      {
        "inboundTag": ["socks-in", "http-in"],
        "type": "field",
        "port": "0-65535",
        "outboundTag": "fragment-out",
        "enabled": true
      }
    ],
    "strategy": "rules"
  },
  "stats": {}
}''';
  final V2RayService _v2rayService = V2RayService();
  final ServerService _serverService = ServerService();
  bool statusPingOnly = false;
  List<V2RayConfig> _configs = [];
  List<Subscription> _subscriptions = [];
  V2RayConfig? _selectedConfig;
  bool _isConnecting = false;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isLoadingServers = false;
  bool _isProxyMode = false;
  bool _isInitializing = true;
  Timer? _connectionHealthTimer;
  int _connectionHealthFailures = 0;
  String? _healthMonitorConfigId;
  bool _isPreconfiguring = false;
  String? _preselectedConfigId;

  // Method channel for VPN control
  static const platform = MethodChannel('com.cloud.pira/vpn_control');

  List<V2RayConfig> get configs => _configs;
  List<Subscription> get subscriptions => _subscriptions;
  V2RayConfig? get selectedConfig => _selectedConfig;
  V2RayConfig? get activeConfig => _v2rayService.activeConfig;
  bool get isConnecting => _isConnecting;
  bool get isLoading => _isLoading;
  bool get isLoadingServers => _isLoadingServers;
  bool get isInitializing => _isInitializing; // New getter
  bool get isPreconfiguring => _isPreconfiguring;
  String get errorMessage => _errorMessage;
  V2RayService get v2rayService => _v2rayService;
  bool get isProxyMode => _isProxyMode;
  V2RayConfig? get preselectedConfig {
    if (_preselectedConfigId == null) return null;
    try {
      return _configs.firstWhere((c) => c.id == _preselectedConfigId);
    } catch (_) {
      return null;
    }
  }

  // Expose V2Ray status for real-time traffic monitoring
  V2RayStatus? get currentStatus => _v2rayService.currentStatus;

  V2RayProvider() {
    WidgetsBinding.instance.addObserver(this);
    _initialize();

    // Set up method channel handler
    platform.setMethodCallHandler(_handleMethodCall);
  }

  // Handle method calls from native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'disconnectFromNotification':
        await _handleNotificationDisconnect();
        break;
      default:
        throw MissingPluginException();
    }
  }

  Future<void> _handleNotificationDisconnect() async {
    // Actually disconnect the VPN service
    await _v2rayService.disconnect();
    _stopConnectionHealthMonitor();

    // Update config status when disconnected from notification
    for (int i = 0; i < _configs.length; i++) {
      _configs[i].isConnected = false;
    }

    // Notify listeners immediately to update UI in real-time
    notifyListeners();

    // Persist the changes
    try {
      await _v2rayService.saveConfigs(_configs);
      notifyListeners();
    } catch (e) {
      print('Error saving configs after notification disconnect: $e');
      notifyListeners();
    }
  }

  Future<void> _initialize() async {
    _setLoading(true);
    _isInitializing = true; // Set initialization flag
    notifyListeners();

    const updateInterval = Duration(hours: 24);

    try {
      await _v2rayService.initialize();

      // Set up callback for notification disconnects
      _v2rayService.setDisconnectedCallback(() async {
        await _handleNotificationDisconnect();
      });

      // Load configurations first
      await loadConfigs();
      debugPrint('Loaded ${_configs.length} configs during initialization');

      // Load subscriptions
      await loadSubscriptions();
      debugPrint('Loaded ${_subscriptions.length} subscriptions during initialization');

      // Load proxy mode setting from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _isProxyMode = prefs.getBool('proxy_mode_enabled') ?? false;

      // Startup: skip automatic subscription refresh to speed up launch.
      // User can refresh manually from UI when needed.

      // CRITICAL FIX: Enhanced synchronization with actual VPN service state
      await _enhancedSyncWithVpnServiceState();

      // Start a quick preconfiguration to find a best server for simple mode
      if (_configs.isNotEmpty) {
        unawaited(_preselectBestServer());
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to initialize: $e');
      debugPrint('Initialization error: $e');
    } finally {
      _setLoading(false);
      _isInitializing = false; // Clear initialization flag
      notifyListeners();
    }
  }

  // CRITICAL FIX: Enhanced method to synchronize with actual VPN service state
  Future<void> _enhancedSyncWithVpnServiceState() async {
    try {
      print('Enhanced synchronization with VPN service state...');

      // First, check if VPN is actually running using the improved method
      final isActuallyConnected = await _v2rayService.isActuallyConnected();
      print(
        'VPN service status - Actually connected (primary check): $isActuallyConnected',
      );

      // Reset all connection states first
      for (int i = 0; i < _configs.length; i++) {
        _configs[i].isConnected = false;
      }

      if (isActuallyConnected) {
        print('VPN is actually running, synchronizing config states...');

        // Try to get the active config from service
        final activeConfigFromService = _v2rayService.activeConfig;
        print('Active config from service: ${activeConfigFromService?.remark}');

        if (activeConfigFromService != null) {
          bool configFound = false;

          // Try to find exact matching config
          for (var config in _configs) {
            if (config.fullConfig == activeConfigFromService.fullConfig) {
              config.isConnected = true;
              _selectedConfig = config;
              configFound = true;
              print('Found exact matching config: ${config.remark}');
              break;
            }
          }

          // If we couldn't find the exact active config in our list,
          // try to find a matching one by address and port
          if (!configFound) {
            for (var config in _configs) {
              if (config.address == activeConfigFromService.address &&
                  config.port == activeConfigFromService.port) {
                config.isConnected = true;
                _selectedConfig = config;
                configFound = true;
                print(
                  'Found matching config by address/port: ${config.remark}',
                );
                break;
              }
            }
          }

          // If still no matching config found, add the active config temporarily
          if (!configFound) {
            print('No matching config found in list for active VPN connection');
            // Add the active config to our list temporarily
            _configs.add(activeConfigFromService);
            activeConfigFromService.isConnected = true;
            _selectedConfig = activeConfigFromService;
            print(
              'Added active config to list: ${activeConfigFromService.remark}',
            );
          }
        } else {
          // VPN is running but we don't have the config details
          // Try to find any config that might be connected
          print(
            'VPN is running but no active config in service, checking configs...',
          );
          V2RayConfig? foundConnectedConfig;

          // Check if any config has connection details that match a running service
          for (var config in _configs) {
            try {
              final parser = V2ray.parseFromURL(config.fullConfig);
              // We can't directly ping without the service, so we'll mark the first one as connected
              config.isConnected = true;
              _selectedConfig = config;
              foundConnectedConfig = config;
              print('Marked config as connected by default: ${config.remark}');
              break;
            } catch (e) {
              print('Error checking config ${config.remark}: $e');
            }
          }

          if (foundConnectedConfig == null) {
            print(
              'Could not identify which config is connected, marking first available',
            );
            // As a fallback, mark the first config as connected if we have configs
            if (_configs.isNotEmpty) {
              _configs.first.isConnected = true;
              _selectedConfig = _configs.first;
              print(
                'Marked first config as connected: ${_configs.first.remark}',
              );
            }
          }
        }
      } else {
        print('VPN is not actually connected, clearing connection states');
        // VPN is not running, ensure all configs show disconnected
        for (var config in _configs) {
          config.isConnected = false;
        }
        // FIX: Don't clear the selected config when VPN is not connected
        // _selectedConfig = null;  // This line was causing the bug

        // Clear active config from service if it exists
        if (_v2rayService.activeConfig != null) {
          await _v2rayService.disconnect();
        }
      }

      // Save the synchronized state
      await _v2rayService.saveConfigs(_configs);
      print('VPN service state synchronization completed');
    } catch (e) {
      print('Error in enhanced synchronization with VPN service state: $e');
      // On error, ensure clean state
      for (var config in _configs) {
        config.isConnected = false;
      }
      // FIX: Don't clear the selected config on error
      // _selectedConfig = null;  // This line was causing the bug
    }
  }

  Future<void> loadConfigs() async {
    _setLoading(true);
    try {
      _configs = await _v2rayService.loadConfigs();
      notifyListeners();
    } catch (e) {
      _setError('Failed to load configurations: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchServers({required String customUrl}) async {
    _isLoadingServers = true;
    _errorMessage = '';
    notifyListeners();

    try {
      // Fetch servers from service using the provided custom URL
      final servers = await _serverService.fetchServers(customUrl: customUrl);

      if (servers.isNotEmpty) {
        // Get all subscription config IDs to preserve them
        final subscriptionConfigIds = <String>{};
        for (var subscription in _subscriptions) {
          subscriptionConfigIds.addAll(subscription.configIds);
        }

        // Clear ping cache for default servers (non-subscription servers)
        for (var config in _configs) {
          if (!subscriptionConfigIds.contains(config.id)) {
            _v2rayService.clearPingCache(configId: config.id);
          }
        }

        // Keep existing subscription configs
        final subscriptionConfigs = _configs
            .where((c) => subscriptionConfigIds.contains(c.id))
            .toList();

        // Add default servers to the configs list
        _configs = [...subscriptionConfigs, ...servers];

        // Save configs and update UI immediately to show servers
        await _v2rayService.saveConfigs(_configs);

        // Mark loading as complete
        _isLoadingServers = false;
        notifyListeners();

        // Server delay functionality removed as requested
      } else {
        // If no servers found online, try to load from local storage
        _configs = await _v2rayService.loadConfigs();
      }
    } catch (e) {
      _setError('Failed to fetch servers: $e');
      // Try to load from local storage as fallback
      _configs = await _v2rayService.loadConfigs();
      notifyListeners();
    } finally {
      _isLoadingServers = false;
      notifyListeners();
    }
  }

  Future<void> loadSubscriptions() async {
    _setLoading(true);
    try {
      _subscriptions = await _v2rayService.loadSubscriptions();
      
      // Debug information
      debugPrint('Loaded ${_subscriptions.length} subscriptions');
      for (var sub in _subscriptions) {
        debugPrint('  Subscription: ${sub.name} with ${sub.configIds.length} configs');
      }

      // Create default subscription if no subscriptions exist
      if (_subscriptions.isEmpty) {
        final defaultSubscription = Subscription(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: 'Default Subscription',
          url:
              'https://raw.githubusercontent.com/darkvpnapp/CloudflarePlus/refs/heads/main/proxy',
          lastUpdated: DateTime.now(),
          configIds: [],
        );
        _subscriptions.add(defaultSubscription);
        await _v2rayService.saveSubscriptions(_subscriptions);
        debugPrint('Created default subscription');
      }

      // Ensure configs are loaded and match subscription config IDs
      if (_configs.isEmpty) {
        _configs = await _v2rayService.loadConfigs();
        debugPrint('Loaded ${_configs.length} configs');
      }

      // Verify that all subscription config IDs exist in the configs list
      // If not, it means the configs weren't properly saved or loaded
      for (var subscription in _subscriptions) {
        final configIds = subscription.configIds;
        final existingConfigIds = _configs.map((c) => c.id).toSet();
        
        debugPrint('Subscription "${subscription.name}" has ${configIds.length} config IDs, ${existingConfigIds.length} existing configs');

        // Check if any config IDs in the subscription are missing from the configs list
        final missingConfigIds = configIds
            .where((id) => !existingConfigIds.contains(id))
            .toList();

        if (missingConfigIds.isNotEmpty) {
          debugPrint(
            'Warning: Found ${missingConfigIds.length} missing configs for subscription ${subscription.name}: $missingConfigIds',
          );
          // Update the subscription to remove missing config IDs
          final updatedConfigIds = configIds
              .where((id) => existingConfigIds.contains(id))
              .toList();
          final index = _subscriptions.indexWhere(
            (s) => s.id == subscription.id,
          );
          if (index != -1) {
            _subscriptions[index] = subscription.copyWith(
              configIds: updatedConfigIds,
            );
            debugPrint('Updated subscription "${subscription.name}" to have ${updatedConfigIds.length} config IDs');
          }
        }
      }

      notifyListeners();
    } catch (e) {
      _setError('Failed to load subscriptions: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addConfig(V2RayConfig config) async {
    // Add config and display it immediately
    _configs.add(config);
    debugPrint('Added config: ${config.remark} (${config.id}) - Total configs: ${_configs.length}');

    // Save the configuration immediately to display it
    await _v2rayService.saveConfigs(_configs);
    notifyListeners();
  }

  Future<void> removeConfig(V2RayConfig config) async {
    try {
      debugPrint('Removing config: ${config.remark} (${config.id})');
      _configs.removeWhere((c) => c.id == config.id);
      debugPrint('After removal - Total configs: ${_configs.length}');

      // Also remove from subscriptions if the config is part of any subscription
      for (int i = 0; i < _subscriptions.length; i++) {
        final subscription = _subscriptions[i];
        if (subscription.configIds.contains(config.id)) {
          debugPrint('Removing config from subscription: ${subscription.name}');
          final updatedConfigIds = List<String>.from(subscription.configIds)
            ..remove(config.id);
          _subscriptions[i] = subscription.copyWith(
            configIds: updatedConfigIds,
          );
        }
      }

      // If the deleted config was selected, clear the selection
      if (_selectedConfig?.id == config.id) {
        _selectedConfig = null;
      }

      await _v2rayService.saveConfigs(_configs);
      await _v2rayService.saveSubscriptions(_subscriptions);
      notifyListeners();
    } catch (e) {
      _setError('Failed to delete configuration: $e');
    }
  }

  Future<V2RayConfig?> importConfigFromText(String configText) async {
    try {
      // Try to parse the configuration
      final config = await _v2rayService.parseSubscriptionConfig(configText);
      if (config == null) {
        throw Exception('Invalid configuration format');
      }

      // Add the config to the list
      await addConfig(config);

      return config;
    } catch (e) {
      _setError('Failed to import configuration: $e');
      return null;
    }
  }

  Future<List<V2RayConfig>> importConfigsFromText(String configText) async {
    try {
      // Parse multiple configurations from text (similar to subscription parsing)
      final configs = await _v2rayService.parseSubscriptionContent(configText);

      if (configs.isEmpty) {
        throw Exception('No valid configurations found');
      }

      // Add all configs to the list
      for (var config in configs) {
        await addConfig(config);
      }

      return configs;
    } catch (e) {
      _setError('Failed to import configurations: $e');
      return [];
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Dispose the service to stop monitoring
    _v2rayService.dispose();
    // Disconnect if connected when disposing
    if (_v2rayService.activeConfig != null) {
      _v2rayService.disconnect();
    }
    super.dispose();
  }

  Future<void> addSubscription(String name, String url) async {
    _setLoading(true);
    _errorMessage = '';
    try {
      final configs = await _v2rayService.parseSubscriptionUrl(url);
      if (configs.isEmpty) {
        _setError('No valid configurations found in subscription');
        return;
      }

      // Add configs and display them immediately
      _configs.addAll(configs);

      final newConfigIds = configs.map((c) => c.id).toList();
      
      // Debug information
      debugPrint('Adding subscription "$name" with ${configs.length} configs and IDs: $newConfigIds');

      // Create subscription
      final subscription = Subscription(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        url: url,
        lastUpdated: DateTime.now(),
        configIds: newConfigIds,
      );

      _subscriptions.add(subscription);

      // Save both configs and subscription
      await _v2rayService.saveConfigs(_configs);
      await _v2rayService.saveSubscriptions(_subscriptions);
      
      // Debug information
      debugPrint('Subscription "$name" added successfully');

      // Update UI after everything is saved
      notifyListeners();
    } catch (e) {
      String errorMsg = 'Failed to add subscription';

      // Provide more specific error messages
      if (e.toString().contains('Network error') ||
          e.toString().contains('timeout') ||
          e.toString().contains('SocketException')) {
        errorMsg = 'Network error: Check your internet connection';
      } else if (e.toString().contains('Invalid URL')) {
        errorMsg = 'Invalid subscription URL format';
      } else if (e.toString().contains('No valid servers')) {
        errorMsg = 'No valid servers found in subscription';
      } else if (e.toString().contains('HTTP')) {
        errorMsg = 'Server error: ${e.toString()}';
      } else {
        errorMsg = 'Failed to add subscription: ${e.toString()}';
      }

      _setError(errorMsg);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateSubscription(Subscription subscription) async {
    _setLoading(true);
    _isLoadingServers = true;
    _errorMessage = '';
    notifyListeners();

    try {
      // NEW: Force fresh fetch by bypassing any cache mechanisms
      final configs = await _v2rayService.parseSubscriptionUrl(
        subscription.url,
      );
      if (configs.isEmpty) {
        _setError('No valid configurations found in subscription');
        _isLoadingServers = false;
        notifyListeners();
        return;
      }

      // Clear ping cache for old configs before removing them
      for (var configId in subscription.configIds) {
        _v2rayService.clearPingCache(configId: configId);
      }

      // Remove old configs
      _configs.removeWhere((c) => subscription.configIds.contains(c.id));

      // Add new configs and display them immediately
      _configs.addAll(configs);

      final newConfigIds = configs.map((c) => c.id).toList();

      // Update subscription
      final index = _subscriptions.indexWhere((s) => s.id == subscription.id);
      if (index != -1) {
        _subscriptions[index] = subscription.copyWith(
          lastUpdated: DateTime.now(),
          configIds: newConfigIds,
        );

        // Save both configs and subscriptions to ensure persistence
        await _v2rayService.saveConfigs(_configs);
        await _v2rayService.saveSubscriptions(_subscriptions);
      }

      // Mark loading as complete
      _isLoadingServers = false;
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      String errorMsg = 'Failed to update subscription';

      // Provide more specific error messages
      if (e.toString().contains('Network error') ||
          e.toString().contains('timeout') ||
          e.toString().contains('SocketException')) {
        errorMsg = 'Network error: Check your internet connection';
      } else if (e.toString().contains('Invalid URL')) {
        errorMsg = 'Invalid subscription URL format';
      } else if (e.toString().contains('No valid servers')) {
        errorMsg = 'No valid servers found in subscription';
      } else if (e.toString().contains('HTTP')) {
        errorMsg = 'Server error: ${e.toString()}';
      } else {
        errorMsg = 'Failed to update subscription: ${e.toString()}';
      }

      _setError(errorMsg);
    } finally {
      _setLoading(false);
    }
  }

  // Update subscription info without refreshing servers
  Future<void> updateSubscriptionInfo(Subscription subscription) async {
    _setLoading(true);
    _errorMessage = '';

    try {
      // Find and update the subscription
      final index = _subscriptions.indexWhere((s) => s.id == subscription.id);
      if (index != -1) {
        _subscriptions[index] = subscription;
        await _v2rayService.saveSubscriptions(_subscriptions);
        notifyListeners();
      } else {
        _setError('Subscription not found');
      }
    } catch (e) {
      String errorMsg = 'Failed to update subscription info';

      // Provide more specific error messages
      if (e.toString().contains('Network error') ||
          e.toString().contains('timeout') ||
          e.toString().contains('SocketException')) {
        errorMsg = 'Network error: Check your internet connection';
      } else if (e.toString().contains('Invalid URL')) {
        errorMsg = 'Invalid subscription URL format';
      } else if (e.toString().contains('Permission')) {
        errorMsg = 'Permission error: Unable to save subscription';
      } else {
        errorMsg = 'Failed to update subscription info: ${e.toString()}';
      }

      _setError(errorMsg);
    } finally {
      _setLoading(false);
    }
  }

  // Update all subscriptions
  Future<void> updateAllSubscriptions() async {
    _setLoading(true);
    _errorMessage = '';
    _isLoadingServers = true;
    notifyListeners();

    // Clear all ping cache before updating subscriptions
    _v2rayService.clearPingCache();

    try {
      // Make a copy to avoid modification during iteration
      final subscriptionsCopy = List<Subscription>.from(_subscriptions);
      bool anyUpdated = false;
      List<String> failedSubscriptions = [];

      // Keep track of all subscription config IDs to properly filter local configs
      final allSubscriptionConfigIds = <String>{};

      for (final subscription in subscriptionsCopy) {
        try {
          // Skip empty or invalid subscriptions
          if (subscription.url.isEmpty) continue;

          // NEW: Force fresh fetch by bypassing any cache mechanisms
          final configs = await _v2rayService.parseSubscriptionUrl(
            subscription.url,
          );

          // Remove old configs for this subscription (if any exist)
          _configs.removeWhere((c) => subscription.configIds.contains(c.id));

          // Add new configs
          _configs.addAll(configs);

          final newConfigIds = configs.map((c) => c.id).toList();

          // Update subscription
          final index = _subscriptions.indexWhere(
            (s) => s.id == subscription.id,
          );
          if (index != -1) {
            _subscriptions[index] = subscription.copyWith(
              lastUpdated: DateTime.now(),
              configIds: newConfigIds,
            );
            anyUpdated = true;
          }

          // Add new config IDs to the set of all subscription config IDs
          allSubscriptionConfigIds.addAll(newConfigIds);
        } catch (e) {
          // Record failed subscription
          failedSubscriptions.add(subscription.name);
          print('Error updating subscription ${subscription.name}: $e');
        }
      }

      // Save all changes at once to reduce disk operations
      if (anyUpdated) {
        await _v2rayService.saveConfigs(_configs);
        await _v2rayService.saveSubscriptions(_subscriptions);
      }

      // Set error message if any subscriptions failed
      if (failedSubscriptions.isNotEmpty) {
        if (failedSubscriptions.length == _subscriptions.length) {
          // All subscriptions failed - likely a network issue
          _setError(
            'Failed to update subscriptions: Network error or invalid URLs',
          );
        } else {
          // Some subscriptions failed
          _setError('Failed to update: ${failedSubscriptions.join(', ')}');
        }
      }

      _isLoadingServers = false;
      notifyListeners();
    } catch (e) {
      _setError('Failed to update all subscriptions: $e');
    } finally {
      _setLoading(false);
      _isLoadingServers = false;
    }
  }

  Future<void> removeSubscription(Subscription subscription) async {
    // Remove configs associated with this subscription
    _configs.removeWhere((c) => subscription.configIds.contains(c.id));

    // Remove subscription
    _subscriptions.removeWhere((s) => s.id == subscription.id);

    await _v2rayService.saveConfigs(_configs);
    await _v2rayService.saveSubscriptions(_subscriptions);
    notifyListeners();
  }

  Future<void> connectToServer(V2RayConfig config, bool _isProxyMode) async {
    _stopConnectionHealthMonitor();
    _isConnecting = true;
    _errorMessage = '';
    notifyListeners();

    // Maximum number of connection attempts
    const int maxAttempts = 3;
    // Delay between attempts in seconds
    const int retryDelaySeconds = 2;

    try {
      // Disconnect from current server if connected
      if (_v2rayService.activeConfig != null) {
        try {
          await _v2rayService.disconnect();
          // Add a small delay to ensure disconnection is complete
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          debugPrint('Error disconnecting from current server: $e');
          // Continue with connection attempt even if disconnect failed
        }
      }

      // Try to connect with automatic retry
      bool success = false;
      String lastError = '';
      int attemptCount = 0;

      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        attemptCount = attempt;
        try {
          debugPrint(
            'Connection attempt $attempt/$maxAttempts for ${config.remark}',
          );

          // Connect to server with timeout
          success = await _v2rayService
              .connect(config, _isProxyMode)
              .timeout(
                const Duration(seconds: 30), // Timeout for connection
                onTimeout: () {
                  debugPrint('Connection timeout for ${config.remark}');
                  return false;
                },
              );

          if (success) {
            debugPrint('Connection successful for ${config.remark}');
            // Verify the connection is actually established
            await Future.delayed(const Duration(seconds: 1));
            final connectionVerified = await _v2rayService
                .isActuallyConnected();
            if (connectionVerified) {
              debugPrint('Connection verified for ${config.remark}');
              break;
            } else {
              debugPrint('Connection verification failed for ${config.remark}');
              success = false;
              lastError = 'Connection verification failed';
            }
          } else {
            // Connection failed but no exception was thrown
            lastError =
                'Failed to connect to ${config.remark} on attempt $attempt';
            debugPrint(lastError);

            // If this is not the last attempt, wait before retrying
            if (attempt < maxAttempts) {
              await Future.delayed(Duration(seconds: retryDelaySeconds));
            }
          }
        } catch (e) {
          // Check if this is a timeout-related error
          if (e.toString().contains('timeout')) {
            lastError = 'Connection timeout on attempt $attempt: $e';
            debugPrint(lastError);
          } else {
            lastError = 'Error on connection attempt $attempt: $e';
            debugPrint(lastError);
          }

          // If this is not the last attempt, wait before retrying
          if (attempt < maxAttempts) {
            await Future.delayed(Duration(seconds: retryDelaySeconds));
          }
        }
      }

      if (success) {
        try {
          // Wait for connection to stabilize
          await Future.delayed(
            const Duration(seconds: 2),
          ); // Reduced from 3 to 2 seconds

          // Update config status safely
          for (int i = 0; i < _configs.length; i++) {
            if (_configs[i].id == config.id) {
              _configs[i].isConnected = true;
              _configs[i].isProxyMode =
                  _isProxyMode; // Update proxy mode status
            } else {
              _configs[i].isConnected = false;
            }
          }
          _selectedConfig = config;
          _isProxyMode = _isProxyMode; // Update provider's proxy mode state

          // Persist the changes with error handling
          try {
            await _v2rayService.saveConfigs(_configs);
          } catch (e) {
            debugPrint('Error saving configs after connection: $e');
            // Don't fail the connection for this
          }

          // Reset usage statistics when connecting to a new server
          try {
            await _v2rayService.resetUsageStats();
          } catch (e) {
            debugPrint('Error resetting usage stats: $e');
            // Don't fail the connection for this
          }

          final connectionHealthy = await _verifyConnectionQuality();
          if (!connectionHealthy) {
            debugPrint(
              'Connectivity verification failed after connecting to ${config.remark}',
            );
            try {
              await _v2rayService.disconnect();
            } catch (e) {
              debugPrint('Error disconnecting after failed verification: $e');
            }
            for (final cfg in _configs) {
              cfg.isConnected = false;
            }
            _selectedConfig = null;
            try {
              await _v2rayService.saveConfigs(_configs);
            } catch (e) {
              debugPrint('Error saving configs after failed verification: $e');
            }
            _setError(
              'Connected server did not pass the internet reachability test. Trying another server...',
            );
            await _removeFaultyConfig(config);
            _isConnecting = false;
            notifyListeners();
            Future.microtask(
              () => _connectToBestAvailableServer(
                excludeIds: {config.id},
              ),
            );
            return;
          }

          debugPrint('Successfully connected to ${config.remark}');
          _startConnectionHealthMonitor(config);
        } catch (e) {
          debugPrint('Error in post-connection setup: $e');
          // Connection succeeded but post-setup failed
          _setError('Connected but failed to update settings: $e');
        }
      } else {
        _setError(
          'Failed to connect to ${config.remark} after $attemptCount attempts: $lastError',
        );
        Future.microtask(
          () => _handleFailedServer(config, lastError),
        );
      }
    } catch (e) {
      debugPrint('Unexpected error in connection process: $e');
      _setError('Unexpected error connecting to ${config.remark}: $e');
      Future.microtask(
        () => _handleFailedServer(config, e.toString()),
      );
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  V2RayConfig _buildSmartModeConfig() {
    return V2RayConfig(
      id: smartModeConfigId,
      remark: _smartModeRemark,
      address: 'google.com',
      port: 443,
      configType: 'vless',
      fullConfig: _smartModeConfigJson,
      isConnected: false,
      isProxyMode: false,
    );
  }

  Future<void> connectSmartMode() async {
    _stopConnectionHealthMonitor();
    _isConnecting = true;
    _errorMessage = '';
    notifyListeners();

    final smartConfig = _buildSmartModeConfig();

    try {
      // Ensure clean state before starting smart connection
      if (_v2rayService.activeConfig != null) {
        await _v2rayService.disconnect();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      await _v2rayService.resetUsageStats();

      final success = await _v2rayService.connectWithRawConfig(
        config: smartConfig,
        proxyOnly: false,
      );

      if (success) {
        // Mark other configs as disconnected
        for (int i = 0; i < _configs.length; i++) {
          _configs[i].isConnected = false;
        }
        smartConfig.isConnected = true;
        _selectedConfig = smartConfig;
        _startConnectionHealthMonitor(smartConfig);
      } else {
        _setError('Failed to start smart mode connection');
      }
    } catch (e) {
      _setError('Smart mode error: $e');
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _isConnecting = true;
    notifyListeners();

    try {
      _stopConnectionHealthMonitor();
      await _v2rayService.disconnect();
      statusPingOnly = false;
      // Update config status
      for (int i = 0; i < _configs.length; i++) {
        _configs[i].isConnected = false;
      }

      // Persist the changes
      await _v2rayService.saveConfigs(_configs);
    } catch (e) {
      _setError('Error disconnecting: $e');
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> selectConfig(V2RayConfig config) async {
    _selectedConfig = config;
    // Save the selected config for persistence
    await _v2rayService.saveSelectedConfig(config);
    notifyListeners();
  }

  // تغییر وضعیت بین حالت پروکسی و تونل
  void toggleProxyMode(bool isProxy) {
    _isProxyMode = isProxy;
    // اینجا می‌توانیم منطق اضافی برای تغییر حالت اضافه کنیم
    // مثلاً ارسال دستور به سرویس برای تغییر حالت
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    _isLoadingServers = loading; // Update server loading state as well
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  Future<bool> _verifyConnectionQuality() async {
    try {
      final response = await http
          .get(Uri.parse('https://www.google.com/generate_204'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      debugPrint('Connectivity verification error: $e');
      return false;
    }
  }

  Future<void> _removeFaultyConfig(V2RayConfig config) async {
    _configs.removeWhere((cfg) => cfg.id == config.id);
    try {
      await _v2rayService.saveConfigs(_configs);
    } catch (e) {
      debugPrint('Error saving configs after removing faulty server: $e');
    }
  }

  Future<bool> _connectToBestAvailableServer({Set<String>? excludeIds}) async {
    final exclude = excludeIds ?? {};
    final candidates =
        _configs.where((cfg) => !exclude.contains(cfg.id)).toList();
    if (candidates.isEmpty) {
      _setError('No other servers available to connect.');
      return false;
    }

    final result = await AutoSelectUtil.runAutoSelect(
      candidates,
      _v2rayService,
    );

    if (result.selectedConfig == null) {
      _setError(
        result.errorMessage ?? 'No suitable server available for fallback.',
      );
      return false;
    }

    await connectToServer(result.selectedConfig!, _isProxyMode);
    return true;
  }

  Future<void> _handleFailedServer(
    V2RayConfig config,
    String reason,
  ) async {
    debugPrint('Handling failed server ${config.remark}: $reason');
    if (_healthMonitorConfigId == config.id) {
      _stopConnectionHealthMonitor();
    }
    await _removeFaultyConfig(config);
    await _connectToBestAvailableServer(excludeIds: {config.id});
  }

  void _startConnectionHealthMonitor(V2RayConfig config) {
    _stopConnectionHealthMonitor();
    _healthMonitorConfigId = config.id;
    _connectionHealthFailures = 0;
    _connectionHealthTimer = Timer.periodic(
      const Duration(seconds: 30),
      (timer) async {
        if (_v2rayService.activeConfig?.id != _healthMonitorConfigId) {
          _stopConnectionHealthMonitor();
          return;
        }
        final healthy = await _verifyConnectionQuality();
        if (!healthy) {
          _connectionHealthFailures++;
          if (_connectionHealthFailures >= 2) {
            _stopConnectionHealthMonitor();
            _setError(
              'Connection dropped; switching to another server...',
            );
            await _handleFailedServer(
              config,
              'Health monitor detected repeated failures',
            );
          }
        } else {
          _connectionHealthFailures = 0;
        }
      },
    );
  }

  void _stopConnectionHealthMonitor() {
    _connectionHealthTimer?.cancel();
    _connectionHealthTimer = null;
    _healthMonitorConfigId = null;
    _connectionHealthFailures = 0;
  }

  Future<void> _preselectBestServer() async {
    if (_isPreconfiguring) return;
    _isPreconfiguring = true;
    notifyListeners();
    try {
      final result = await AutoSelectUtil.runAutoSelect(
        _configs,
        _v2rayService,
        fastMode: true,
      ).timeout(const Duration(seconds: 5), onTimeout: () {
        return AutoSelectResult(
          selectedConfig: null,
          bestPing: null,
          errorMessage: 'timeout',
        );
      });

      if (result.selectedConfig != null) {
        _preselectedConfigId = result.selectedConfig!.id;
      } else if (_configs.isNotEmpty) {
        _preselectedConfigId = _configs.first.id;
      }
    } catch (_) {
      if (_configs.isNotEmpty) {
        _preselectedConfigId = _configs.first.id;
      }
    } finally {
      _isPreconfiguring = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('App lifecycle state changed: $state');

    // Handle app lifecycle changes
    if (state == AppLifecycleState.resumed) {
      // When app is resumed, check connection status after a delay
      // This allows the VPN connection time to stabilize
      Future.delayed(const Duration(milliseconds: 500), () async {
        print('App resumed, checking VPN status...');
        // CRITICAL FIX: Enhanced synchronization with actual VPN service state when app resumes
        await _enhancedSyncWithVpnServiceState();
        notifyListeners();
      });
    } else if (state == AppLifecycleState.paused) {
      // App is paused, VPN status will be maintained in background
      print('App paused, VPN will continue in background');
    }
  }

  // Method to fetch connection status from the notification
  Future<void> fetchNotificationStatus() async {
    try {
      // Get the actual connection status from the service
      final isActuallyConnected = await _v2rayService.isActuallyConnected();
      final activeConfig = _v2rayService.activeConfig;

      print(
        'Fetching notification status - Connected: $isActuallyConnected, Active config: ${activeConfig?.remark}',
      );

      // Update all configs based on the actual status
      bool statusChanged = false;

      if (activeConfig != null && isActuallyConnected) {
        // VPN is connected, update the matching config
        for (int i = 0; i < _configs.length; i++) {
          bool shouldBeConnected = false;

          // Find the matching config by comparing the server details
          shouldBeConnected =
              _configs[i].fullConfig == activeConfig.fullConfig ||
              (_configs[i].address == activeConfig.address &&
                  _configs[i].port == activeConfig.port);

          if (_configs[i].isConnected != shouldBeConnected) {
            _configs[i].isConnected = shouldBeConnected;
            statusChanged = true;

            if (shouldBeConnected) {
              _selectedConfig = _configs[i];
              print('Updated config ${_configs[i].remark} to connected');
            }
          }
        }
      } else {
        // VPN is not connected, clear all connected states
        for (int i = 0; i < _configs.length; i++) {
          if (_configs[i].isConnected) {
            _configs[i].isConnected = false;
            statusChanged = true;
            print('Updated config ${_configs[i].remark} to disconnected');
          }
        }
        if (statusChanged) {
          _selectedConfig = null;
        }
      }

      if (statusChanged) {
        await _v2rayService.saveConfigs(_configs);
        notifyListeners();
        print('Connection status updated from notification check');
      }
    } catch (e) {
      print('Error fetching notification status: $e');
      // Don't change connection state on errors
    }
  }

  // Method to manually check connection status
  Future<void> checkConnectionStatus() async {
    try {
      // Only check status if we think we're connected
      if (_v2rayService.activeConfig != null) {
        // Force check the actual connection status
        final isActuallyConnected = await _v2rayService.isActuallyConnected();

        // Only update UI if we have a definitive negative status
        // Don't disconnect just because we can't verify the connection
        if (isActuallyConnected == false) {
          // Explicitly check for false, not just !isActuallyConnected
          // Update our configs based on the actual status
          bool hadConnectedConfig = false;
          for (int i = 0; i < _configs.length; i++) {
            if (_configs[i].isConnected) {
              _configs[i].isConnected = false;
              hadConnectedConfig = true;
            }
          }

          if (hadConnectedConfig) {
            _selectedConfig = null;
            await _v2rayService.saveConfigs(_configs);
            notifyListeners();
          }
        }
      }
    } catch (e) {
      print('Error checking connection status: $e');
      // Don't change connection state on errors
    }
  }

  Future<List<V2RayConfig>> parseSubscriptionContent(String content) async {
    return await _v2rayService.parseSubscriptionContent(content);
  }

  // NEW: Method to clear subscription configs to force fresh updates
  Future<void> _clearSubscriptionConfigs() async {
    try {
      // Only clear subscription configs if we have subscriptions loaded
      if (_subscriptions.isNotEmpty) {
        // Get all subscription config IDs
        final subscriptionConfigIds = <String>{};
        for (var subscription in _subscriptions) {
          subscriptionConfigIds.addAll(subscription.configIds);
        }

        // Remove all subscription configs from the configs list
        _configs.removeWhere((c) => subscriptionConfigIds.contains(c.id));

        // Clear config IDs from all subscriptions
        for (int i = 0; i < _subscriptions.length; i++) {
          _subscriptions[i] = _subscriptions[i].copyWith(configIds: []);
        }

        // Save the cleared state
        await _v2rayService.saveConfigs(_configs);
        await _v2rayService.saveSubscriptions(_subscriptions);

        print(
          'Cleared ${subscriptionConfigIds.length} subscription configs for fresh update',
        );
      }
    } catch (e) {
      print('Error clearing subscription configs: $e');
    }
  }

  Future<void> addSubscriptionFromFile(
    String name,
    List<V2RayConfig> configs,
  ) async {
    _setLoading(true);
    _errorMessage = '';
    try {
      // Add configs and display them immediately
      _configs.addAll(configs);

      final newConfigIds = configs.map((c) => c.id).toList();

      // Create subscription with a special indicator for file-based subscriptions
      final subscription = Subscription(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        url:
            'file://subscription', // Special indicator for file-based subscriptions
        lastUpdated: DateTime.now(),
        configIds: newConfigIds,
      );

      _subscriptions.add(subscription);

      // Save both configs and subscription
      await _v2rayService.saveConfigs(_configs);
      await _v2rayService.saveSubscriptions(_subscriptions);

      // Update UI after everything is saved
      notifyListeners();
    } catch (e) {
      String errorMsg = 'Failed to add subscription from file';

      // Provide more specific error messages
      if (e.toString().contains('No valid servers')) {
        errorMsg = 'No valid servers found in file';
      } else {
        errorMsg = 'Failed to add subscription from file: ${e.toString()}';
      }

      _setError(errorMsg);
    } finally {
      _setLoading(false);
    }
  }
}
