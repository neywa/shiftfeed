// Widget tests for the email+password fallback in [AuthSheet].
//
// Added for Apple App Review (Guideline 2.1(a)): reviewers can't click a
// magic-link email, so the sheet grows a revealed-on-demand password path.
// These pin that (a) magic link stays the default with the password field
// hidden, (b) the password path calls signInWithPassword with the exact args,
// (c) auth errors render via the existing error block, and (d) the reused
// pop-on-signedIn exit still fires.
//
// The sheet talks to Supabase only through the injectable [AuthSheetActions]
// seam, so a fake stands in — the repo deliberately avoids pumping widgets
// against the live Supabase singleton (see nav_tabs_test.dart).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/widgets/auth_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records calls and lets tests drive the auth streams / force failures.
class FakeAuthSheetActions implements AuthSheetActions {
  final _authStateController = StreamController<AuthState>.broadcast();
  final _authErrorController = StreamController<String>.broadcast();

  final List<String> magicLinkCalls = [];
  final List<List<String>> passwordSignInCalls = [];
  final List<List<String>> signUpCalls = [];

  /// When set, the matching method throws it instead of succeeding.
  Object? throwOnSignIn;
  Object? throwOnMagicLink;

  /// Value returned by [signUpWithPassword] (true = immediate session).
  bool signUpReturnsSignedIn = false;

  @override
  Stream<AuthState> get authStateChanges => _authStateController.stream;

  @override
  Stream<String> get authErrors => _authErrorController.stream;

  void emitSignedIn() =>
      _authStateController.add(const AuthState(AuthChangeEvent.signedIn, null));

  void emitAuthError(String message) => _authErrorController.add(message);

  @override
  Future<void> sendMagicLink(String email) async {
    magicLinkCalls.add(email);
    if (throwOnMagicLink != null) throw throwOnMagicLink!;
  }

  @override
  Future<void> signInWithPassword(String email, String password) async {
    passwordSignInCalls.add([email, password]);
    if (throwOnSignIn != null) throw throwOnSignIn!;
  }

  @override
  Future<bool> signUpWithPassword(String email, String password) async {
    signUpCalls.add([email, password]);
    return signUpReturnsSignedIn;
  }

  void dispose() {
    _authStateController.close();
    _authErrorController.close();
  }
}

void main() {
  late FakeAuthSheetActions fake;

  setUp(() => fake = FakeAuthSheetActions());
  tearDown(() => fake.dispose());

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthSheet(actions: fake),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('password field is hidden until "Use password instead" is tapped',
      (tester) async {
    await pumpSheet(tester);

    // Default (magic-link) state: no password field, primary CTA sends a link.
    expect(find.widgetWithText(TextFormField, 'Password'), findsNothing);
    expect(find.text('Send sign-in link'), findsOneWidget);

    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('password sign-in calls signInWithPassword with trimmed args',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      '  reviewer@example.com  ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter2pass',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(fake.passwordSignInCalls, [
      ['reviewer@example.com', 'hunter2pass'],
    ]);
    expect(fake.magicLinkCalls, isEmpty);
  });

  testWidgets('a failed password sign-in renders the error message',
      (tester) async {
    fake.throwOnSignIn = const AuthException('Invalid login credentials');
    await pumpSheet(tester);
    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      'reviewer@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'wrongpass',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid login credentials'), findsOneWidget);
  });

  testWidgets('empty password blocks the call and shows a validation error',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      'reviewer@example.com',
    );
    // Leave password empty.
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(fake.passwordSignInCalls, isEmpty);
    expect(find.text('Please enter your password.'), findsOneWidget);
  });

  testWidgets('sign-up without an immediate session shows the confirm hint',
      (tester) async {
    fake.signUpReturnsSignedIn = false;
    await pumpSheet(tester);
    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      'newuser@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'strongpass1',
    );
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(fake.signUpCalls, [
      ['newuser@example.com', 'strongpass1'],
    ]);
    expect(
      find.textContaining('Check your inbox to confirm'),
      findsOneWidget,
    );
  });

  testWidgets('magic-link default path still calls sendMagicLink',
      (tester) async {
    await pumpSheet(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      'realuser@example.com',
    );
    await tester.tap(find.text('Send sign-in link'));
    await tester.pump();

    expect(fake.magicLinkCalls, ['realuser@example.com']);
    expect(fake.passwordSignInCalls, isEmpty);
  });

  testWidgets('a signedIn auth event pops the sheet with true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await AuthSheet.show(context, actions: fake);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Send sign-in link'), findsOneWidget);

    fake.emitSignedIn();
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.text('Send sign-in link'), findsNothing);
  });
}
