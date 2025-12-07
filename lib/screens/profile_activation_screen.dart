import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_profile.dart';
import '../providers/profile_provider.dart';
import '../services/profile_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/error_snackbar.dart';
import 'main_navigation_screen.dart';
import 'qr_scanner_screen.dart';

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
          _error =
              'کد وارد شده یافت نشد. لطفاً با پشتیبانی تماس بگیرید.';
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

  Future<void> _openSupport() async {
    final uri = Uri.parse('https://t.me/nexg0');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ErrorSnackbar.show(
          context,
          'امکان باز کردن تلگرام وجود ندارد.',
        );
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
              'برای استفاده از برنامه لازم است پروفایل اختصاصی خود را فعال کنید. '
              'کد ردیم را از پشتیبانی دریافت کنید و در کادر زیر وارد نمایید.',
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
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  tooltip: 'چسباندن از کلیپ‌بورد',
                  onPressed: _isLoading
                      ? null
                      : () async {
                          final data =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null) {
                            _codeController.text = data!.text!.trim();
                            setState(() {
                              _error = null;
                            });
                          }
                        },
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final result = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const QrScannerScreen(),
                        ),
                      );
                      if (result != null && result.isNotEmpty) {
                        setState(() {
                          _codeController.text = result.trim();
                          _error = null;
                        });
                      }
                    },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('اسکن QR'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
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
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _openSupport,
              icon: const Icon(Icons.support_agent, color: Colors.white70),
              label: const Text(
                'ارتباط با پشتیبان (تلگرام)',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
