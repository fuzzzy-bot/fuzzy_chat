import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuzzy_chat/lib.dart';
import 'package:fuzzzy_ui_kit/fuzzzy_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The forward-secrecy trade-off (owner decision D-1) is the last onboarding
/// slide, in both locales.
void main() {
  const enNotice = 'Each fuzzed message can be unfuzzed once, on this device '
      'only. Your history stays in the app — export an archive to back it up. '
      'A new device cannot re-read old blobs.';
  const kaNotice = 'თითოეული დაშიფრული შეტყობინების გაშიფვრა მხოლოდ ერთხელ და '
      'მხოლოდ ამ მოწყობილობაზე შეიძლება. თქვენი ისტორია აპლიკაციაში რჩება — '
      'სარეზერვო ასლისთვის არქივის ექსპორტი გააკეთეთ. ახალ მოწყობილობას ძველი '
      'შეტყობინებების ხელახლა წაკითხვა არ შეუძლია.';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sl.safeRegisterSingleton<PreferencesService>(
      PreferencesService(await SharedPreferences.getInstance()),
    );
  });

  tearDown(() async {
    await sl.unregister<PreferencesService>();
  });

  Future<void> pumpOnboarding(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FuzzzyTheme.build(inkPack, FuzzzySkin.night),
        localizationsDelegates: FuzzyChatLocalizations.localizationsDelegates,
        supportedLocales: FuzzyChatLocalizations.supportedLocales,
        locale: locale,
        home: const OnboardingPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
  }

  for (final (locale, notice, cta) in [
    (const Locale('en'), enNotice, 'Get Started'),
    (const Locale('ka'), kaNotice, 'დაწყება'),
  ]) {
    testWidgets(
        'the fourth slide carries the forward-secrecy notice '
        '(${locale.languageCode})', (tester) async {
      await pumpOnboarding(tester, locale);
      expect(find.text(notice), findsNothing);

      await next(tester);
      await next(tester);
      await next(tester);

      expect(find.text(notice), findsOneWidget);
      expect(find.text(cta), findsOneWidget);
    });
  }
}
