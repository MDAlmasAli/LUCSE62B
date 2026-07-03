import 'package:package_info_plus/package_info_plus.dart';
import '../core/supa.dart';
import 'models/app_version.dart';

/// Checks the Supabase `app_updates` table for a newer build and decides
/// whether an update is optional or FORCED (blocking). Actual download/install
/// is handled in the UI via the `ota_update` package.
class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  Future<int> currentVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  Future<UpdateStatus> check() async {
    try {
      final current = await currentVersionCode();
      final rows = await Supa.client
          .from('app_updates')
          .select(
            'version_name,version_code,min_version_code,apk_url,features,fixes',
          )
          .order('version_code', ascending: false)
          .limit(1)
          .timeout(const Duration(seconds: 4));
      if (rows.isEmpty) {
        return UpdateStatus(
          latest: null,
          currentCode: current,
          updateAvailable: false,
          forced: false,
        );
      }
      final latest = AppVersion.fromJson(rows.first);
      final available = latest.versionCode > current;
      final forced = current < latest.minVersionCode;
      return UpdateStatus(
        latest: latest,
        currentCode: current,
        updateAvailable: available,
        forced: forced,
      );
    } catch (_) {
      // Network/db failure → never block the user.
      return UpdateStatus.none;
    }
  }
}
