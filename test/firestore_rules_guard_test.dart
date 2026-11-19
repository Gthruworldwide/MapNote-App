import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _ruleFiles = <String>[
  'android/app/firestore.rules',
  'android/app/master_stations.rules',
];

void main() {
  group('Firestore rules access matrix guards', () {
    final Map<String, String> rules = <String, String>{
      for (final String path in _ruleFiles)
        path: File(path).readAsStringSync(),
    };

    test('both candidate rulesets are byte-identical', () {
      expect(rules[_ruleFiles[1]], rules[_ruleFiles[0]],
          reason: 'deployment authority is external; the candidates must not diverge');
    });

    for (final MapEntry<String, String> entry in rules.entries) {
      final String path = entry.key;
      final String text = entry.value;

      test('$path has no root-wide or unauthenticated allow', () {
        final int firstMatch = text.indexOf('match /');
        final String rootScope = text.substring(0, firstMatch);

        expect(
          rootScope,
          isNot(matches(
              r'allow\s+(read|write|read,\s*write)\s*:\s*if\s*request\.auth\s*!=\s*null')),
          reason: 'root grants are OR\'d with every descendant allow',
        );

        final List<String> grants = text
            .split('\n')
            .map((String line) => line.trimLeft())
            .where((String line) => line.startsWith('allow '))
            .toList();
        expect(grants, isNotEmpty);
        for (final String grant in grants) {
          expect(grant, isNot(contains('request.auth != null')),
              reason: 'only the signed-in helpers may inspect request.auth');
          expect(
            grant,
            anyOf(
              contains('isSignedIn()'),
              contains('isAdmin()'),
              contains('isOwner('),
              contains('if false'),
            ),
            reason: 'every grant must be an explicit owner/admin/deny rule',
          );
        }
      });

      test('$path denies normal users all master-station access', () {
        final String master = text.substring(
          text.indexOf('match /master_stations'),
          text.indexOf('match /pending_updates'),
        );

        expect(master, contains('allow read: if isAdmin();'));
        expect(master, contains('allow create, update, delete: if isAdmin();'));
        expect(master, isNot(contains('if request.auth != null')));
      });

      test('$path denies normal users the admin audit log', () {
        final String adminOps = text.substring(
          text.indexOf('match /admin_operations'),
          text.indexOf('match /shared_stations'),
        );

        expect(adminOps,
            contains('allow read, create, update, delete: if isAdmin();'));
      });

      test('$path has no public or sharedWith read bypass', () {
        expect(text, isNot(contains('sharedWith')));
        expect(text, isNot(contains('isPublic')));

        final String shared = text.substring(
          text.indexOf('match /shared_stations'),
          text.indexOf('match /user_settings'),
        );
        expect(shared, contains('isOwner(resource.data.ownerUid)'));
        expect(shared, contains('isOwner(request.resource.data.ownerUid)'));
      });

      test('$path denies unmatched paths for reads and writes', () {
        final RegExp wildcard = RegExp(
            r'match\s+/\{document=\*\*\}\s*\{[^}]*allow\s+read,\s+write:\s+if\s+false');
        expect(
          wildcard.hasMatch(text),
          isTrue,
          reason: '$path must end with an explicit read/write deny wildcard',
        );
      });
    }
  });
}
