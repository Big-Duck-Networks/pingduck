import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/constants/app_version.dart';
import 'package:pingduck_app/features/account/presentation/about_contacts_screen.dart';

void main() {
  testWidgets('AboutContactsScreen renders all Fing-style contact rows', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AboutContactsScreen(),
      ),
    );

    // App header & version
    expect(find.text('About & contacts'), findsOneWidget);
    expect(find.text('PingDuck'), findsOneWidget);
    expect(find.text(AppVersion.display), findsOneWidget);

    // Action rows
    expect(find.text('Rate PingDuck on the Store'), findsOneWidget);
    expect(find.text('Rate and review this App on the Store'), findsOneWidget);
    expect(find.text('Release notes'), findsOneWidget);
    expect(find.text('Show the new content of this version'), findsOneWidget);
    expect(find.text('Website'), findsOneWidget);
    expect(find.text('Visit PingDuck website.'), findsOneWidget);
    expect(find.text('Tell a friend'), findsOneWidget);
    expect(find.text('Share PingDuck with your friends on email or social networks.'), findsOneWidget);

    // Footer
    expect(find.text('Third-party notices & licenses'), findsOneWidget);
    expect(find.text('© ${DateTime.now().year} Big Duck Networks. All rights reserved.'), findsOneWidget);
  });

  testWidgets('tapping Release notes shows the release notes sheet', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AboutContactsScreen(),
      ),
    );

    await tester.tap(find.text('Release notes'));
    await tester.pumpAndSettle();

    expect(find.text('RELEASE NOTES'), findsOneWidget);
    expect(find.text('Version ${AppVersion.display}'), findsOneWidget);
    expect(find.text('Smart Device & OS Recognition'), findsOneWidget);
    expect(find.text('One-Tap Confirmation'), findsOneWidget);
    expect(find.text('Deep Hardware Inspector'), findsOneWidget);

    // Close button dismisses
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    expect(find.text('RELEASE NOTES'), findsNothing);
  });
}
