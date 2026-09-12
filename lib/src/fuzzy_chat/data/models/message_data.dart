import 'package:fuzzy_chat/lib.dart';

class MessageData {
  final int id;
  final String chatId;
  final MessageType type;
  final String encryptedMessage;
  final String decryptedMessage;
  final DateTime sentAt;
  final bool isSent;

  MessageData({
    required this.id,
    required this.chatId,
    required this.type,
    required this.encryptedMessage,
    required this.decryptedMessage,
    required this.sentAt,
    required this.isSent,
  });

  /// [decryptedMessage] is the opened local seal — the repository fills it.
  factory MessageData.fromStored(
    StoredMessageData stored, {
    String decryptedMessage = '',
  }) {
    return MessageData(
      id: stored.id,
      chatId: stored.chatId,
      type: MessageType.values.firstWhereOrNull(
            (messageType) => messageType.name == stored.messageType,
          ) ??
          MessageType.text,
      encryptedMessage: stored.encryptedMessage,
      decryptedMessage: decryptedMessage,
      sentAt: stored.sentAt,
      isSent: stored.isSent,
    );
  }

  MessageData copyWith({
    int? id,
    String? chatId,
    MessageType? type,
    String? encryptedMessage,
    String? decryptedMessage,
    DateTime? sentAt,
    bool? isSent,
  }) {
    return MessageData(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      type: type ?? this.type,
      encryptedMessage: encryptedMessage ?? this.encryptedMessage,
      decryptedMessage: decryptedMessage ?? this.decryptedMessage,
      sentAt: sentAt ?? this.sentAt,
      isSent: isSent ?? this.isSent,
    );
  }

  @override
  String toString() {
    return 'MessageData(id: $id, chatId: $chatId, type: $type, encryptedMessage: $encryptedMessage, decryptedMessage: $decryptedMessage, sentAt: $sentAt, isSent: $isSent)';
  }
}
