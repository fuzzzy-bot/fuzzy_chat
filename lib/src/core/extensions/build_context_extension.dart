import 'package:flutter/material.dart';
import 'package:fuzzy_chat/lib.dart';

extension BuildContextExtension on BuildContext {
  FuzzyChatLocalizations get fuzzyChatLocalizations =>
      FuzzyChatLocalizations.of(this)!;
}
