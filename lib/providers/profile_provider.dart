import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../services/profile_manager.dart';

class ProfileProvider extends ChangeNotifier {
  UserProfile? _profile;
  bool _isLoading = true;

  ProfileProvider() {
    _loadProfile();
  }

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;

  bool get hasValidProfile =>
      _profile != null && !_profile!.isExpired && _profile!.code.isNotEmpty;

  Future<void> _loadProfile() async {
    _isLoading = true;
    notifyListeners();
    _profile = await ProfileManager.loadSavedProfile();
    if (_profile?.isExpired == true) {
      await ProfileManager.clearProfile();
      _profile = null;
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (_profile == null || _profile!.code.isEmpty) return;
    _isLoading = true;
    notifyListeners();
    try {
      final fresh =
          await ProfileManager.fetchProfileByCode(_profile!.code.trim());
      if (fresh != null) {
        _profile = fresh;
        await ProfileManager.saveProfile(fresh);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setProfile(UserProfile profile) async {
    _profile = profile;
    await ProfileManager.saveProfile(profile);
    notifyListeners();
  }

  Future<void> clearProfile() async {
    _profile = null;
    await ProfileManager.clearProfile();
    notifyListeners();
  }
}
