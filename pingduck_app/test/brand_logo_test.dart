import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/features/recognition/brand_logo.dart';

void main() {
  testWidgets('all bundled brand logos render valid SVG without throwing', (tester) async {
    final logoDir = Directory('assets/logos');
    final svgFiles = logoDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.svg'))
        .toList();

    expect(svgFiles, isNotEmpty);

    for (final file in svgFiles) {
      final content = file.readAsStringSync();
      expect(content.startsWith('<svg'), isTrue, reason: '${file.path} must start with <svg');
      expect(content, isNot(contains("Couldn't find the requested file")), reason: '${file.path} must not be a 404 response');

      // Verify it mounts and renders in flutter_svg without throwing
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SvgPicture.file(file),
          ),
        ),
      );
    }
  });

  test('BrandLogo.forName returns non-null logo for known brands and OS names', () {
    expect(BrandLogo.forName('Apple'), isNotNull);
    expect(BrandLogo.forName('Windows'), isNotNull);
    expect(BrandLogo.forName('Amazon'), isNotNull);
    expect(BrandLogo.forName('Nintendo'), isNotNull);
    expect(BrandLogo.forName('iPadOS'), isNotNull);
    expect(BrandLogo.forName('UnknownDeviceXYZ'), isNull);
  });
}
