import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuzzy_chat/lib.dart';
import 'package:fuzzzy_ui_kit/fuzzzy_ui_kit.dart';

const _chatId = '6f1e9b2c-3d4a-4f5b-8c6d-7e8f9a0b1c2d';
const _missingPath = '/definitely/not/here/secret.fuzz';

/// `File.exists()` completes on the real event loop, which a widget test's
/// fake async never reaches; this stand-in answers within the test zone.
class _MissingFile extends Fake implements File {
  @override
  Future<bool> exists() async => false;
}

MessageData _fileRow({required bool isSent}) => MessageData(
      id: 1,
      chatId: _chatId,
      type: MessageType.file,
      encryptedMessage: _missingPath,
      decryptedMessage: '',
      sentAt: DateTime(2026, 9, 22, 12),
      isSent: isSent,
    );

Widget _host(Widget child) => MaterialApp(
      theme: FuzzzyTheme.build(inkPack, FuzzzySkin.night),
      localizationsDelegates: FuzzyChatLocalizations.localizationsDelegates,
      supportedLocales: FuzzyChatLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

/// Only the bubble's path is faked; the test binding keeps reading real
/// files (assets, fonts).
final class _MissingFileOverrides extends IOOverrides {
  @override
  File createFile(String path) =>
      path == _missingPath ? _MissingFile() : super.createFile(path);
}

Future<void> _withMissingFiles(Future<void> Function() body) =>
    IOOverrides.runWithIOOverrides(body, _MissingFileOverrides());

/// Tap the overlay's barrier so the action pill is closed before the tree is
/// torn down, then let the toast's auto-dismiss timer run out.
Future<void> _dismissOverlayAndToast(WidgetTester tester) async {
  await tester.tapAt(const Offset(1, 1));
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  // T-0360: the file bubbles' "Show" is reveal-in-file-manager, which only
  // desktop has; on Android/iOS it is the share sheet and the button is hidden
  // so it does not duplicate "Share File". The test host is desktop, so the
  // button is expected; what is asserted is that a failing action surfaces a
  // toast instead of an unhandled error.
  group('file bubble actions (T-0360)', () {
    testWidgets(
        'sent file: "Show" is offered where revealing works and a missing '
        'file toasts instead of failing silently', (tester) async {
      await _withMissingFiles(() async {
        await tester.pumpWidget(
          _host(SentMessageArea(message: _fileRow(isSent: true))),
        );

        await tester.tap(find.text(_missingPath));
        await tester.pumpAndSettle();

        expect(
          find.text('Show'),
          DeviceFileInteractor.canRevealFile ? findsOneWidget : findsNothing,
        );
        expect(find.text('Share File'), findsOneWidget);

        if (DeviceFileInteractor.canRevealFile) {
          await tester.tap(find.text('Show'));
          await tester.pump();

          expect(find.text('Could not open file.'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        await _dismissOverlayAndToast(tester);
      });
    });

    testWidgets(
        'received file: "Open" on a missing file toasts instead of failing '
        'silently', (tester) async {
      await _withMissingFiles(() async {
        await tester.pumpWidget(
          _host(ReceivedFileMessageArea(message: _fileRow(isSent: false))),
        );

        await tester.tap(find.text(_missingPath));
        await tester.pumpAndSettle();

        expect(
          find.text('Show'),
          DeviceFileInteractor.canRevealFile ? findsOneWidget : findsNothing,
        );
        expect(find.text('Open'), findsOneWidget);

        await tester.tap(find.text('Open'));
        await tester.pump();

        expect(find.text('Could not open file.'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _dismissOverlayAndToast(tester);
      });
    });
  });
}
