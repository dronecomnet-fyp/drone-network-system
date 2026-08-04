/// The sign-in QR decoder (field backlog #17).
///
/// Worth testing on its own because a rescuer scanning the wrong barcode is
/// the NORMAL case, not the exceptional one: shipping labels, equipment
/// asset tags and food packaging all carry codes, and every one of them
/// must produce a readable message instead of a crash on the login screen.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescue_app/providers/auth_provider.dart';

String makeCode({String id = 'RESC-01', String pin = '481920'}) {
  return base64Url.encode(utf8.encode(jsonEncode({
    'i': id,
    'p': pin,
    'e': 'ZW5yb2xtZW50LWJsb2I=',
  })));
}

void main() {
  test('a real code yields the id, the pin and the enrolment record', () {
    final decoded = decodeSigninCode(makeCode());
    expect(decoded, isNotNull);
    expect(decoded!.personnelId, 'RESC-01');
    expect(decoded.pin, '481920');
    expect(decoded.enrolment, 'ZW5yb2xtZW50LWJsb2I=');
  });

  test('surrounding whitespace from a scanner is tolerated', () {
    expect(decodeSigninCode('  ${makeCode()}\n'), isNotNull);
  });

  test('a shipping label barcode is rejected, not crashed on', () {
    expect(decodeSigninCode('1Z999AA10123456784'), isNull);
    expect(decodeSigninCode('https://example.com/tracking'), isNull);
    expect(decodeSigninCode(''), isNull);
  });

  test('valid base64 that is not our JSON is rejected', () {
    expect(decodeSigninCode(base64Url.encode(utf8.encode('hello'))), isNull);
  });

  test('a code missing the pin is rejected rather than half used', () {
    final partial = base64Url.encode(utf8.encode(jsonEncode({
      'i': 'RESC-01',
      'e': 'ZW5yb2xtZW50',
    })));
    expect(decodeSigninCode(partial), isNull);
  });
}
