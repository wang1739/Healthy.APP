import 'package:dio/dio.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:healthy/core/api/api_config.dart';
import 'package:healthy/core/storage/token_store.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';
import 'package:healthy/features/activity/domain/activity_data.dart';
import 'package:healthy/features/sleep/domain/sleep_data.dart';
import 'package:healthy/features/today/domain/today_data.dart';

class ApiClient {
  ApiClient({
    Dio? dio,
    TokenStore? tokenStore,
    Future<String> Function()? timezone,
  }) : _dio = dio ?? Dio(_options()),
       _tokenStore = tokenStore ?? TokenStore(),
       _timezone = timezone ?? _deviceTimezone;

  static final instance = ApiClient();

  final Dio _dio;
  final TokenStore _tokenStore;
  final Future<String> Function() _timezone;
  String? _accessToken;
  Future<bool>? _refreshing;

  static BaseOptions _options() => BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    headers: {'Content-Type': 'application/json'},
  );

  static Future<String> _deviceTimezone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

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
    return _acceptLogin(response.data!, phone: phone);
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
    return _acceptLogin(response.data!, phone: phone);
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

  Future<TodayData> getToday(DateTime date) async {
    final response = await _authorized(
      'GET',
      '/today',
      queryParameters: {
        'date': formatLocalDate(date),
        'timezone': await _timezone(),
      },
    );
    return TodayData.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<List<Food>> searchFoods({
    String query = '',
    String scope = 'ALL',
    int limit = 20,
  }) async {
    final response = await _authorized(
      'GET',
      '/foods',
      queryParameters: {'query': query, 'scope': scope, 'limit': limit},
    );
    final data = response.data;
    final items = data is List ? data : (data as Map?)?['items'] as List? ?? [];
    return items
        .map((item) => Food.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<FoodSuggestions> getFoodSuggestions({int limit = 8}) async {
    final response = await _authorized(
      'GET',
      '/foods/suggestions',
      queryParameters: {'limit': limit},
    );
    return FoodSuggestions.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<Food> createCustomFood(Map<String, dynamic> data) async {
    final response = await _authorized('POST', '/foods/custom', data: data);
    return Food.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<NutritionDay> getNutritionDay(DateTime date) =>
      _nutritionRequest('GET', '/nutrition/days/${formatLocalDate(date)}');

  Future<NutritionDay> addNutritionEntry(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) => _nutritionRequest(
    'POST',
    '/nutrition/entries',
    data: data,
    headers: {'Idempotency-Key': idempotencyKey},
  );

  Future<NutritionDay> updateNutritionEntry(
    String id,
    Map<String, dynamic> data,
  ) => _nutritionRequest('PUT', '/nutrition/entries/$id', data: data);

  Future<NutritionDay> deleteNutritionEntry(String id) =>
      _nutritionRequest('DELETE', '/nutrition/entries/$id');

  Future<HydrationDay> getHydrationDay(
    DateTime date, {
    required String timezone,
  }) => _hydrationDayRequest(
    'GET',
    '/hydration/days/${formatLocalDate(date)}',
    queryParameters: {'timezone': timezone},
  );

  Future<HydrationDay> addHydrationEntry(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) => _hydrationDayRequest(
    'POST',
    '/hydration/entries',
    data: data,
    headers: {'Idempotency-Key': idempotencyKey},
  );

  Future<HydrationDay> deleteHydrationEntry(
    String id, {
    required String timezone,
  }) => _hydrationDayRequest(
    'DELETE',
    '/hydration/entries/$id',
    queryParameters: {'timezone': timezone},
  );

  Future<HydrationSettings> getHydrationSettings() =>
      _hydrationSettingsRequest('GET', '/hydration/settings');
  Future<HydrationSettings> updateHydrationSettings(
    Map<String, dynamic> data,
  ) => _hydrationSettingsRequest('PUT', '/hydration/settings', data: data);
  Future<HydrationSettings> adoptPlanHydrationTarget() =>
      _hydrationSettingsRequest(
        'POST',
        '/hydration/settings/adopt-plan-target',
      );

  Future<List<ActivityType>> getActivityTypes({String query = ''}) async {
    final response = await _authorized(
      'GET',
      '/activity/types',
      queryParameters: {'query': query},
    );
    final value = response.data;
    final items = value is List
        ? value
        : (value as Map?)?['items'] as List? ?? [];
    return items
        .map(
          (item) =>
              ActivityType.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<ActivityType> createCustomActivityType({
    required String name,
    required String referenceTypeId,
  }) async {
    final response = await _authorized(
      'POST',
      '/activity/types/custom',
      data: {'name': name, 'referenceTypeId': referenceTypeId},
    );
    return ActivityType.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<ActivityDay> getActivityDay(DateTime date) async {
    final response = await _authorized(
      'GET',
      '/activity/days/${formatLocalDate(date)}',
      queryParameters: {'timezone': await _timezone()},
    );
    return ActivityDay.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<ActivityWeek> getActivityWeek(DateTime date) async {
    final response = await _authorized(
      'GET',
      '/activity/weeks/${formatLocalDate(date)}',
      queryParameters: {'timezone': await _timezone()},
    );
    return ActivityWeek.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<ActivityWriteResult> addActivityRecord(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) => _activityWrite(
    'POST',
    '/activity/records',
    data: data,
    headers: {'Idempotency-Key': idempotencyKey},
  );

  Future<ActivityWriteResult> updateActivityRecord(
    String id,
    Map<String, dynamic> data,
  ) => _activityWrite('PUT', '/activity/records/$id', data: data);

  Future<ActivityWriteResult> deleteActivityRecord(String id) =>
      _activityWrite('DELETE', '/activity/records/$id');

  Future<ActivityWriteResult> _activityWrite(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    final timezone = await _timezone();
    final body = data == null
        ? null
        : {...data, 'timezone': data['timezone'] ?? timezone};
    final response = await _authorized(
      method,
      path,
      data: body,
      queryParameters: method == 'DELETE' ? {'timezone': timezone} : null,
      headers: headers,
    );
    return ActivityWriteResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<SleepDay> getSleepDay(DateTime date) async {
    final response = await _authorized(
      'GET',
      '/sleep/days/${formatLocalDate(date)}',
      queryParameters: {'timezone': await _timezone()},
    );
    return SleepDay.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<SleepWeek> getSleepWeek(DateTime date) async {
    final response = await _authorized(
      'GET',
      '/sleep/weeks/${formatLocalDate(date)}',
      queryParameters: {'timezone': await _timezone()},
    );
    return SleepWeek.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<SleepWriteResult> addSleepRecord(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) => _sleepWrite(
    'POST',
    '/sleep/records',
    data: data,
    headers: {'Idempotency-Key': idempotencyKey},
  );

  Future<SleepWriteResult> updateSleepRecord(
    String id,
    Map<String, dynamic> data,
  ) => _sleepWrite('PUT', '/sleep/records/$id', data: data);

  Future<SleepWriteResult> deleteSleepRecord(String id) =>
      _sleepWrite('DELETE', '/sleep/records/$id');

  Future<SleepWriteResult> _sleepWrite(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    final timezone = await _timezone();
    final body = data == null
        ? null
        : {...data, 'timezone': data['timezone'] ?? timezone};
    final response = await _authorized(
      method,
      path,
      data: body,
      queryParameters: method == 'DELETE' ? {'timezone': timezone} : null,
      headers: headers,
    );
    return SleepWriteResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<HydrationDay> _hydrationDayRequest(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    final response = await _authorized(
      method,
      path,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
    );
    return HydrationDay.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<HydrationSettings> _hydrationSettingsRequest(
    String method,
    String path, {
    Object? data,
  }) async {
    final response = await _authorized(method, path, data: data);
    return HydrationSettings.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<NutritionDay> _nutritionRequest(
    String method,
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    final response = await _authorized(
      method,
      path,
      data: data,
      headers: headers,
    );
    return NutritionDay.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<Map<String, dynamic>> previewPlan() =>
      _planRequest('POST', '/plans/preview');

  Future<Map<String, dynamic>> createPlan({
    Map<String, dynamic>? adjustments,
  }) => _planRequest('POST', '/plans', data: adjustments ?? const {});

  Future<Map<String, dynamic>> getCurrentPlan() =>
      _planRequest('GET', '/plans/current');

  Future<List<Map<String, dynamic>>> getPlanHistory() async {
    final response = await _authorized('GET', '/plans/history');
    final data = response.data;
    final items = data is List ? data : (data as Map?)?['items'] as List? ?? [];
    return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> recalculatePlan(
    String id, {
    required int expectedVersion,
  }) => _planRequest(
    'POST',
    '/plans/$id/recalculate',
    data: {'expectedVersion': expectedVersion},
  );

  Future<Map<String, dynamic>> updatePlanTargets(
    String id,
    Map<String, dynamic> targets,
  ) => _planRequest('PUT', '/plans/$id/targets', data: targets);

  Future<Map<String, dynamic>> pausePlan(String id) =>
      _planRequest('POST', '/plans/$id/pause');

  Future<Map<String, dynamic>> resumePlan(String id) =>
      _planRequest('POST', '/plans/$id/resume');

  Future<Map<String, dynamic>> _planRequest(
    String method,
    String path, {
    Object? data,
  }) async {
    final response = await _authorized(method, path, data: data);
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
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    try {
      return await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: {..._authHeaders, ...?headers},
        ),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 401 || !await _refresh()) rethrow;
      return _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: {..._authHeaders, ...?headers},
        ),
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

  Future<LoginResult> _acceptLogin(
    Map<String, dynamic> data, {
    String? phone,
  }) async {
    _accessToken = data['accessToken'] as String;
    await _tokenStore.saveRefreshToken(data['refreshToken'] as String);
    return LoginResult(
      profileComplete: data['profileComplete'] == true,
      phone: phone ?? data['phone'] as String?,
    );
  }

  static String errorMessage(Object error) {
    if (error is FormatException) return error.message;
    if (error is DioException && error.response?.data is Map) {
      return (error.response!.data as Map)['message']?.toString() ?? '请求失败';
    }
    return '网络连接失败，请稍后重试';
  }

  static String? errorCode(Object error) {
    if (error is DioException && error.response?.data is Map) {
      return (error.response!.data as Map)['code']?.toString();
    }
    return null;
  }
}

class LoginResult {
  const LoginResult({required this.profileComplete, this.phone});

  final bool profileComplete;
  final String? phone;
}
