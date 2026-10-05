import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/features/auth/screens/setup_screen.dart';

void main() {
  test('Apple name cannot replace a saved profile name', () {
    expect(
        resolveSetupName(
          profile: {'full_name': 'Saved name', 'name': 'Legacy name'},
          metadata: {'full_name': 'Apple name'},
        ),
        'Saved name');
  });

  test('an empty full_name preserves the saved legacy name', () {
    expect(
        resolveSetupName(
          profile: {'full_name': '  ', 'name': 'Legacy name'},
          metadata: {'full_name': 'Apple name'},
        ),
        'Legacy name');
  });

  test('Apple name is available for a new or unnamed profile', () {
    for (final profile in [
      null,
      <String, dynamic>{},
      {'full_name': '', 'name': null}
    ]) {
      expect(
          resolveSetupName(
              profile: profile, metadata: {'full_name': 'Apple name'}),
          'Apple name');
    }
  });

  test('missing or malformed name metadata cannot crash setup or invent a name',
      () {
    expect(
        resolveSetupName(
            profile: {'full_name': 42, 'name': []},
            metadata: {'full_name': false}),
        '');
    expect(resolveSetupName(metadata: {'full_name': '   '}), '');
    expect(resolveSetupName(), '');
  });
}
