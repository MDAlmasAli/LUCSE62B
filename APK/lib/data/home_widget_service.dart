import 'dart:io';

import 'package:home_widget/home_widget.dart';

class HomeWidgetService {
  HomeWidgetService._();
  static final instance = HomeWidgetService._();

  static const provider = 'CsePortalWidgetProvider';
  static const qualifiedProvider =
      'com.lucse62b.lucse62b.CsePortalWidgetProvider';

  Future<void> saveClassStatus({
    required String label,
    required String title,
    required String details,
  }) async {
    if (!Platform.isAndroid) return;
    await HomeWidget.saveWidgetData('class_label', label);
    await HomeWidget.saveWidgetData('class_title', title);
    await HomeWidget.saveWidgetData('class_details', details);
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
    await HomeWidget.requestPinWidget(
      androidName: provider,
      qualifiedAndroidName: qualifiedProvider,
    );
  }
}
