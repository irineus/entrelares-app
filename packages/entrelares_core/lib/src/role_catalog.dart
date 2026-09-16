/// The caregiver role catalog — mirror of `entrelares-app`
/// `Entrelares/Services/RoleCatalog.cs`.
///
/// The DATABASE seeds the same 21 built-in roles (`roles` rows with
/// `family_id IS NULL`), but it stores only `label_pt`: the English labels and
/// the alias table live in the CLIENT, because they exist to render and to
/// resolve whatever historical spelling a row carries — never to validate.
///
/// The single most important property, and the reason custom roles (F-41) work
/// with no extra code: an unknown value passes through UNCHANGED in every
/// language. A family's own role is family data, not product vocabulary, so
/// translating it would be a bug.
library;

import 'localization/app_language.dart';

/// One built-in role: its canonical key, both labels, its emoji, and every
/// spelling that must resolve to it.
class RoleDefinition {
  /// The value stored in `roles.role_name` for this role.
  final String canonicalName;

  /// PT-BR label — the same text the DB seed carries in `label_pt`.
  final String label;

  /// English label. Lives only here: the DB has no English column.
  final String labelEn;

  /// Every accepted spelling, lowercase and including the canonical name.
  /// Aliases are globally unique across the catalog — two roles claiming one
  /// spelling would make resolution order-dependent.
  final List<String> aliases;

  const RoleDefinition(
    this.canonicalName,
    this.label,
    this.labelEn,
    this.aliases,
  );

  String labelFor(AppLanguage language) =>
      language == AppLanguage.en ? labelEn : label;
}

abstract final class RoleCatalog {
  /// The 21 built-ins, in catalog order — the order the sign-up's "Outro…"
  /// sheet lists the ones outside [signUpShortlist] (U-44).
  ///
  /// The English labels of the three gendered pairs carry "(m)"/"(f)" on
  /// purpose: the label is the ONLY thing that tells them apart. The built-ins
  /// carried an emoji until U-31 (16/09/2026) took it out of the sign-up
  /// picker, where the closed alpha read the app as homemade.
  static const List<RoleDefinition> all = [
    RoleDefinition('father', 'Pai', 'Father', ['father', 'pai']),
    RoleDefinition('mother', 'Mãe', 'Mother', ['mother', 'mãe', 'mae']),
    RoleDefinition('grandfather', 'Avô', 'Grandfather',
        ['grandfather', 'avô', 'avo']),
    RoleDefinition(
        'grandmother', 'Avó', 'Grandmother', ['grandmother', 'avó']),
    RoleDefinition('great_grandfather', 'Bisavô', 'Great-grandfather',
        ['great_grandfather', 'bisavô', 'bisavo']),
    RoleDefinition('great_grandmother', 'Bisavó', 'Great-grandmother',
        ['great_grandmother', 'bisavó']),
    RoleDefinition(
        'stepfather', 'Padrasto', 'Stepfather', ['stepfather', 'padrasto']),
    RoleDefinition('stepmother', 'Madrasta', 'Stepmother',
        ['stepmother', 'madrasta']),
    RoleDefinition('uncle', 'Tio', 'Uncle', ['uncle', 'tio']),
    RoleDefinition('aunt', 'Tia', 'Aunt', ['aunt', 'tia']),
    RoleDefinition(
        'godfather', 'Padrinho', 'Godfather', ['godfather', 'padrinho']),
    RoleDefinition(
        'godmother', 'Madrinha', 'Godmother', ['godmother', 'madrinha']),
    RoleDefinition(
        'brother', 'Irmão', 'Brother', ['brother', 'irmão', 'irmao']),
    RoleDefinition(
        'sister', 'Irmã', 'Sister', ['sister', 'irmã', 'irma']),
    RoleDefinition('cousin_m', 'Primo', 'Cousin (m)',
        ['cousin_m', 'primo']),
    RoleDefinition('cousin_f', 'Prima', 'Cousin (f)',
        ['cousin_f', 'prima']),
    RoleDefinition('friend_m', 'Amigo', 'Friend (m)', ['friend_m', 'amigo']),
    RoleDefinition('friend_f', 'Amiga', 'Friend (f)', ['friend_f', 'amiga']),
    RoleDefinition('guardian_m', 'Tutor', 'Guardian (m)',
        ['guardian_m', 'tutor']),
    RoleDefinition('guardian_f', 'Tutora', 'Guardian (f)',
        ['guardian_f', 'tutora']),
    RoleDefinition('nanny', 'Babá', 'Nanny', ['nanny', 'babá', 'baba']),
  ];

  /// U-44 — the roles the sign-up picker shows as chips, in this order (owner,
  /// 16/09/2026). Everything else sits one tap further, behind "Outro…": 21
  /// chips in a wrap were a wall, and these six answer almost every founder —
  /// the step-parents included, because recomposed families are the people
  /// shared custody is for.
  static const List<String> signUpShortlist = [
    'father',
    'mother',
    'grandfather',
    'grandmother',
    'stepfather',
    'stepmother',
  ];

  /// The shortlist as definitions, in [signUpShortlist]'s order.
  static List<RoleDefinition> get shortlist =>
      [for (final name in signUpShortlist) find(name)!];

  /// The built-ins NOT in the shortlist, in catalog order — what the
  /// "Outro…" sheet lists.
  static List<RoleDefinition> get others => [
        for (final definition in all)
          if (!signUpShortlist.contains(definition.canonicalName)) definition,
      ];

  /// Resolves any stored spelling to its definition, or null when the value is
  /// not a built-in (every F-41 custom role lands here). Case- and
  /// accent-tolerant only through the alias table — there is no normalisation
  /// beyond trim + lowercase, exactly as in C#.
  static RoleDefinition? find(String roleName) {
    final normalized = roleName.trim().toLowerCase();
    for (final definition in all) {
      if (definition.aliases.contains(normalized)) return definition;
    }
    return null;
  }

  /// The display label for a stored role name. Unknown values (custom roles)
  /// come back untouched — in BOTH languages.
  static String translate(String roleName,
          [AppLanguage language = AppLanguage.ptBr]) =>
      find(roleName)?.labelFor(language) ?? roleName;
}
