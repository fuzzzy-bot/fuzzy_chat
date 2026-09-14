import 'package:fuzzy_chat/lib.dart';

enum ConnectedChatFailureType {
  alreadyUnfuzzed,
  wrongChat,
  tooOld,
  corrupt,
  unknown;

  String toUiMessage(
    FuzzyChatLocalizations localizations, {
    String? customUnknownMessage,
  }) {
    return switch (this) {
      ConnectedChatFailureType.alreadyUnfuzzed => localizations.alreadyUnfuzzed,
      ConnectedChatFailureType.wrongChat => localizations.wrongChatBlob,
      ConnectedChatFailureType.tooOld => localizations.blobTooOld,
      ConnectedChatFailureType.corrupt => localizations.corruptBlob,
      ConnectedChatFailureType.unknown =>
        customUnknownMessage ?? localizations.unknownError,
    };
  }
}
