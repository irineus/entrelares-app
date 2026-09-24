import 'dart:convert';

/// The `notifications` row. Mirrors `Entrelares/Models/AppNotification.cs`.
/// `params` is the U-13 render payload (VALUES only, never a sentence) that
/// [NotificationRenderer] rebuilds in the READER's language; the stored
/// `title`/`message` are the PT-BR fallback sentences.
class AppNotification {
  final int id;
  final int recipientProfileId;
  final String type;
  final String title;
  final String message;
  final Map<String, dynamic>? params;
  final int? swapRequestId;
  final bool isRead;
  final String? createdAt;

  const AppNotification({
    required this.id,
    required this.recipientProfileId,
    required this.type,
    required this.title,
    required this.message,
    this.params,
    this.swapRequestId,
    this.isRead = false,
    this.createdAt,
  });

  /// What `NotificationRenderer` takes — the raw JSON text, null when the
  /// row predates U-13 (legacy rows fall back to the stored sentence).
  String? get paramsJson => params == null ? null : jsonEncode(params);

  /// F-55 PR 4: false for a row whose author chose "phone only" — it exists
  /// so the push can render from it, is born read, and stays off the list.
  bool get shownInApp => params?['in_app'] != 'false';

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as int,
        recipientProfileId: json['recipient_profile_id'] as int,
        type: (json['type'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        message: (json['message'] as String?) ?? '',
        params: (json['params'] as Map?)?.cast<String, dynamic>(),
        swapRequestId: json['swap_request_id'] as int?,
        isRead: (json['is_read'] as bool?) ?? false,
        createdAt: json['created_at'] as String?,
      );
}
