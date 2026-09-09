/// The notification composition mirror — the stored PT-BR fallback sentences
/// must stay BYTE-IDENTICAL to what `SwapRequestService.cs` writes (the same
/// discipline as `notification_renderer_test.dart`, from the other side: that
/// suite pins how stored sentences render, this one pins what gets stored).
/// The C# has no unit suite for these strings (they live inline in the
/// service); the expected literals below were transcribed from
/// `SwapRequestService.cs` on 19/08/2026 and are the contract.
library;

import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

final _date = DateTime(2026, 9, 5);

const _members = [
  MemberView(id: 1, fullName: 'Ana Prado'),
  MemberView(id: 2, fullName: 'Bruno Prado'),
  MemberView(id: 3, fullName: 'Carla Souza'),
  MemberView(id: 4, fullName: 'Davi Lima'),
];

void main() {
  group('composeSwapCreated', () {
    test('scenario A — the planned responsible proposes the target', () {
      final drafts = composeSwapCreated(
        scheduleDate: _date,
        requesterId: 1,
        requesterName: 'Ana Prado',
        targetId: 2,
        targetName: 'Bruno Prado',
        targetIsProposed: true,
        creationTag: SwapPriorityTag.none,
        requestMessage: 'Tenho consulta médica',
        environmentPrefix: '',
      );

      expect(drafts, hasLength(2));

      final sent = drafts[0];
      expect(sent.recipientProfileId, 1);
      expect(sent.type, 'swap_sent');
      expect(sent.title, 'Solicitação de troca enviada');
      expect(sent.message,
          'Você solicitou uma troca de guarda para o dia 05/09/2026. Aguardando resposta de Bruno Prado.');
      expect(sent.params, {'date': '2026-09-05', 'name': 'Bruno Prado'});
      expect(sent.bestEffort, isFalse);

      final requested = drafts[1];
      expect(requested.recipientProfileId, 2);
      expect(requested.type, 'swap_requested');
      expect(requested.title, 'Nova solicitação de troca');
      expect(requested.message,
          'Ana Prado solicitou que você fique responsável pela criança no dia 05/09/2026. Mensagem: Tenho consulta médica');
      expect(requested.params, {
        'date': '2026-09-05',
        'name': 'Ana Prado',
        'proposed': 'target',
        'msg': 'Tenho consulta médica',
      });
    });

    test('scenario B — the requester proposes THEMSELVES on the target\'s day',
        () {
      final drafts = composeSwapCreated(
        scheduleDate: _date,
        requesterId: 2,
        requesterName: 'Bruno Prado',
        targetId: 1,
        targetName: 'Ana Prado',
        targetIsProposed: false,
        creationTag: SwapPriorityTag.none,
        environmentPrefix: '',
      );

      // Inverting this wording inverted the request's meaning — the exact
      // production bug the service comment records.
      expect(drafts[1].message,
          'Bruno Prado solicitou ficar responsável pela criança no dia 05/09/2026 no seu lugar.');
      expect(drafts[1].params['proposed'], 'requester');
      expect(drafts[1].params.containsKey('msg'), isFalse);
    });

    test('the creation tag prefixes BOTH stored titles and rides params', () {
      final drafts = composeSwapCreated(
        scheduleDate: _date,
        requesterId: 1,
        requesterName: 'Ana Prado',
        targetId: 2,
        targetName: 'Bruno Prado',
        targetIsProposed: true,
        creationTag: SwapPriorityTag.urgent,
        environmentPrefix: '',
      );
      expect(drafts[0].title, '⚠️ URGENTE: Solicitação de troca enviada');
      expect(drafts[1].title, '⚠️ URGENTE: Nova solicitação de troca');
      expect(drafts[0].params['tag'], 'urgent');
      expect(drafts[1].params['tag'], 'urgent');
    });

    test('the environment prefix leads the title and NEVER rides params', () {
      final drafts = composeSwapCreated(
        scheduleDate: _date,
        requesterId: 1,
        requesterName: 'Ana Prado',
        targetId: 2,
        targetName: 'Bruno Prado',
        targetIsProposed: true,
        creationTag: SwapPriorityTag.overdue,
        environmentPrefix: '[Dev] ',
      );
      expect(drafts[0].title, '[Dev] ⏰ ATRASADO: Solicitação de troca enviada');
      expect(drafts[1].params.values.any((v) => v.contains('[Dev]')), isFalse);
    });

    test('a whitespace-only message stores no suffix and no msg param', () {
      final drafts = composeSwapCreated(
        scheduleDate: _date,
        requesterId: 1,
        requesterName: 'Ana Prado',
        targetId: 2,
        targetName: 'Bruno Prado',
        targetIsProposed: true,
        creationTag: SwapPriorityTag.none,
        requestMessage: '   ',
        environmentPrefix: '',
      );
      expect(drafts[1].message, endsWith('no dia 05/09/2026.'));
      expect(drafts[1].params.containsKey('msg'), isFalse);
    });
  });

  group('composeSwapApproved', () {
    test('requester + self receipt + family fan-out, scenario A wording', () {
      final drafts = composeSwapApproved(
        scheduleDate: _date,
        requestingProfileId: 1,
        targetProfileId: 2,
        proposedActualParentId: 2,
        approvalNote: 'Busco às 18h',
        allProfiles: _members,
        environmentPrefix: '',
      );

      expect(drafts, hasLength(4)); // requester, self, 2 uninvolved

      expect(drafts[0].recipientProfileId, 1);
      expect(drafts[0].type, 'swap_approved');
      expect(drafts[0].title, 'Troca aprovada! ✅');
      expect(drafts[0].message,
          'Bruno Prado aceitou ficar com a criança no dia 05/09/2026. Mensagem: Busco às 18h');
      expect(drafts[0].params, {
        'date': '2026-09-05',
        'name': 'Bruno Prado',
        'proposed': 'target',
        'msg': 'Busco às 18h',
      });

      expect(drafts[1].recipientProfileId, 2);
      expect(drafts[1].type, 'swap_approved_self');
      expect(drafts[1].title, 'Troca confirmada');
      expect(drafts[1].message,
          'Você confirmou que ficará com a criança no dia 05/09/2026.');
      expect(drafts[1].params,
          {'date': '2026-09-05', 'name': 'Bruno Prado', 'proposed': 'target'});

      final family = drafts.sublist(2);
      expect(family.map((d) => d.recipientProfileId), [3, 4]);
      for (final d in family) {
        expect(d.type, 'swap_family_info');
        expect(d.title, 'Calendário atualizado');
        expect(d.message,
            'Bruno Prado ficará com a criança no dia 05/09/2026 (troca solicitada por Ana Prado e aprovada por Bruno Prado).');
        expect(d.params, {
          'kind': 'swap',
          'date': '2026-09-05',
          'name': 'Bruno Prado',
          'requester': 'Ana Prado',
          'approver': 'Bruno Prado',
        });
        expect(d.bestEffort, isTrue,
            reason: 'family-info inserts must not fail the approval');
      }
    });

    test('scenario B wording — the approver is NOT the proposed parent', () {
      final drafts = composeSwapApproved(
        scheduleDate: _date,
        requestingProfileId: 2,
        targetProfileId: 1,
        proposedActualParentId: 2,
        allProfiles: _members,
        environmentPrefix: '',
      );
      expect(drafts[0].message,
          'Ana Prado aceitou que você fique com a criança no dia 05/09/2026.');
      expect(drafts[1].message,
          'Você confirmou que Bruno Prado ficará com a criança no dia 05/09/2026.');
      expect(drafts[0].params['proposed'], 'requester');
    });

    test('a requester who left the family gets no draft; fallbacks name the '
        'missing profiles', () {
      final drafts = composeSwapApproved(
        scheduleDate: _date,
        requestingProfileId: 99,
        targetProfileId: 2,
        proposedActualParentId: 2,
        allProfiles: _members,
        environmentPrefix: '',
      );
      expect(drafts.map((d) => d.type),
          isNot(contains('swap_approved')));
      final family = drafts.where((d) => d.type == 'swap_family_info');
      expect(family.first.message,
          'Bruno Prado ficará com a criança no dia 05/09/2026 (troca solicitada por um responsável e aprovada por Bruno Prado).');
      expect(family.first.params.containsKey('requester'), isFalse);
    });

    test('two-member family produces no fan-out', () {
      final drafts = composeSwapApproved(
        scheduleDate: _date,
        requestingProfileId: 1,
        targetProfileId: 2,
        proposedActualParentId: 2,
        allProfiles: _members.sublist(0, 2),
        environmentPrefix: '',
      );
      expect(drafts.where((d) => d.type == 'swap_family_info'), isEmpty);
    });

    test('F-56: the fan-out skips a pending member and a departed one — '
        'nobody is behind those rows to read it', () {
      const pending = MemberView(
          id: 5,
          fullName: 'Eva Pendente',
          isActiveMember: false,
          isPendingMember: true);
      const gone = MemberView(id: 6, fullName: 'Fábio', isActiveMember: false);
      final drafts = composeSwapApproved(
        scheduleDate: _date,
        requestingProfileId: 1,
        targetProfileId: 2,
        proposedActualParentId: 2,
        allProfiles: [..._members.sublist(0, 2), pending, gone],
        environmentPrefix: '',
      );
      expect(drafts.where((d) => d.type == 'swap_family_info'), isEmpty);
    });
  });

  group('composeSwapRejected', () {
    test('names the approver and rides the reason on suffix and params', () {
      final drafts = composeSwapRejected(
        scheduleDate: _date,
        requestingProfileId: 1,
        targetProfileId: 2,
        reason: ' Já tenho compromisso ',
        allProfiles: _members,
        environmentPrefix: '',
      );
      expect(drafts, hasLength(1));
      expect(drafts[0].recipientProfileId, 1);
      expect(drafts[0].type, 'swap_rejected');
      expect(drafts[0].title, 'Troca recusada ❌');
      expect(drafts[0].message,
          'Bruno Prado recusou a troca de guarda para o dia 05/09/2026. Mensagem: Já tenho compromisso');
      expect(drafts[0].params['msg'], 'Já tenho compromisso');
    });

    test('a blank reason renders no dangling label and no msg param', () {
      final drafts = composeSwapRejected(
        scheduleDate: _date,
        requestingProfileId: 1,
        targetProfileId: 2,
        reason: '   ',
        allProfiles: _members,
        environmentPrefix: '',
      );
      expect(drafts[0].message,
          'Bruno Prado recusou a troca de guarda para o dia 05/09/2026.');
      expect(drafts[0].params.containsKey('msg'), isFalse);
    });
  });

  group('composeSwapCancelled', () {
    test('tells the target, with the by_requester discriminator', () {
      final drafts = composeSwapCancelled(
        scheduleDate: _date,
        targetProfileId: 2,
        allProfiles: _members,
        environmentPrefix: '',
      );
      expect(drafts, hasLength(1));
      expect(drafts[0].recipientProfileId, 2);
      expect(drafts[0].type, 'swap_cancelled');
      expect(drafts[0].title, 'Solicitação cancelada');
      expect(drafts[0].message,
          'A solicitação de troca para o dia 05/09/2026 foi cancelada pelo solicitante.');
      // `kind` because request_account_deletion writes this SAME type with
      // completely different copy.
      expect(drafts[0].params, {'kind': 'by_requester', 'date': '2026-09-05'});
    });
  });

  group('composeRevertRequested', () {
    test('requester receipt + approver call to action, tag on both titles',
        () {
      final drafts = composeRevertRequested(
        scheduleDate: _date,
        requesterId: 1,
        requesterName: 'Ana Prado',
        approverId: 2,
        approverName: 'Bruno Prado',
        creationTag: SwapPriorityTag.urgent,
        requestMessage: 'Plano mudou',
        environmentPrefix: '',
      );

      expect(drafts, hasLength(2));

      expect(drafts[0].recipientProfileId, 1);
      expect(drafts[0].type, 'revert_sent');
      expect(drafts[0].title, '⚠️ URGENTE: Reversão de troca solicitada');
      expect(drafts[0].message,
          'Você solicitou reverter a troca de guarda do dia 05/09/2026. Aguardando confirmação de Bruno Prado.');
      expect(drafts[0].params,
          {'date': '2026-09-05', 'name': 'Bruno Prado', 'tag': 'urgent'});

      expect(drafts[1].recipientProfileId, 2);
      expect(drafts[1].type, 'revert_requested');
      expect(drafts[1].title, '⚠️ URGENTE: Pedido de reversão de troca');
      expect(drafts[1].message,
          'Ana Prado quer reverter a troca de guarda do dia 05/09/2026. Você precisa confirmar. Mensagem: Plano mudou');
      expect(drafts[1].params, {
        'date': '2026-09-05',
        'name': 'Ana Prado',
        'tag': 'urgent',
        'msg': 'Plano mudou',
      });
    });
  });

  group('composeRevertApproved', () {
    test('requester + self receipt + family fan-out naming the restored '
        'responsible', () {
      final drafts = composeRevertApproved(
        scheduleDate: _date,
        requestingProfileId: 1,
        targetProfileId: 2,
        proposedActualParentId: 1,
        approvalNote: 'Combinado',
        allProfiles: _members,
        environmentPrefix: '',
      );

      expect(drafts, hasLength(4));

      expect(drafts[0].type, 'revert_approved');
      expect(drafts[0].title, 'Reversão confirmada ✅');
      expect(drafts[0].message,
          'Bruno Prado confirmou a reversão da troca do dia 05/09/2026. O calendário voltou ao normal. Mensagem: Combinado');
      expect(drafts[0].params,
          {'date': '2026-09-05', 'name': 'Bruno Prado', 'msg': 'Combinado'});

      expect(drafts[1].type, 'revert_approved_self');
      expect(drafts[1].title, 'Reversão confirmada');
      expect(drafts[1].message,
          'Você confirmou a reversão da troca do dia 05/09/2026.');
      expect(drafts[1].params, {'date': '2026-09-05'});

      final family = drafts.sublist(2);
      expect(family.map((d) => d.recipientProfileId), [3, 4]);
      expect(family.first.message,
          'A troca do dia 05/09/2026 foi revertida — Ana Prado volta a ficar com a criança.');
      expect(family.first.params,
          {'kind': 'revert', 'date': '2026-09-05', 'name': 'Ana Prado'});
    });
  });

  group('composeRevertRejected', () {
    test('the "permanece ativa" tail comes AFTER the message suffix', () {
      final drafts = composeRevertRejected(
        scheduleDate: _date,
        requestingProfileId: 1,
        targetProfileId: 2,
        reason: 'Prefiro manter',
        allProfiles: _members,
        environmentPrefix: '',
      );
      expect(drafts, hasLength(1));
      expect(drafts[0].type, 'revert_rejected');
      expect(drafts[0].title, 'Reversão recusada ❌');
      expect(drafts[0].message,
          'Bruno Prado recusou reverter a troca do dia 05/09/2026. Mensagem: Prefiro manter A troca permanece ativa.');
      expect(drafts[0].params['msg'], 'Prefiro manter');
    });

    test('without a reason the sentence closes cleanly', () {
      final drafts = composeRevertRejected(
        scheduleDate: _date,
        requestingProfileId: 1,
        targetProfileId: 2,
        allProfiles: _members,
        environmentPrefix: '',
      );
      expect(drafts[0].message,
          'Bruno Prado recusou reverter a troca do dia 05/09/2026. A troca permanece ativa.');
    });
  });

  group('composeRevertCancelled', () {
    test('tells the approver the pedido died', () {
      final drafts = composeRevertCancelled(
        scheduleDate: _date,
        targetProfileId: 2,
        allProfiles: _members,
        environmentPrefix: '',
      );
      expect(drafts, hasLength(1));
      expect(drafts[0].recipientProfileId, 2);
      expect(drafts[0].type, 'revert_cancelled');
      expect(drafts[0].title, 'Pedido de reversão cancelado');
      expect(drafts[0].message,
          'O pedido de reversão da troca do dia 05/09/2026 foi cancelado.');
      expect(drafts[0].params, {'date': '2026-09-05'});
    });
  });

  group('stored sentences render through the NotificationRenderer', () {
    // The two halves of the U-13 contract meet: what composition stores, the
    // renderer must reproduce byte-identically for a PT-BR reader.
    test('PT-BR reader sees the stored sentence, byte-identical', () {
      final l = Localization(AppLanguage.ptBr);
      final drafts = composeSwapCreated(
        scheduleDate: _date,
        requesterId: 1,
        requesterName: 'Ana Prado',
        targetId: 2,
        targetName: 'Bruno Prado',
        targetIsProposed: true,
        creationTag: SwapPriorityTag.urgent,
        requestMessage: 'Tenho consulta',
        environmentPrefix: '',
      );
      for (final d in drafts) {
        final paramsJson = jsonEncode(d.params);
        expect(
            NotificationRenderer.message(d.type, paramsJson, d.message, l),
            d.message,
            reason: '${d.type} message must round-trip for a PT-BR reader');
        expect(NotificationRenderer.title(d.type, paramsJson, d.title, l),
            d.title,
            reason: '${d.type} title must round-trip for a PT-BR reader');
      }
    });
  });
}
