import 'package:fuzzy_chat/lib.dart';

/// Why a file job ended in [FileProcessingStatus.failed]. The chat-receive
/// prepare step consumes the container's key message, so a failure *after*
/// it ([cannotOpenAskResend]) is terminal for that container — the sender has
/// to send it again; the other cases leave nothing consumed.
enum FileProcessingFailureType {
  wrongPassword,
  alreadyUnfuzzed,
  wrongChat,
  tooOld,
  corrupt,
  stillArriving,
  cannotOpenAskResend,
  unknown;

  String toUiMessage(
    FuzzyChatLocalizations localizations, {
    String? customUnknownMessage,
  }) {
    return switch (this) {
      FileProcessingFailureType.wrongPassword =>
        localizations.wrongPasswordFile,
      FileProcessingFailureType.alreadyUnfuzzed =>
        localizations.alreadyUnfuzzed,
      FileProcessingFailureType.wrongChat => localizations.wrongChatBlob,
      FileProcessingFailureType.tooOld => localizations.blobTooOld,
      FileProcessingFailureType.corrupt => localizations.corruptBlob,
      FileProcessingFailureType.stillArriving =>
        localizations.fileStillArriving,
      FileProcessingFailureType.cannotOpenAskResend =>
        localizations.fileCannotBeOpenedAskToResend,
      FileProcessingFailureType.unknown =>
        customUnknownMessage ?? localizations.unknownError,
    };
  }
}
