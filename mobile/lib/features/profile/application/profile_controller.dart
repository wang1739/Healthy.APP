import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/profile/domain/profile_data.dart';

enum ProfileSaveResult { saved, recalculationRequired, failed }

class ProfileViewState {
  const ProfileViewState({
    this.data,
    this.loading = false,
    this.saving = false,
    this.error,
    this.draft,
  });

  final ProfileData? data;
  final bool loading;
  final bool saving;
  final String? error;
  final Map<String, dynamic>? draft;
}

class ProfileController extends ChangeNotifier {
  ProfileController(this.api);

  final ApiClient api;
  ProfileViewState state = const ProfileViewState(loading: true);

  Future<void> load() async {
    state = ProfileViewState(data: state.data, loading: true);
    notifyListeners();
    try {
      final values = await Future.wait([
        api.getProfileSections(),
        api.getProfileMeasurements(),
      ]);
      final data = ProfileData.fromJson(values[0] as Map<String, dynamic>)
          .withMeasurements(
            (values[1] as List<Map<String, dynamic>>)
                .map(BodyMeasurement.fromJson)
                .toList(),
          );
      state = ProfileViewState(data: data);
    } catch (error) {
      state = ProfileViewState(
        data: state.data,
        error: ApiClient.errorMessage(error),
      );
    }
    notifyListeners();
  }

  Future<ProfileSaveResult> save(
    String section,
    Map<String, dynamic> data,
  ) async {
    final criticalChanged = _criticalChanged(section, data);
    state = ProfileViewState(data: state.data, saving: true, draft: data);
    notifyListeners();
    try {
      final response = await api.saveProfileSection(section, data);
      final fresh = response['sections'] is Map || response['basicInfo'] is Map
          ? response
          : await api.getProfileSections();
      final measurements = await api.getProfileMeasurements();
      final updated = ProfileData.fromJson(
        fresh,
      ).withMeasurements(measurements.map(BodyMeasurement.fromJson).toList());
      state = ProfileViewState(data: updated);
      notifyListeners();
      return criticalChanged && updated.planNeedsRecalculation
          ? ProfileSaveResult.recalculationRequired
          : ProfileSaveResult.saved;
    } catch (error) {
      state = ProfileViewState(
        data: state.data,
        error: ApiClient.errorMessage(error),
        draft: data,
      );
      notifyListeners();
      return ProfileSaveResult.failed;
    }
  }

  Future<ProfileSaveResult> addMeasurement(Map<String, dynamic> data) async {
    state = ProfileViewState(data: state.data, saving: true, draft: data);
    notifyListeners();
    try {
      await api.addMeasurement(data);
      await load();
      return ProfileSaveResult.recalculationRequired;
    } catch (error) {
      state = ProfileViewState(
        data: state.data,
        error: ApiClient.errorMessage(error),
        draft: data,
      );
      notifyListeners();
      return ProfileSaveResult.failed;
    }
  }

  bool _criticalChanged(String section, Map<String, dynamic> draft) {
    final current = state.data;
    if (current == null) return false;
    final keys = switch (section) {
      'basic' => const ['birthDate', 'sex', 'metabolicBasis'],
      'body' => const ['heightCm'],
      'lifestyle' => const ['activityLevel'],
      'goal' => const ['goalType', 'targetWeightKg', 'targetDate'],
      _ => const <String>[],
    };
    return keys.any(
      (key) =>
          draft.containsKey(key) && '${draft[key]}' != '${current.value(key)}',
    );
  }
}

final profileControllerProvider = ChangeNotifierProvider.autoDispose
    .family<ProfileController, ApiClient>((ref, api) => ProfileController(api));
