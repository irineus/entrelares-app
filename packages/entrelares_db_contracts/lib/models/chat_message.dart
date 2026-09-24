/// F-35 — the family's Conversa, as a member reads it. Written only through
/// `send_chat_message`; immutable on the server (no edit, no delete).
library;

int _int(Object? raw) => raw is int ? raw : int.parse('$raw');
int? _intOrNull(Object? raw) => raw == null ? null : _int(raw);

class ChatMessage {
  final int id;
  final int authorProfileId;
  final String body;

  /// The message this one replies to (same family), or null.
  final int? quoteId;

  /// A calendar day the author cited, or null.
  final DateTime? quotedDay;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.authorProfileId,
    required this.body,
    required this.createdAt,
    this.quoteId,
    this.quotedDay,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: _int(json['id']),
        authorProfileId: _int(json['author_profile_id']),
        body: json['body'] as String,
        quoteId: _intOrNull(json['quote_id']),
        quotedDay: json['quoted_day'] == null
            ? null
            : DateTime.parse(json['quoted_day'] as String),
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      );
}

/// "Lida por": who read a message, and when.
class ChatRead {
  final int messageId;
  final int profileId;
  final DateTime readAt;

  const ChatRead(
      {required this.messageId, required this.profileId, required this.readAt});

  factory ChatRead.fromJson(Map<String, dynamic> json) => ChatRead(
        messageId: _int(json['message_id']),
        profileId: _int(json['profile_id']),
        readAt: DateTime.parse(json['read_at'] as String).toUtc(),
      );
}
