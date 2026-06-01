// Unit tests for OcpVersion parsing resilience.
//
// These pin the behavior the Versions screen relies on to avoid the
// intermittent "No version data available" blank: a malformed `minor_version`
// must not throw (it's sentinel-excluded by the >= kOcpActiveMinorMinimum
// filter), and one bad row must not discard the whole list.
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/models/ocp_version.dart';

Map<String, dynamic> _row({
  String id = '1',
  String minor = '4.18',
  String stable = '4.18.3',
  String updatedAt = '2026-06-01T00:00:00Z',
}) {
  return {
    'id': id,
    'minor_version': minor,
    'latest_stable': stable,
    'updated_at': updatedAt,
  };
}

void main() {
  group('OcpVersion.fromJson', () {
    test('parses a well-formed row', () {
      final v = OcpVersion.fromJson(_row());
      expect(v.id, '1');
      expect(v.minorVersion, '4.18');
      expect(v.latestStable, '4.18.3');
      expect(v.updatedAt.toUtc(), DateTime.utc(2026, 6, 1));
    });

    test('throws on a malformed row (null required field)', () {
      final bad = _row()..['latest_stable'] = null;
      expect(() => OcpVersion.fromJson(bad), throwsA(anything));
    });
  });

  group('OcpVersion.minorInt', () {
    test('extracts the numeric minor from a normal version', () {
      expect(OcpVersion.fromJson(_row(minor: '4.18')).minorInt, 18);
      expect(OcpVersion.fromJson(_row(minor: '4.9')).minorInt, 9);
      expect(OcpVersion.fromJson(_row(minor: '4.21')).minorInt, 21);
    });

    test('returns -1 for a version without a dot', () {
      expect(OcpVersion.fromJson(_row(minor: '4')).minorInt, -1);
    });

    test('returns -1 for a non-numeric minor', () {
      expect(OcpVersion.fromJson(_row(minor: '4.x')).minorInt, -1);
    });

    test('sentinel is excluded by the active-minor filter', () {
      // The screen filters with `minorInt >= kOcpActiveMinorMinimum`; a
      // malformed row must fall below the threshold rather than throw.
      expect(-1 >= kOcpActiveMinorMinimum, isFalse);
    });
  });

  group('OcpVersion.parseList', () {
    test('parses every row when all are well-formed', () {
      final list = OcpVersion.parseList([
        _row(id: '1', minor: '4.18'),
        _row(id: '2', minor: '4.17'),
      ]);
      expect(list, hasLength(2));
      expect(list.map((v) => v.minorVersion), ['4.18', '4.17']);
    });

    test('skips a malformed row but keeps the valid ones', () {
      final list = OcpVersion.parseList([
        _row(id: '1', minor: '4.18'),
        _row(id: '2')..['latest_stable'] = null, // bad row
        _row(id: '3', minor: '4.16'),
      ]);
      expect(list, hasLength(2));
      expect(list.map((v) => v.id), ['1', '3']);
    });

    test('returns an empty list for an empty input', () {
      expect(OcpVersion.parseList(const []), isEmpty);
    });
  });
}
