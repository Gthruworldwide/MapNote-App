import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _workflow(String name) =>
    File('.github/workflows/$name').readAsStringSync();

void _assertPinnedActions(String workflow, String name) {
  expect(
    RegExp(r'uses:\s+\S+@[0-9a-f]{40}').hasMatch(workflow),
    isTrue,
    reason: '$name must pin every action to a full commit SHA',
  );
  expect(
    RegExp(r'uses:\s+\S+@v\d').hasMatch(workflow),
    isFalse,
    reason: '$name must not use a moving major-version action tag',
  );
}

void _assertNoDirectSecretShellExpansion(String workflow, String name) {
  for (final String line in workflow.split('\n')) {
    if (line.contains(r'${{ secrets.') &&
        (line.trimLeft().startsWith('run:') ||
            line.trimLeft().startsWith('--') ||
            line.contains('flutter build'))) {
      fail('$name interpolates a secret directly into a shell command');
    }
  }
}

void main() {
  group('CI workflow hardening', () {
    test('opencode agent trigger is trusted and command-bound', () {
      final String workflow = _workflow('opencode.yml');

      expect(workflow, contains('author_association'));
      for (final String role in <String>['OWNER', 'MEMBER', 'COLLABORATOR']) {
        expect(workflow, contains(role));
      }
      expect(
        workflow,
        isNot(contains("contains(github.event.comment.body, '/oc')")),
      );
      expect(workflow, contains("github.event.comment.body == '/oc'"));
      expect(
        workflow,
        contains("startsWith(github.event.comment.body, '/oc ')"),
      );
      expect(workflow, contains("github.event.comment.body == '/opencode'"));
      expect(
        workflow,
        contains("startsWith(github.event.comment.body, '/opencode ')"),
      );
      _assertNoDirectSecretShellExpansion(workflow, 'opencode.yml');
      _assertPinnedActions(workflow, 'opencode.yml');
    });

    test('release builds use semver tags, injected secrets and short-lived APKs',
        () {
      final String workflow = _workflow('android-release.yml');

      expect(workflow, contains('permissions:\n  contents: read'));
      expect(workflow, contains("'v[0-9]+.[0-9]+.[0-9]+'"));
      expect(
        workflow,
        isNot(contains("- 'v*'")),
        reason: 'a broad v* tag can build a key-bearing APK for throwaway tags',
      );
      expect(
        workflow,
        contains(r'GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}'),
      );
      expect(
        workflow,
        contains(r'--dart-define="GEMINI_API_KEY=$GEMINI_API_KEY"'),
      );
      expect(workflow, contains('retention-days: 1'));
      expect(workflow, contains('if-no-files-found: error'));
      expect(workflow, contains('APP_EDITION: personal'));
      expect(
        workflow,
        contains(r'--dart-define="APP_EDITION=$APP_EDITION"'),
      );
      _assertNoDirectSecretShellExpansion(workflow, 'android-release.yml');
      _assertPinnedActions(workflow, 'android-release.yml');
    });

    test('Firebase distribution validates secrets and shortens artifact links',
        () {
      final String workflow = _workflow('firebase-distribution.yml');

      expect(workflow, contains('permissions:\n  contents: read'));
      expect(workflow, contains("'v[0-9]+.[0-9]+.[0-9]+'"));
      expect(workflow, isNot(contains("- 'v*'")));
      expect(workflow, contains('retention-days: 1'));
      expect(workflow, contains('if-no-files-found: error'));
      expect(workflow, contains("type == \"service_account\""));
      expect(workflow, contains('FIREBASE_SERVICE_ACCOUNT_KEY'));
      expect(workflow, contains('APP_EDITION: personal'));
      expect(
        workflow,
        contains(r'--dart-define="APP_EDITION=$APP_EDITION"'),
      );
      expect(workflow, contains('Record artifact digest'));
      expect(workflow, contains('Verify distributed APK digest'));
      expect(workflow, contains('needs.build.outputs.apk_sha256'));
      _assertNoDirectSecretShellExpansion(workflow, 'firebase-distribution.yml');
      _assertPinnedActions(workflow, 'firebase-distribution.yml');
    });
  });
}
