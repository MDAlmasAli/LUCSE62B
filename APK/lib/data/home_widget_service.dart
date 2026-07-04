import 'dart:io';

import 'package:home_widget/home_widget.dart';

class HomeWidgetService {
  HomeWidgetService._();
  static final instance = HomeWidgetService._();

  static const provider = 'CsePortalWidgetProvider';
  static const qualifiedProvider =
      'com.lucse62b.lucse62b.CsePortalWidgetProvider';

  Future<void> ensureDefaults() async {
    if (!Platform.isAndroid) return;
    final defaults = <String, String>{
      'class_label': 'TODAY',
      'class_title': 'No upcoming class',
      'class_details': 'Open the app to refresh your routine',
      'bus_status': 'No upcoming bus',
      'deadline': 'No upcoming deadline',
    };
    for (final entry in defaults.entries) {
      final saved = await HomeWidget.getWidgetData<String>(entry.key);
      if (saved == null || saved.trim().isEmpty) {
        await HomeWidget.saveWidgetData(entry.key, entry.value);
      }
    }
    await update();
  }

  Future<void> saveScheduleStatus({
    required String label,
    required String title,
    required String details,
    required String busStatus,
  }) async {
    if (!Platform.isAndroid) return;
    await HomeWidget.saveWidgetData('class_label', label);
    await HomeWidget.saveWidgetData('class_title', title);
    await HomeWidget.saveWidgetData('class_details', details);
    await HomeWidget.saveWidgetData('bus_status', busStatus);
    await update();
  }

  Future<void> saveDeadline(String value) async {
    if (!Platform.isAndroid) return;
    await HomeWidget.saveWidgetData('deadline', value);
    await update();
  }

  Future<void> update() async {
    if (!Platform.isAndroid) return;
    await HomeWidget.updateWidget(
      androidName: provider,
      qualifiedAndroidName: qualifiedProvider,
    );
  }

  Future<bool> canPin() async {
    if (!Platform.isAndroid) return false;
    return await HomeWidget.isRequestPinWidgetSupported() ?? false;
  }

  Future<void> requestPin() async {
    if (!Platform.isAndroid) return;
    await ensureDefaults();
    await HomeWidget.requestPinWidget(
      androidName: provider,
      qualifiedAndroidName: qualifiedProvider,
    );
  }
}
