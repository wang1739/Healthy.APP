import 'package:flutter_test/flutter_test.dart';
import 'package:healthy/core/api/api_config.dart';

void main() {
  test('uses the Android emulator host by default', () {
    expect(ApiConfig.baseUrl, 'http://10.0.2.2:8080/api/v1');
  });
}
