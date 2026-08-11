import 'package:college_project_app/features/auth/widgets/login_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateUsername', () {
    test('rejects empty', () {
      expect(validateUsername(''), isNotNull);
      expect(validateUsername(null), isNotNull);
    });

    test('rejects whitespace-only', () {
      expect(validateUsername('   '), isNotNull);
    });

    test('rejects embedded spaces', () {
      expect(validateUsername('a b'), isNotNull);
    });

    test('rejects over 64 characters', () {
      expect(validateUsername('a' * 65), isNotNull);
    });

    test('accepts register number', () {
      expect(validateUsername('U18IW24S0166'), isNull);
    });

    test('accepts mobile number', () {
      expect(validateUsername('9538111909'), isNull);
    });

    test('trims surrounding whitespace', () {
      expect(validateUsername('  U18IW24S0166  '), isNull);
    });
  });

  group('validatePassword', () {
    test('rejects empty', () {
      expect(validatePassword(''), isNotNull);
      expect(validatePassword(null), isNotNull);
    });

    test('rejects over 128 characters', () {
      expect(validatePassword('p' * 129), isNotNull);
    });

    test('accepts a typical password', () {
      expect(validatePassword('Santhosh*9900'), isNull);
    });

    test('accepts a short password', () {
      expect(validatePassword('x'), isNull);
    });
  });
}
