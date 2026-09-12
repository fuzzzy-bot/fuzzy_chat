import 'package:fuzzy_chat/lib.dart';

enum ChatCreationFailureType {
  existingName,
  ownInvitation,
  invalidInvitation,
  invalidAcceptance,
  invitationAlreadyUsed,
  wrongChat,
  unknown;

  String toUiMessage(
    FuzzyChatLocalizations localizations, {
    String? customUnknownMessage,
  }) {
    return switch (this) {
      ChatCreationFailureType.existingName =>
        localizations.chatWithIndicatedNameAlreadyExists,
      ChatCreationFailureType.ownInvitation =>
        localizations.cantAcceptOwnInvitation,
      ChatCreationFailureType.invalidInvitation =>
        localizations.invalidInvitation,
      ChatCreationFailureType.invalidAcceptance =>
        localizations.invalidAcceptance,
      ChatCreationFailureType.invitationAlreadyUsed =>
        localizations.invitationAlreadyUsed,
      ChatCreationFailureType.wrongChat => localizations.wrongChatBlob,
      ChatCreationFailureType.unknown =>
        customUnknownMessage ?? localizations.failedToCreateChat,
    };
  }
}
