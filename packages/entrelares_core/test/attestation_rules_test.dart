import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-64 — the verifiable report, as the client mirrors it.
void main() {
  const id = '3f2c9a1e-7b4d-4c2a-9e8f-0a1b2c3d4e5f';

  test('the QR opens the environment\'s own host — never a hard-coded one',
      () {
    expect(AttestationRules.url('https://qa.entrelares.app', id),
        'https://qa.entrelares.app/verificar/$id');
    expect(AttestationRules.url('https://web.entrelares.app/', id),
        'https://web.entrelares.app/verificar/$id');
    expect(AttestationRules.address('https://web.entrelares.app', id),
        'web.entrelares.app/verificar/$id');
  });

  test('the id is a capability: analytics and crash reports never carry it',
      () {
    expect(sanitizeAnalyticsPath('/verificar/$id'), '/verificar/:id');
    expect(sanitizeAnalyticsPath('https://web.entrelares.app/verificar/$id'),
        '/verificar/:id');
    expect(scrubCrashLocation('https://web.entrelares.app/verificar/$id'),
        isNot(contains(id)));
    expect(scrubCrashMessage('failed on /verificar/$id'), isNot(contains(id)));
  });

  test('the state is a closed set; a future shape reads as unknown', () {
    expect(AttestationState.parse('valid'), AttestationState.valid);
    expect(AttestationState.parse('revoked'), AttestationState.revoked);
    expect(AttestationState.parse('something_new'), AttestationState.unknown);
    expect(AttestationState.parse(null), AttestationState.unknown);
  });

  test('ids and fingerprints', () {
    expect(AttestationRules.isId(id), isTrue);
    expect(AttestationRules.isId('not-an-id'), isFalse);
    final hex = 'ab12' * 16;
    expect(AttestationRules.groupFingerprint(hex).split(' '), hasLength(16));
    expect(AttestationRules.sameFingerprint(hex, hex.toUpperCase()), isTrue);
    expect(
        AttestationRules.sameFingerprint(
            AttestationRules.groupFingerprint(hex), hex),
        isTrue);
    expect(AttestationRules.sameFingerprint(hex, 'cd34' * 16), isFalse);
    expect(AttestationRules.sameFingerprint('ab', 'ab'), isFalse);
  });

  test('the attestation flag reads its seed until the server answers', () {
    expect(PublicSettings.unloaded.reportAttestationEnabled, isFalse);
    expect(
        const PublicSettings({'feature.report_attestation': 'true'})
            .reportAttestationEnabled,
        isTrue);
  });
}
