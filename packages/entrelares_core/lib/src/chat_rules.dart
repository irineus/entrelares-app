/// F-35 — the family's Conversa, as the client reads it.
///
/// The server keeps the texts (immutable) and who read them; these are the
/// small rules the screen needs on top: what is still unread for me, who read
/// a text, and a search that forgives accents and case.
library;

/// A text as these rules see it — the screen maps its rows to this.
typedef ChatLine = ({int id, int author, String body});

/// One "lida por" mark.
typedef ChatMark = ({int messageId, int profileId, DateTime readAt});

abstract final class ChatRules {
  /// How many texts I have not read yet: written by someone else, with no
  /// mark of mine.
  static int unreadFor(
      int me, Iterable<ChatLine> lines, Iterable<ChatMark> marks) {
    final mine = {
      for (final m in marks)
        if (m.profileId == me) m.messageId
    };
    return lines.where((l) => l.author != me && !mine.contains(l.id)).length;
  }

  /// The newest text id, which is what `mark_chat_read` takes; null when the
  /// Conversa is empty.
  static int? newestId(Iterable<ChatLine> lines) => lines.isEmpty
      ? null
      : lines.map((l) => l.id).reduce((a, b) => a > b ? a : b);

  /// Who read [messageId], oldest first — never the author (the server never
  /// writes the author's own mark, and this does not invent one).
  static List<ChatMark> readersOf(
          int messageId, int author, Iterable<ChatMark> marks) =>
      [
        for (final m in marks)
          if (m.messageId == messageId && m.profileId != author) m
      ]..sort((a, b) => a.readAt.compareTo(b.readAt));

  static const Map<String, String> _fold = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };

  /// Lowercase, without accents — "Ônibus" and "onibus" are the same search.
  static String fold(String text) {
    final lower = text.toLowerCase();
    final out = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      out.write(_fold[ch] ?? ch);
    }
    return out.toString();
  }

  /// Whether [body] matches [query] (every word of the query, in any order).
  /// A blank query matches everything.
  static bool matches(String body, String query) {
    final words =
        fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return true;
    final text = fold(body);
    return words.every(text.contains);
  }

  /// A one-line preview of a quoted text.
  static String snippet(String body, {int max = 80}) {
    final line = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length <= max ? line : '${line.substring(0, max - 1)}…';
  }
}
