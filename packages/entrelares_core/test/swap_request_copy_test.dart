import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// U-60 — the request said in plain words to whoever answers it.
void main() {
  final pt = Localization(AppLanguage.ptBr);
  final en = Localization(AppLanguage.en);
  final thursday = DateTime(2026, 10, 8);
  final saturday = DateTime(2026, 10, 10);

  test('scenario A: the reader is asked to take the day', () {
    expect(
        swapRequestSentence(
            l: pt,
            requesterName: 'Ana',
            date: thursday,
            isRevert: false,
            requesterIsProposed: false),
        'Ana pede que você fique com a criança na qui, 08/10.');
    expect(
        swapRequestSentence(
            l: en,
            requesterName: 'Ana',
            date: thursday,
            isRevert: false,
            requesterIsProposed: false),
        'Ana asks you to keep the child on Thu, 08 Oct.');
  });

  test('PT-BR genders the weekday: no sábado, no domingo', () {
    expect(swapOnDay(saturday, pt), 'no sáb, 10/10');
    expect(swapOnDay(DateTime(2026, 10, 11), pt), 'no dom, 11/10');
    expect(swapOfDay(saturday, pt), 'do sáb, 10/10');
    expect(swapOfDay(thursday, pt), 'da qui, 08/10');
  });

  test('scenario B: the requester proposes themselves on my day', () {
    expect(
        swapRequestSentence(
            l: pt,
            requesterName: 'Ana',
            date: saturday,
            isRevert: false,
            requesterIsProposed: true),
        'Ana pede para ficar com a criança no sáb, 10/10, que é seu dia.');
  });

  test('a revert says it undoes a swap', () {
    expect(
        swapRequestSentence(
            l: pt,
            requesterName: 'Ana',
            date: thursday,
            isRevert: true,
            requesterIsProposed: false),
        'Ana pede para desfazer a troca da qui, 08/10.');
    expect(
        swapRequestSentence(
            l: en,
            requesterName: 'Ana',
            date: thursday,
            isRevert: true,
            requesterIsProposed: false),
        'Ana asks to undo the swap of Thu, 08 Oct.');
  });
}
