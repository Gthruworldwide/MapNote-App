import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/core/config/app_config.dart';
import 'package:routenote/src/providers/app_providers.dart';

void main() {
  group('build-bound edition identity', () {
    test('the default build is personal with every privileged capability off',
        () {
      final EditionCapabilities capabilities = EditionCapabilities.fromBuild();

      expect(capabilities.edition, AppEdition.personal);
      expect(capabilities.allowAdminUi, isFalse);
      expect(capabilities.allowFirebaseStationAdmin, isFalse);
    });

    test('unknown edition strings fail closed to personal', () {
      for (final String raw in <String>['', 'WORK_EDITION', 'admin', 'work ']) {
        expect(AppConfig.parseEdition(raw), AppEdition.personal);
      }
      expect(AppConfig.parseEdition('work'), AppEdition.work);
      expect(AppConfig.parseEdition('WORK'), AppEdition.work);
    });

    test('even a work build fails closed for Firebase station administration',
        () {
      const EditionCapabilities work = EditionCapabilities(AppEdition.work);

      expect(work.allowAdminUi, isTrue);
      expect(work.allowFirebaseStationAdmin, isFalse);
    });

    test('the provider exposes the build flag, not a runtime override', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(editionCapabilitiesProvider).edition,
        AppConfig.appEdition,
      );
    });
  });
}
