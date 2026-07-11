/// Shared models and API client for the rescue mesh apps (file 04).
///
/// Pure Dart (no Flutter dependency) so the same package serves the GCC
/// desktop app, the rescue personnel app, and the emergency app, and can
/// be tested with `dart test` against a live backend node.
library;

export 'src/models.dart';
export 'src/client.dart';
