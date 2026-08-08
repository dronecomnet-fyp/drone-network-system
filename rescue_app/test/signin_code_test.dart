/// The sign-in QR decoder (field backlog #17).
///
/// Worth testing on its own because a rescuer scanning the wrong barcode is
/// the NORMAL case, not the exceptional one: shipping labels, equipment
/// asset tags and food packaging all carry codes, and every one of them
/// must produce a readable message instead of a crash on the login screen.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescue_app/providers/auth_provider.dart';

/// The legacy uncompressed shape, still accepted so a code issued
/// before compression keeps working.
String makeLegacyCode({String id = 'RESC-01', String pin = '481920'}) {
  return base64Url.encode(utf8.encode(jsonEncode({
    'i': id,
    'p': pin,
    'e': 'ZW5yb2xtZW50LWJsb2I=',
  })));
}

/// What the GCC issues now: the record as an object, deflated, prefixed
/// with Z. Compressed because the uncompressed form needed a QR too dense
/// for a phone camera to read.
String makeCode({String id = 'RESC-01', String pin = '481920'}) {
  final payload = utf8.encode(jsonEncode({
    'i': id,
    'p': pin,
    'e': {
      'personnel_id': id,
      'name': 'A. Perera',
      'role': 'RESCUE_TEAM',
      'pin_salt': 'a' * 32,
      'pin_hash': 'b' * 64,
      'pin_algo': 'pbkdf2_sha256',
      'pin_iterations': 200000,
      'issued_at': '2026-08-09T10:00:00.000000Z',
      'expires_at': '2026-08-16T10:00:00.000000Z',
      'status': 'ACTIVE',
      'updated_at': '2026-08-09T10:00:00.000000Z',
      'signature': 'c' * 64,
    },
  }));
  return 'Z' + base64Url.encode(ZLibCodec().encode(payload));
}

void main() {
  test('a real code yields the id, the pin and the enrolment record', () {
    final decoded = decodeSigninCode(makeCode());
    expect(decoded, isNotNull);
    expect(decoded!.personnelId, 'RESC-01');
    expect(decoded.pin, '481920');
    // The record travelled as an object and was re-encoded into the blob
    // POST /enrol expects.
    final rebuilt = jsonDecode(utf8.decode(base64Url.decode(decoded.enrolment)));
    expect(rebuilt['personnel_id'], 'RESC-01');
    expect(rebuilt['signature'], 'c' * 64);
  });

  test('a code issued before compression still works', () {
    final decoded = decodeSigninCode(makeLegacyCode());
    expect(decoded, isNotNull);
    expect(decoded!.enrolment, 'ZW5yb2xtZW50LWJsb2I=');
  });

  test('the compressed code is small enough for a scannable QR', () {
    // Over about 600 characters the QR needs so many modules that a
    // phone camera cannot resolve them at a sane on-screen size. This is
    // the regression guard for the bug where nobody could scan it.
    final code = makeCode();
    expect(code.length, lessThan(600),
        reason: 'sign-in code grew back to an unscannable size');
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
