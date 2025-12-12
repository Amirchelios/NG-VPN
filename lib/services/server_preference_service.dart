import 'package:shared_preferences/shared_preferences.dart';

/// A service to manage user preferences for servers (like/dislike).
/// This helps in prioritizing connections and avoiding bad servers.
class ServerPreferenceService {
  static const String _likedServersKey = 'liked_servers';
  static const String _dislikedServersKey = 'disliked_servers';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Saves a server to the liked list.
  /// If it was disliked, it will be removed from the disliked list.
  Future<void> likeServer(String serverId) async {
    final prefs = await _prefs;
    final liked = await getLikedServers();
    final disliked = await getDislikedServers();

    liked.add(serverId);
    disliked.remove(serverId);

    await prefs.setStringList(_likedServersKey, liked.toList());
    await prefs.setStringList(_dislikedServersKey, disliked.toList());
  }

  /// Saves a server to the disliked list.
  /// If it was liked, it will be removed from the liked list.
  Future<void> dislikeServer(String serverId) async {
    final prefs = await _prefs;
    final liked = await getLikedServers();
    final disliked = await getDislikedServers();

    disliked.add(serverId);
    liked.remove(serverId);

    await prefs.setStringList(_dislikedServersKey, disliked.toList());
    await prefs.setStringList(_likedServersKey, liked.toList());
  }

  /// Removes any preference (like/dislike) for a server.
  Future<void> clearServerPreference(String serverId) async {
    final prefs = await _prefs;
    final liked = await getLikedServers();
    final disliked = await getDislikedServers();

    liked.remove(serverId);
    disliked.remove(serverId);

    await prefs.setStringList(_likedServersKey, liked.toList());
    await prefs.setStringList(_dislikedServersKey, disliked.toList());
  }

  /// Returns a set of liked server IDs.
  Future<Set<String>> getLikedServers() async {
    final prefs = await _prefs;
    return prefs.getStringList(_likedServersKey)?.toSet() ?? {};
  }

  /// Returns a set of disliked server IDs.
  Future<Set<String>> getDislikedServers() async {
    final prefs = await _prefs;
    return prefs.getStringList(_dislikedServersKey)?.toSet() ?? {};
  }

  /// Checks if a server is liked.
  Future<bool> isLiked(String serverId) async {
    final liked = await getLikedServers();
    return liked.contains(serverId);
  }

  /// Checks if a server is disliked.
  Future<bool> isDisliked(String serverId) async {
    final disliked = await getDislikedServers();
    return disliked.contains(serverId);
  }
}
