import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescue_app/main.dart';

const _storageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Backs flutter_secure_storage with an in-memory map so AuthProvider and
/// ApiConfigStore work in widget tests.
void mockSecureStorage(Map<String, String> initial) {
  final store = Map<String, String>.from(initial);
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storageChannel, (call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    switch (call.method) {
      case 'read':
        return store[args['key'] as String];
      case 'readAll':
        return store;
      case 'write':
        store[args['key'] as String] = args['value'] as String;
        return null;
      case 'delete':
        store.remove(args['key'] as String);
        return null;
      case 'deleteAll':
        store.clear();
        return null;
      case 'containsKey':
        return store.containsKey(args['key'] as String);
      default:
        return null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('no credentials: RootGate lands on the login screen',
      (tester) async {
    mockSecureStorage({});
    await tester.pumpWidget(const RescueApp());
    await tester.pump(); // AuthProvider.load()
    await tester.pump();

    expect(find.text('Rescue Mesh'), findsOneWidget);
    expect(find.text('LOG IN'), findsOneWidget);
    expect(find.textContaining('Join any RESCUE_x WiFi'), findsOneWidget);
    // break-glass path is reachable but labeled
    expect(find.textContaining('break-glass admin key'), findsOneWidget);

    // validation: empty submit shows field errors, no crash
    await tester.tap(find.text('LOG IN'));
    await tester.pump();
    expect(find.text('Personnel ID is required'), findsOneWidget);
    expect(find.text('Enter the PIN you were issued'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose providers/timers
  });

  testWidgets('valid stored session: RootGate goes straight to the app',
      (tester) async {
    final exp =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    mockSecureStorage({
      'session_json':
          '{"token":"t.x","expires_at":$exp,"personnel_id":"R-014","role":"RESCUE_TEAM","name":"Bob"}',
    });
    await tester.pumpWidget(const RescueApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('HQ Uplink'), findsOneWidget);
    expect(find.text('Announcements'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expired stored session: back to login', (tester) async {
    final exp =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10;
    mockSecureStorage({
      'session_json':
          '{"token":"t.x","expires_at":$exp,"personnel_id":"R-014","role":"RESCUE_TEAM","name":"Bob"}',
    });
    await tester.pumpWidget(const RescueApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('LOG IN'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('break-glass key stored: app opens in admin mode',
      (tester) async {
    mockSecureStorage({'rescue_api_key': 'bg_key_123'});
    await tester.pumpWidget(const RescueApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('Requests'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
