import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/profile_provider.dart';
import '../services/profile_manager.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import 'main_navigation_screen.dart';

class ProfileActivationScreen extends StatefulWidget {
  const ProfileActivationScreen({super.key});

  @override
  State<ProfileActivationScreen> createState() =>
      _ProfileActivationScreenState();
}

class _ProfileActivationScreenState extends State<ProfileActivationScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _error = 'لطفاً کد فعال‌سازی را وارد کنید.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final UserProfile? profile =
          await ProfileManager.fetchProfileByCode(code);
      if (profile == null) {
        setState(() {
          _error = 'کد وارد شده یافت نشد. لطفاً با پشتیبانی تماس بگیرید.';
        });
      } else if (profile.isExpired) {
        setState(() {
          _error = 'این پروفایل منقضی شده است. لطفاً تمدید انجام دهید.';
        });
      } else {
        if (!mounted) return;
        final provider = context.read<ProfileProvider>();
        await provider.setProfile(profile);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const MainNavigationScreen(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _error = 'خطا در دریافت اطلاعات: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryDark,
      appBar: AppBar(
        title: const Text('فعال‌سازی پروفایل'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'برای استفاده از برنامه لازم است پروفایل اختصاصی خود را وارد کنید. '
              'کد ردیم را از پشتیبانی دریافت نمایید و در کادر زیر وارد کنید.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              enabled: !_isLoading,
              decoration: InputDecoration(
                labelText: 'کد فعال‌سازی',
                filled: true,
                fillColor: AppTheme.cardDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      )
                    : const Text(
                        'فعال‌سازی',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
