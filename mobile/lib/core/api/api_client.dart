import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:healthy/core/api/api_config.dart';
import 'package:healthy/core/storage/token_store.dart';
import 'package:healthy/features/nutrition/domain/nutrition_data.dart';
import 'package:healthy/features/hydration/domain/hydration_data.dart';
import 'package:healthy/features/activity/domain/activity_data.dart';
import 'package:healthy/features/sleep/domain/sleep_data.dart';
import 'package:healthy/features/tasks/domain/task_data.dart';
import 'package:healthy/features/report/domain/report_data.dart';
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
  String? _accountStatus;
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

  Future<String?> sendPurposeCode(String phone, String purpose) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/sms/send',
      data: {'phone': phone, 'purpose': purpose},
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
    if (_accountStatus == 'DELETION_PENDING') {
      return const LoginResult(
        profileComplete: false,
        accountStatus: 'DELETION_PENDING',
      );
    }
    final account = await getAccount();
    return LoginResult(
      profileComplete: account['profileComplete'] == true,
      phone: account['phone'] as String?,
      accountStatus: account['status']?.toString() ?? 'ACTIVE',
    );
  }

  Future<Map<String, dynamic>> getAccount() async {
    final response = await _authorized('GET', '/account');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> getDevices() async {
    final response = await _authorized('GET', '/account/devices');
    return (response.data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<void> removeDevice(String id) =>
      _authorized('DELETE', '/account/devices/$id').then((_) {});

  Future<List<Map<String, dynamic>>> getSecurityEvents() async {
    final response = await _authorized('GET', '/account/security-events');
    return (response.data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<void> logoutOtherDevices(String code) => _authorized(
    'POST',
    '/account/devices/logout-others',
    data: {'code': code},
  ).then((_) {});

  Future<Map<String, dynamic>> getPrivacy() async => Map<String, dynamic>.from(
    (await _authorized('GET', '/privacy')).data as Map,
  );

  Future<void> acceptConsent(String type, String version) => _authorized(
    'POST',
    '/privacy/consents',
    data: {'documentType': type, 'version': version},
  ).then((_) {});

  Future<void> withdrawHealthAuthorization() => _authorized(
    'POST',
    '/privacy/health-authorization/withdraw',
  ).then((_) {});

  Future<void> changePhone({
    required String oldCode,
    required String newPhone,
    required String newCode,
  }) => _authorized(
    'POST',
    '/account/phone/change',
    data: {'oldCode': oldCode, 'newPhone': newPhone, 'newCode': newCode},
  ).then((_) {});

  Future<Map<String, dynamic>> submitPhoneAppeal({
    required String newPhone,
    required String materialReference,
  }) async => Map<String, dynamic>.from(
    (await _authorized(
          'POST',
          '/account/phone/appeals',
          data: {'newPhone': newPhone, 'materialReference': materialReference},
        )).data
        as Map,
  );

  Future<List<Map<String, dynamic>>> getDataExports() async {
    final response = await _authorized('GET', '/data-exports');
    return (response.data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createDataExport({
    required String code,
    required String password,
  }) async => Map<String, dynamic>.from(
    (await _authorized(
          'POST',
          '/data-exports',
          data: {'code': code, 'password': password},
        )).data
        as Map,
  );

  Future<Map<String, dynamic>> previewHealthDataDeletion(
    List<String> types,
  ) async => Map<String, dynamic>.from(
    (await _authorized(
          'POST',
          '/health-data-deletion/preview',
          data: {'dataTypes': types},
        )).data
        as Map,
  );

  Future<Map<String, dynamic>> deleteHealthData(
    List<String> types,
    String code,
  ) async => Map<String, dynamic>.from(
    (await _authorized(
          'POST',
          '/health-data-deletion',
          data: {'dataTypes': types, 'code': code},
        )).data
        as Map,
  );

  Future<Map<String, dynamic>> requestAccountDeletion(String code) async =>
      Map<String, dynamic>.from(
        (await _authorized(
              'POST',
              '/account/deletion',
              data: {'code': code},
            )).data
            as Map,
      );

  Future<Map<String, dynamic>> getAccountDeletion() async =>
      Map<String, dynamic>.from(
        (await _authorized('GET', '/account/deletion')).data as Map,
      );

  Future<void> recoverAccount(String code) => _authorized(
    'POST',
    '/account/deletion/recover',
    data: {'code': code},
  ).then((_) => _accountStatus = 'ACTIVE');

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

  Future<TaskDay> getTaskDay(DateTime date) async {
    final response = await _authorized(
      'GET',
      '/tasks/days/${formatLocalDate(date)}',
      queryParameters: {'timezone': await _timezone()},
    );
    return TaskDay.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<TaskWeek> getTaskWeek(DateTime date) async {
    final response = await _authorized(
      'GET',
      '/tasks/weeks/${formatLocalDate(date)}',
      queryParameters: {'timezone': await _timezone()},
    );
    return TaskWeek.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<List<TaskNotification>> getTaskNotifications({
    required DateTime from,
    required DateTime to,
  }) async {
    final response = await _authorized(
      'GET',
      '/tasks/notifications',
      queryParameters: {
        'from': formatLocalDate(from),
        'to': formatLocalDate(to),
        'timezone': await _timezone(),
      },
    );
    final data = response.data;
    final items = data is List ? data : (data as Map?)?['items'] as List? ?? [];
    return items
        .map(
          (item) =>
              TaskNotification.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<TaskMutationResult> createTask(
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) => _taskMutation(
    'POST',
    '/tasks',
    data: _taskCreateData(data),
    headers: {'Idempotency-Key': idempotencyKey},
    includeTimezone: true,
  );

  Future<TaskMutationResult> updateTaskInstance(
    String id,
    Map<String, dynamic> data,
  ) => _taskMutation(
    'PUT',
    '/tasks/instances/$id',
    data: _taskInstanceUpdateData(data),
    includeTimezone: true,
  );

  Future<TaskMutationResult> updateTaskTemplate(
    String id,
    Map<String, dynamic> data,
  ) => _taskMutation(
    'PUT',
    '/tasks/templates/$id',
    data: _taskTemplateUpdateData(data),
    includeTimezone: true,
  );

  Future<TaskMutationResult> completeTask(
    String id, {
    required String idempotencyKey,
  }) => _taskStatus(id, 'complete', const {}, idempotencyKey);

  Future<TaskMutationResult> reopenTask(
    String id, {
    required String idempotencyKey,
  }) => _taskStatus(id, 'reopen', const {}, idempotencyKey);

  Future<TaskMutationResult> skipTask(
    String id, {
    required String idempotencyKey,
    String? reason,
  }) => _taskStatus(id, 'skip', {
    if (reason?.isNotEmpty == true) 'reason': reason,
  }, idempotencyKey);

  Future<TaskMutationResult> postponeTask(
    String id,
    Map<String, dynamic> data, {
    required String idempotencyKey,
  }) => _taskStatus(
    id,
    'postpone',
    {
      ...data,
      'type': data['mode'] == 'LATER_30'
          ? 'LATER'
          : (data['type'] ?? data['mode']),
    }..remove('mode'),
    idempotencyKey,
  );

  Future<TaskMutationResult> _taskStatus(
    String id,
    String action,
    Map<String, dynamic> data,
    String idempotencyKey,
  ) async {
    final timezone = await _timezone();
    final usesQuery = action == 'complete' || action == 'reopen';
    return _taskMutation(
      'POST',
      '/tasks/instances/$id/$action',
      data: usesQuery ? data : {...data, 'timezone': timezone},
      queryParameters: usesQuery ? {'timezone': timezone} : null,
      headers: {'Idempotency-Key': idempotencyKey},
    );
  }

  Future<void> deleteTaskInstance(String id) async {
    await _authorized(
      'DELETE',
      '/tasks/instances/$id',
      queryParameters: {'timezone': await _timezone()},
    );
  }

  Future<void> deleteTaskTemplate(
    String id, {
    required DateTime effectiveDate,
  }) async {
    await _authorized(
      'DELETE',
      '/tasks/templates/$id',
      queryParameters: {
        'effectiveDate': formatLocalDate(effectiveDate),
        'timezone': await _timezone(),
      },
    );
  }

  Future<TaskSettings> getTaskSettings() async {
    final response = await _authorized('GET', '/tasks/settings');
    return TaskSettings.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<TaskSettings> updateTaskSettings(Map<String, dynamic> data) async {
    final response = await _authorized(
      'PUT',
      '/tasks/settings',
      data: {
        ...data,
        if (data.containsKey('version')) 'expectedVersion': data['version'],
      }..remove('version'),
    );
    return TaskSettings.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> reportTaskNotificationEvents(
    List<Map<String, dynamic>> events, {
    required String idempotencyKey,
  }) async {
    await _authorized(
      'POST',
      '/tasks/notification-events',
      data: {'events': events},
      headers: {'Idempotency-Key': idempotencyKey},
    );
  }

  Future<void> adoptTaskPlanUpdates({
    required DateTime date,
    required String idempotencyKey,
  }) async {
    await _authorized(
      'POST',
      '/tasks/plan-updates/adopt',
      data: {'date': formatLocalDate(date), 'timezone': await _timezone()},
      headers: {'Idempotency-Key': idempotencyKey},
    );
  }

  Future<TaskMutationResult> _taskMutation(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool includeTimezone = false,
  }) async {
    final timezone = await _timezone();
    final response = await _authorized(
      method,
      path,
      data: data == null
          ? null
          : {...data, if (includeTimezone) 'timezone': timezone},
      queryParameters: {
        ...?queryParameters,
        if (method == 'DELETE') 'timezone': timezone,
      },
      headers: headers,
    );
    return TaskMutationResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Map<String, dynamic> _taskCreateData(Map<String, dynamic> data) =>
      {
          ...data,
          if (data.containsKey('localDate')) 'date': data['localDate'],
          if (data['weekdays'] is List)
            'weekdaysMask': _taskWeekdaysMask(data['weekdays'] as List),
        }
        ..remove('localDate')
        ..remove('weekdays');

  Map<String, dynamic> _taskInstanceUpdateData(Map<String, dynamic> data) => {
    for (final key in const [
      'title',
      'note',
      'category',
      'priority',
      'allDay',
      'localTime',
      'reminderOffsetMinutes',
    ])
      if (data.containsKey(key)) key: data[key],
    if (data.containsKey('version')) 'expectedVersion': data['version'],
  };

  Map<String, dynamic> _taskTemplateUpdateData(Map<String, dynamic> data) =>
      {
          ...data,
          if (data.containsKey('localDate') || data.containsKey('date'))
            'effectiveDate': data['localDate'] ?? data['date'],
          if (data.containsKey('version')) 'expectedVersion': data['version'],
          if (data['weekdays'] is List)
            'weekdaysMask': _taskWeekdaysMask(data['weekdays'] as List),
        }
        ..remove('localDate')
        ..remove('date')
        ..remove('version')
        ..remove('weekdays');

  int _taskWeekdaysMask(List weekdays) => weekdays.fold<int>(0, (mask, day) {
    final value = day is num ? day.toInt() : int.tryParse('$day') ?? 0;
    return value >= 1 && value <= 7 ? mask | (1 << (value - 1)) : mask;
  });

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

  Future<HealthReport> generateReport({
    required ReportType type,
    required DateTime date,
    required String idempotencyKey,
  }) async {
    final response = await _authorized(
      'POST',
      '/reports',
      data: {
        'type': type.wireName,
        'date': formatLocalDate(date),
        'timezone': await _timezone(),
      },
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return HealthReport.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<ReportPageData> getReports({
    required ReportType type,
    required DateTime date,
  }) async {
    final response = await _authorized(
      'GET',
      '/reports',
      queryParameters: {
        'type': type.wireName,
        'date': formatLocalDate(date),
        'timezone': await _timezone(),
      },
    );
    return ReportPageData.fromJson(response.data);
  }

  Future<HealthReport> getReport(String id) async {
    final response = await _authorized('GET', '/reports/$id');
    return HealthReport.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<List<ReportSource>> getReportSources(
    String id, {
    required String section,
    String? metric,
  }) async {
    final response = await _authorized(
      'GET',
      '/reports/$id/sources',
      queryParameters: {
        'section': section,
        if (metric?.isNotEmpty == true) 'metric': metric,
      },
    );
    final data = response.data;
    final values = data is List
        ? data
        : (data as Map?)?['items'] as List? ?? const [];
    return values
        .map(
          (item) =>
              ReportSource.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<ReportPdf> downloadReportPdf(String id) async {
    final response = await _authorized(
      'GET',
      '/reports/$id/pdf',
      responseType: ResponseType.bytes,
    );
    final data = response.data;
    final bytes = data is Uint8List
        ? data
        : Uint8List.fromList(List<int>.from(data as List));
    final disposition = response.headers.value('content-disposition') ?? '';
    final encoded = RegExp(
      r"filename\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(disposition);
    final fallback = RegExp(r'filename="?([^";]+)').firstMatch(disposition);
    final rawName = encoded == null
        ? fallback?.group(1) ?? '轻食记-健康报告.pdf'
        : Uri.decodeComponent(encoded.group(1)!);
    return ReportPdf(
      bytes: bytes,
      fileName: rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_'),
    );
  }

  Future<void> deleteReport(String id) async {
    await _authorized('DELETE', '/reports/$id');
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
      _accountStatus = null;
      await _tokenStore.clear();
    }
  }

  Future<Response<dynamic>> _authorized(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    ResponseType? responseType,
  }) async {
    try {
      return await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: {..._authHeaders, ...?headers},
          responseType: responseType,
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
          responseType: responseType,
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
      _accountStatus = null;
      await _tokenStore.clear();
      return false;
    }
  }

  Future<LoginResult> _acceptLogin(
    Map<String, dynamic> data, {
    String? phone,
  }) async {
    _accessToken = data['accessToken'] as String;
    _accountStatus = data['accountStatus']?.toString() ?? 'ACTIVE';
    await _tokenStore.saveRefreshToken(data['refreshToken'] as String);
    return LoginResult(
      profileComplete: data['profileComplete'] == true,
      phone: phone ?? data['phone'] as String?,
      accountStatus: _accountStatus!,
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
  const LoginResult({
    required this.profileComplete,
    this.phone,
    this.accountStatus = 'ACTIVE',
  });

  final bool profileComplete;
  final String? phone;
  final String accountStatus;
}
