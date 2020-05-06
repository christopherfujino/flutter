// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dev_tools/roll_dev.dart';
import './common.dart';

void main() {
  group('parseFullTag', () {
    test('returns match on valid version input', () {
      final List<String> validTags = <String>[
        '1.2.3-1.2.pre-3-gabc123',
        '10.2.30-12.22.pre-45-gabc123',
        '1.18.0-0.0.pre-0-gf0adb240a',
        '2.0.0-1.99.pre-45-gf0adb240a',
        '12.34.56-78.90.pre-12-g9db2703a2',
        '0.0.1-0.0.pre-1-g07601eb95ff82f01e870566586340ed2e87b9cbb',
        '958.80.144-6.224.pre-7803-g06e90',
      ];
      for (final String validTag in validTags) {
        final Match match = parseFullTag(validTag);
        expect(match, isNotNull, reason: 'Expected $validTag to be parsed');
      }
    });

    test('returns null on invalid version input', () {
      final List<String> invalidTags = <String>[
        '1.2.3-dev.1.2-3-gabc123',
        '1.2.3-1.2-3-gabc123',
        'v1.2.3',
        '2.0.0',
        'v1.2.3-1.2.pre-3-gabc123',
        '10.0.1-0.0.pre-gf0adb240a',
        '10.0.1-0.0.pre-3-gggggggggg',
        '1.2.3-1.2.pre-3-abc123',
        '1.2.3-1.2.pre-3-gabc123_',
      ];
      for (final String invalidTag in invalidTags) {
        final Match match = parseFullTag(invalidTag);
        expect(match, null, reason: 'Expected $invalidTag to not be parsed');
      }
    });
  });

  group('getVersionFromParts', () {
    test('returns correct string from valid parts', () {
      List<int> parts = <int>[1, 2, 3, 4, 5];
      expect(getVersionFromParts(parts), '1.2.3-4.5.pre');

      parts = <int>[11, 2, 33, 1, 0];
      expect(getVersionFromParts(parts), '11.2.33-1.0.pre');
    });
  });

  group('incrementLevel()', () {
    const String hash = 'abc123';

    test('throws exception if hash is not valid release candidate', () {
      String level = 'z';

      String version = '1.0.0-0.0.pre-1-g$hash';
      expect(
        () => incrementLevel(version, level),
        throwsException,
        reason: 'should throw because $version should be an exact tag',
      );

      version = '1.2.3';
      expect(
        () => incrementLevel(version, level),
        throwsException,
        reason: 'should throw because $version should be a dev tag, not stable.'
      );

      version = '1.0.0-0.0.pre-1-g$hash';
      level = 'q';
      expect(
        () => incrementLevel(version, level),
        throwsException,
        reason: 'should throw because $level is unsupported',
      );
    });

    test('successfully increments x', () {
      const String level = 'x';

      String version = '1.0.0-0.0.pre';
      expect(incrementLevel(version, level), '2.0.0-0.0.pre');

      version = '10.20.0-40.50.pre';
      expect(incrementLevel(version, level), '11.0.0-0.0.pre');

      version = '1.18.0-3.0.pre';
      expect(incrementLevel(version, level), '2.0.0-0.0.pre');
    });

    test('successfully increments y', () {
      const String level = 'y';

      String version = '1.0.0-0.0.pre';
      expect(incrementLevel(version, level), '1.1.0-0.0.pre');

      version = '10.20.0-40.50.pre';
      expect(incrementLevel(version, level), '10.21.0-0.0.pre');

      version = '1.18.0-3.0.pre';
      expect(incrementLevel(version, level), '1.19.0-0.0.pre');
    });

    test('successfully increments z', () {
      const String level = 'z';

      String version = '1.0.0-0.0.pre';
      expect(incrementLevel(version, level), '1.0.0-1.0.pre');

      version = '10.20.0-40.50.pre';
      expect(incrementLevel(version, level), '10.20.0-41.0.pre');

      version = '1.18.0-3.0.pre';
      expect(incrementLevel(version, level), '1.18.0-4.0.pre');
    });
  });
}
