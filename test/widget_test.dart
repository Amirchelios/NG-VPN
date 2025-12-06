// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxycloud/providers/language_provider.dart';

import 'package:proxycloud/main.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    // Create a mock language provider
    final languageProvider = LanguageProvider();
    await languageProvider.initialize();

    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(
      privacyAccepted: false,
      languageProvider: languageProvider,
    ));

    // Verify that the privacy screen loads
    expect(find.text('Privacy Policy'), findsOneWidget);
  });
}
