import 'package:dio/dio.dart';
import 'package:healthy/core/api/api_config.dart';

class ApiClient {
  ApiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: ApiConfig.baseUrl,
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 3),
            ),
          );

  final Dio _dio;

  Future<bool> ping() async {
    final response = await _dio.get<Map<String, dynamic>>('/system/ping');
    return response.statusCode == 200 && response.data?['status'] == 'ok';
  }
}
