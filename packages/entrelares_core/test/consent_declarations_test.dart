/// Mirror of `entrelares-app` `Entrelares.Tests/ConsentDeclarationsTests.cs`.
///
/// The last two facts pin the approved PT-BR wording VERBATIM. That is the
/// point of the class: the declaration is a legal instrument, and a paraphrase
/// introduced by a refactor would change what people accepted without anyone
/// noticing. If one of these fails, the fix is to restore the text — not to
/// update the expectation.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  test('the founder gets the awareness declaration (A-1.1)', () {
    expect(ConsentDeclarations.forPath(false), ConsentDeclarations.creator);
  });

  test('the invitee gets the confidentiality declaration (A-1.2)', () {
    expect(ConsentDeclarations.forPath(true), ConsentDeclarations.invitee);
  });

  test('the two declarations are different texts', () {
    expect(ConsentDeclarations.creator, isNot(ConsentDeclarations.invitee));
    expect(ConsentDeclarations.creatorEn, isNot(ConsentDeclarations.inviteeEn));
  });

  // S-22 (phase 6): the wording moved ON PURPOSE — the app gained a first-name
  // field for the child (F-55), so "no dedicated fields" stopped being true.
  // The new text went through the owner's review of the phase-6 material
  // version, like the one it replaces went through the legal review.
  test('the founder declaration matches the approved wording', () {
    expect(
      ConsentDeclarations.creator,
      'Ao criar a família, declaro estar ciente de que o único campo próprio '
      'para dados da criança é o seu primeiro nome. Comprometo-me, no uso da '
      'minha autoridade parental, a inserir apenas as informações da criança '
      'estritamente necessárias à rotina — no cadastro, na agenda e nos campos '
      'de texto livre.',
    );
  });

  test('the invitee declaration matches the approved wording', () {
    expect(
      ConsentDeclarations.invitee,
      'Declaro ter sido convidado(a) para acessar o calendário desta família e '
      'comprometo-me a manter estrita confidencialidade sobre as informações e '
      'a rotina da criança/adolescente, utilizando o aplicativo exclusivamente '
      'para a organização da convivência.',
    );
  });

  group('U-13 courtesy translations', () {
    test('English selects the same branch', () {
      expect(ConsentDeclarations.forPath(false, english: true),
          ConsentDeclarations.creatorEn);
      expect(ConsentDeclarations.forPath(true, english: true),
          ConsentDeclarations.inviteeEn);
    });

    test('both English texts exist — the binding one is still PT-BR', () {
      expect(ConsentDeclarations.creatorEn.trim(), isNotEmpty);
      expect(ConsentDeclarations.inviteeEn.trim(), isNotEmpty);
    });
  });
}
