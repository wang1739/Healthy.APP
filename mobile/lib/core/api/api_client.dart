import 'package:dio/dio.dart';
import 'package:healthy/core/api/api_config.dart';
import 'package:healthy/core/storage/token_store.dart';

class ApiClient {
  ApiClient({Dio? dio, TokenStore? tokenStore})
    : _dio = dio ?? Dio(_options()),
      _tokenStore = tokenStore ?? TokenStore();

  static final instance = ApiClient();

  final Dio _dio;
  final TokenStore _tokenStore;
  String? _accessToken;
  Future<bool>? _refreshing;

  static BaseOptions _options() => BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    headers: {'Content-Type': 'application/json'},
  );

  Future<bool> ping() async {
    final response = await _dio.get<Map<String, dynamic>>('/system/ping');
    return response.statusCode == 200 && response.data?['status'] == 'ok';
  }

  Future<String?> sendCode(String phone) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/sms/send',
      data: {'phone': phone, 'purpose': 'LOGIN'},
    );
    return response.data?['debugCode'] as String?;
  }

  Future<LoginResult> smsLogin({
    required String phone,
    required String code,
    required String deviceName,
    String? password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/sms/login',
      data: {
        'phone': phone,
        'code': code,
        'deviceName': deviceName,
        if (password != null && password.isNotEmpty) 'password': password,
        'acceptedTerms': true,
      },
    );
    return _acceptLogin(response.data!);
  }

  Future<LoginResult> passwordLogin({
    required String phone,
    required String password,
    required String deviceName,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/password/login',
      data: {'phone': phone, 'password': password, 'deviceName': deviceName},
    );
    return _acceptLogin(response.data!);
  }

  Future<LoginResult?> restoreSession() async {
    final refreshed = await _refresh();
    if (!refreshed) return null;
    final account = await getAccount();
    return LoginResult(
      profileComplete: account['profileComplete'] == true,
      phone: account['phone'] as String?,
    );
  }

  Future<Map<String, dynamic>> getAccount() async {
    final response = await _authorized('GET', '/account');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> profileCompleteness() async {
    final response = await _authorized('GET', '/profile/completeness');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> saveProfile(Map<String, dynamic> data) async {
    await _authorized('PUT', '/profile', data: data);
  }

  Future<void> addMeasurement(Map<String, dynamic> data) async {
    await _authorized('POST', '/profile/measurements', data: data);
  }

  Future<void> savePreferences(Map<String, dynamic> data) async {
    await _authorized('PUT', '/profile/preferences', data: data);
  }

  Future<Map<String, dynamic>> saveRisk(Map<String, dynamic> data) async {
    final response = await _authorized(
      'POST',
      '/profile/risk-assessment',
      data: data,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> logout({bool allDevices = false}) async {
    try {
      if (_accessToken != null) {
        await _authorized(
          'POST',
          '/auth/logout',
          data: {'allDevices': allDevices},
        );
      }
    } finally {
      _accessToken = null;
      await _tokenStore.clear();
    }
  }

  Future<Response<dynamic>> _authorized(
    String method,
    String path, {
    Object? data,
  }) async {
    try {
      return await _dio.request<dynamic>(
        path,
        data: data,
        options: Options(method: method, headers: _authHeaders),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 401 || !await _refresh()) rethrow;
      return _dio.request<dynamic>(
        path,
        data: data,
        options: Options(method: method, headers: _authHeaders),
      );
    }
  }

  Map<String, String> get _authHeaders => {
    if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
  };

  Future<bool> _refresh() {
    final active = _refreshing;
    if (active != null) return active;
    final operation = _performRefresh();
    _refreshing = operation;
    return operation.whenComplete(() => _refreshing = null);
  }

  Future<bool> _performRefresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) return false;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/token/refresh',
        data: {'refreshToken': refreshToken},
      );
      await _acceptLogin(response.data!);
      return true;
    } on DioException {
      _accessToken = null;
      await _tokenStore.clear();
      return false;
    }
  }

  Future<LoginResult> _acceptLogin(Map<String, dynamic> data) async {
    _accessToken = data['accessToken'] as String;
    await _tokenStore.saveRefreshToken(data['refreshToken'] as String);
    return LoginResult(profileComplete: data['profileComplete'] == true);
  }

  static String errorMessage(Object error) {
    if (error is FormatException) return error.message;
    if (error is DioException && error.response?.data is Map) {
      return (error.response!.data as Map)['message']?.toString() ?? '请求失败';
    }
    return '网络连接失败，请稍后重试';
  }
}

class LoginResult {
  const LoginResult({required this.profileComplete, this.phone});

  final bool profileComplete;
  final String? phone;
}
