import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-35 — the Conversa's client rules.
void main() {
  final t0 = DateTime.utc(2026, 9, 24, 10);
  final lines = <ChatLine>[
    (id: 1, author: 1, body: 'Busco às 18h.'),
    (id: 2, author: 2, body: 'Combinado. Levo o ônibus escolar.'),
    (id: 3, author: 1, body: 'Obrigado!'),
  ];
  final marks = <ChatMark>[
    (messageId: 1, profileId: 2, readAt: t0.add(const Duration(minutes: 5))),
    (messageId: 1, profileId: 3, readAt: t0.add(const Duration(minutes: 2))),
    (messageId: 2, profileId: 1, readAt: t0.add(const Duration(minutes: 9))),
  ];

  test('unread: written by someone else and not marked by me', () {
    expect(ChatRules.unreadFor(2, lines, marks), 1); // id 3
    expect(ChatRules.unreadFor(1, lines, marks), 0);
    expect(ChatRules.unreadFor(3, lines, marks), 2); // ids 2 and 3
  });

  test('the newest id is what mark_chat_read takes', () {
    expect(ChatRules.newestId(lines), 3);
    expect(ChatRules.newestId(const []), isNull);
  });

  test('"lida por": oldest first, never the author', () {
    final readers = ChatRules.readersOf(1, 1, [
      ...marks,
      (messageId: 1, profileId: 1, readAt: t0),
    ]);
    expect(readers.map((m) => m.profileId), [3, 2]);
  });

  test('search forgives accents and case, and needs every word', () {
    expect(ChatRules.matches('Levo o ônibus escolar.', 'ONIBUS'), isTrue);
    expect(ChatRules.matches('Levo o ônibus escolar.', 'escolar levo'), isTrue);
    expect(ChatRules.matches('Levo o ônibus escolar.', 'escolar carro'), isFalse);
    expect(ChatRules.matches('qualquer', '   '), isTrue);
  });

  test('a quote previews one line', () {
    expect(ChatRules.snippet('a\n\nb   c'), 'a b c');
    expect(ChatRules.snippet('x' * 100, max: 10), '${'x' * 9}…');
  });

  test('the chat keys read their seed until the server answers', () {
    expect(PublicSettings.unloaded.chatEnabled, isFalse);
    expect(PublicSettings.unloaded.chatMessageMaxChars, 2000);
    expect(
        const PublicSettings({'chat.message_max_chars': '500'})
            .chatMessageMaxChars,
        500);
  });
}
