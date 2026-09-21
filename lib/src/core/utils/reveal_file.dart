import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fuzzy_chat/lib.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'share_helper.dart';

class DeviceFileInteractor {
  static Future<void> shareFile(
    String filePath, {
    BuildContext? context,
  }) async {
    final file = File(filePath);
    final fileExists = await file.exists();
    if (!fileExists) {
      throw FileSystemException('File does not exist', filePath);
    }

    if (context != null) {
      // ignore: use_build_context_synchronously
      await ShareHelper.shareXFiles([XFile(filePath)], context: context);
    } else {
      await Share.shareXFiles([XFile(filePath)]);
    }
  }

  static Future<void> openFile(String filePath) async {
    final file = File(filePath);
    final fileExists = await file.exists();
    if (!fileExists) {
      throw FileSystemException('File does not exist', filePath);
    }

    final uri = Uri.file(filePath);

    final isUrlLaunched = await launchUrl(uri);
    if (!isUrlLaunched) {
      throw Exception('Could not open file: $filePath');
    }
  }

  ///Only desktop platforms have a file manager that can select a file.
  ///On Android and iOS the app's folders are private and a directory URI has
  ///no handler, so [revealFile] hands the file to the share sheet instead.
  static bool get canRevealFile =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<void> revealFile(
    String filePath, {
    BuildContext? context,
  }) async {
    final file = File(filePath);
    final fileExists = await file.exists();

    if (!fileExists) {
      throw FileSystemException('File does not exist', filePath);
    }

    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      final folderPath = File(filePath).parent.path;

      final fileManagers = [
        ['nautilus', '--select', filePath],
        ['dolphin', '--select', filePath],
        ['nemo', folderPath],
        ['xdg-open', folderPath],
      ];

      for (final command in fileManagers) {
        try {
          final result = await Process.run(command[0], command.sublist(1));
          if (result.exitCode == 0) return;
        } catch (_) {}
      }

      throw Exception('Could not open file manager on Linux.');
    } else if (Platform.isAndroid || Platform.isIOS) {
      // ignore: use_build_context_synchronously
      await shareFile(filePath, context: context);
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
}
