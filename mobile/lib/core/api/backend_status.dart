import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthy/core/api/api_client.dart';

enum BackendStatus { connected, unavailable }

final backendStatusProvider = FutureProvider<BackendStatus>((ref) async {
  try {
    return await ApiClient().ping()
        ? BackendStatus.connected
        : BackendStatus.unavailable;
  } catch (_) {
    return BackendStatus.unavailable;
  }
});
