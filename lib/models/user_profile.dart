import 'dart:convert';
import 'package:shamsi_date/shamsi_date.dart';

class UserProfile {
  final String code;
  final String name;
  final String phone;
  final String expiryJalali;
  final DateTime expiryDate;
  final int initialDays;

  UserProfile({
    required this.code,
    required this.name,
    required this.phone,
    required this.expiryJalali,
    required this.expiryDate,
    required this.initialDays,
  });

  factory UserProfile.fromRemoteJson(Map<String, dynamic> json) {
    final expiry = _parseJalali(json['expiry_jalali']?.toString() ?? '');
    final remaining =
        expiry.difference(DateTime.now()).inDays.clamp(0, 10000);
    return UserProfile(
      code: json['redeem_code']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      phone: json['phone']?.toString().trim() ?? '',
      expiryJalali: json['expiry_jalali']?.toString().trim() ?? '',
      expiryDate: expiry,
      initialDays: remaining == 0 ? 1 : remaining,
    );
  }

  factory UserProfile.fromStorageJson(Map<String, dynamic> json) {
    return UserProfile(
      code: json['code'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      expiryJalali: json['expiry_jalali'] as String,
      expiryDate: DateTime.parse(json['expiry_date'] as String),
      initialDays: json['initial_days'] as int,
    );
  }

  Map<String, dynamic> toStorageJson() => {
        'code': code,
        'name': name,
        'phone': phone,
        'expiry_jalali': expiryJalali,
        'expiry_date': expiryDate.toIso8601String(),
        'initial_days': initialDays,
      };

  bool get isExpired => expiryDate.isBefore(DateTime.now());

  int get remainingDays {
    final remaining = expiryDate.difference(DateTime.now()).inDays;
    return remaining < 0 ? 0 : remaining;
  }

  double get remainingProgress {
    if (initialDays <= 0) return 0;
    return remainingDays.clamp(0, initialDays) / initialDays;
  }

  static DateTime _parseJalali(String value) {
    try {
      final parts = value.split(RegExp(r'[-/]'));
      if (parts.length != 3) {
        return DateTime.now();
      }
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      final jalali = Jalali(year, month, day);
      return jalali.toDateTime();
    } catch (_) {
      return DateTime.now();
    }
  }

  static UserProfile? fromStorageString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return UserProfile.fromStorageJson(json.decode(raw));
    } catch (_) {
      return null;
    }
  }

  String toStorageString() => json.encode(toStorageJson());
}
