import 'package:flutter/material.dart';
import 'package:proxycloud/services/ping_service.dart';
import 'package:proxycloud/services/v2ray_service.dart';

class PingTestScreen extends StatefulWidget {
  const PingTestScreen({Key? key}) : super(key: key);

  @override
  State<PingTestScreen> createState() => _PingTestScreenState();
}

class _PingTestScreenState extends State<PingTestScreen> {
  final TextEditingController _hostController = TextEditingController(
    text: 'google.com',
  );
  final TextEditingController _portController = TextEditingController(
    text: '80',
  );

  PingResult? _lastPingResult;
  bool _isLoading = false;
  String _networkType = 'Unknown';

  List<PingResult> _continuousPingResults = [];
  Stream<PingResult>? _continuousPingStream;

  final V2RayService _v2rayService = V2RayService();

  @override
  void initState() {
    super.initState();
    _loadNetworkType();
  }

  Future<void> _loadNetworkType() async {
    final networkType = await NativePingService.getNetworkType();
    setState(() {
      _networkType = networkType;
    });
  }

  Future<void> _singlePing() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _lastPingResult = null;
    });

    try {
      final host = _hostController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 80;

      if (host.isEmpty) {
        _showError('Please enter a host');
        return;
      }

      final result = await NativePingService.pingHost(
        host: host,
        port: port,
        timeoutMs: 8000,
        useIcmp: true,
        useTcp: true,
        useCache: false,
      );

      setState(() {
        _lastPingResult = result;
      });
    } catch (e) {
      _showError('Ping failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testConnectivity() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await NativePingService.testConnectivity();

      _showResultsDialog('Connectivity Test Results', results);
    } catch (e) {
      _showError('Connectivity test failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startContinuousPing() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 80;

    if (host.isEmpty) {
      _showError('Please enter a host');
      return;
    }

    setState(() {
      _continuousPingResults.clear();
      _continuousPingStream = NativePingService.startContinuousPing(
        host: host,
        port: port,
        interval: const Duration(seconds: 3),
      );
    });
  }

  void _stopContinuousPing() {
    setState(() {
      _continuousPingStream = null;
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showResultsDialog(String title, Map<String, PingResult> results) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final entry = results.entries.elementAt(index);
              final result = entry.value;

              return ListTile(
                title: Text(entry.key),
                subtitle: result.success
                    ? Text('${result.latency}ms (${result.method})')
                    : Text('Failed: ${result.error}'),
                leading: Icon(
                  result.success ? Icons.check_circle : Icons.error,
                  color: result.success ? Colors.green : Colors.red,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Native Ping Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Network info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Network Information',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Network Type: $_networkType'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Host input
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host',
                border: OutlineInputBorder(),
                hintText: 'google.com',
              ),
            ),

            const SizedBox(height: 16),

            // Port input
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
                hintText: '80',
              ),
              keyboardType: TextInputType.number,
            ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _singlePing,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Single Ping'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _testConnectivity,
                    child: const Text('Test Connectivity'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Continuous ping buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _continuousPingStream == null
                        ? _startContinuousPing
                        : null,
                    child: const Text('Start Continuous'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _continuousPingStream != null
                        ? _stopContinuousPing
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Stop Continuous'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Single ping result
            if (_lastPingResult != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Ping Result',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _lastPingResult!.success
                                ? Icons.check_circle
                                : Icons.error,
                            color: _lastPingResult!.success
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _lastPingResult!.success
                                ? Text(
                                    '${_lastPingResult!.latency}ms (${_lastPingResult!.method})',
                                  )
                                : Text('Failed: ${_lastPingResult!.error}'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Continuous ping results
            if (_continuousPingStream != null)
              Expanded(
                child: Card(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Continuous Ping Results',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Expanded(
                        child: StreamBuilder<PingResult>(
                          stream: _continuousPingStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              _continuousPingResults.insert(0, snapshot.data!);

                              // Keep only last 20 results
                              if (_continuousPingResults.length > 20) {
                                _continuousPingResults.removeRange(
                                  20,
                                  _continuousPingResults.length,
                                );
                              }
                            }

                            return ListView.builder(
                              itemCount: _continuousPingResults.length,
                              itemBuilder: (context, index) {
                                final result = _continuousPingResults[index];
                                final time =
                                    DateTime.fromMillisecondsSinceEpoch(
                                      result.timestamp,
                                    );

                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    result.success
                                        ? Icons.check_circle
                                        : Icons.error,
                                    color: result.success
                                        ? Colors.green
                                        : Colors.red,
                                    size: 16,
                                  ),
                                  title: result.success
                                      ? Text(
                                          '${result.latency}ms (${result.method})',
                                        )
                                      : Text('Failed: ${result.error}'),
                                  subtitle: Text(
                                    '${time.hour}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}',
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _stopContinuousPing();
    super.dispose();
  }
}
