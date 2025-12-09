import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class ProfileManager {
  static const String profilePrefsKey = 'user_profile';
  // GitHub Pages URL (cache-busted via ?ts=... when fetching)
  static const String profileUrl =
      'https://amirchelios.github.io/NG_manager/user.json';

  static Future<UserProfile?> fetchProfileByCode(String code) async {
    final response = await http
        .get(Uri.parse(profileUrl))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Failed to load profile data (${response.statusCode})');
    }

    final dynamic data = json.decode(response.body);
    if (data is Map<String, dynamic> && data['users'] is List) {
      final List<dynamic> users = data['users'];
      for (final user in users) {
        if (user is Map<String, dynamic>) {
          final redeemCode = user['redeem_code']?.toString().trim();
          if (redeemCode != null &&
              redeemCode.toLowerCase() == code.trim().toLowerCase()) {
            return UserProfile.fromRemoteJson(user);
          }
        }
      }
    }
    return null;
  }

  static Future<UserProfile?> loadSavedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return UserProfile.fromStorageString(prefs.getString(profilePrefsKey));
  }

  static Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(profilePrefsKey, profile.toStorageString());
  }

  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(profilePrefsKey);
  }
}
