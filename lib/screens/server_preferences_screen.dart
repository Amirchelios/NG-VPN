import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/v2ray_config.dart';
import '../providers/v2ray_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';

class ServerPreferencesScreen extends StatelessWidget {
  const ServerPreferencesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.primaryDark,
        appBar: AppBar(
          title: Text(context.tr('tools.manage_servers')),
          backgroundColor: AppTheme.primaryDark,
          bottom: TabBar(
            indicatorColor: AppTheme.primaryGreen,
            labelColor: AppTheme.primaryGreen,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: context.tr('tools.liked_servers')),
              Tab(text: context.tr('tools.disliked_servers')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ServerListView(isLikedList: true),
            _ServerListView(isLikedList: false),
          ],
        ),
      ),
    );
  }
}

class _ServerListView extends StatefulWidget {
  final bool isLikedList;

  const _ServerListView({required this.isLikedList});

  @override
  State<_ServerListView> createState() => _ServerListViewState();
}

class _ServerListViewState extends State<_ServerListView> {
  late Future<List<V2RayConfig>> _serversFuture;

  @override
  void initState() {
    super.initState();
    _serversFuture = _loadServers();
  }

  Future<List<V2RayConfig>> _loadServers() async {
    // Use a non-listening provider here to avoid rebuild loops with FutureBuilder
    final provider = Provider.of<V2RayProvider>(context, listen: false);
    final allConfigs = provider.configs;
    final Set<String> serverIds;

    if (widget.isLikedList) {
      serverIds = await provider.getLikedServerIds();
    } else {
      serverIds = await provider.getDislikedServerIds();
    }

    return allConfigs.where((config) => serverIds.contains(config.id)).toList();
  }

  void _refreshList() {
    setState(() {
      _serversFuture = _loadServers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<V2RayProvider>();

    return FutureBuilder<List<V2RayConfig>>(
      future: _serversFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final servers = snapshot.data ?? [];

        if (servers.isEmpty) {
          return Center(
            child: Text(
              context.tr('tools.no_servers_found'),
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8.0),
          itemCount: servers.length,
          itemBuilder: (context, index) {
            final server = servers[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppTheme.cardDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                title: Text(
                  server.remark,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${server.address}:${server.port}',
                  style: const TextStyle(color: AppTheme.textGrey),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  tooltip: context.tr('tools.remove_preference'),
                  onPressed: () async {
                    await provider.clearServerPreferenceById(server.id);
                    _refreshList();
                    if (mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('tools.server_preference_cleared')),
                          backgroundColor: AppTheme.primaryGreen,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
