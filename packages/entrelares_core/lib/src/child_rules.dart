/// F-55 — the child entity's client-side mirror.
///
/// The server (`add_child` / `rename_child`, through `child_normalize_name`)
/// is the rule: flag on, caller an admin, name unique in the family ignoring
/// case. Only the two cheap, unambiguous checks live here, and their messages
/// are the RPC's own PT-BR wording byte for byte — the `CustomRoleRules`
/// convention — so a rule that trips on either side reads identically.
library;

/// F-07 — why a new child would be refused, or [none].
enum ChildAddBlock { none, freeCap, maxCap }

abstract final class ChildRules {
  /// The column CHECK and `child_normalize_name` both say 40.
  static const int maxNameLength = 40;

  /// U-61 — the key the founder's sign-up metadata carries the child's first
  /// name under. The server (`child_name_capture_on_signup`) writes the child
  /// and STRIPS the key before the auth row is stored; the Google door sends
  /// the same word as `p_child_first_name`.
  static const String signupMetadataKey = 'child_first_name';

  /// U-61 (owner, 07/10/2026) — the name the app says where it said "a
  /// criança": only when the family has EXACTLY one child. None keeps the
  /// generic word; two or more decide by context (the lane) or stay generic,
  /// because "Sofia" over a day that is Theo's is a wrong sentence.
  static String? singleName(Iterable<String> names) {
    final clean = [for (final n in names) if (n.trim().isNotEmpty) n.trim()];
    return clean.length == 1 ? clean.single : null;
  }

  /// What the server stores: trimmed, inner runs of whitespace collapsed.
  static String normalize(String? name) =>
      (name ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

  /// The error message, or null when the name is acceptable.
  static String? validateName(String? name) {
    final clean = normalize(name);
    if (clean.isEmpty) return 'Informe o primeiro nome da criança.';
    // Code points, like the database's char_length.
    if (clean.runes.length > maxNameLength) {
      return 'O nome da criança pode ter no máximo $maxNameLength caracteres.';
    }
    return null;
  }

  /// How the children read in one line (the Família row, the PDF header):
  /// "Lia", "Lia e Theo", "Lia, Theo e Nina" — the list joined in the reader's
  /// language with [and] as the last separator. Empty in, null out.
  static String? joinNames(List<String> names, {required String and}) {
    final clean = [for (final n in names) if (n.trim().isNotEmpty) n.trim()];
    if (clean.isEmpty) return null;
    if (clean.length == 1) return clean.single;
    return '${clean.sublist(0, clean.length - 1).join(', ')} $and ${clean.last}';
  }

  /// F-07 — what the *Crianças* page OFFERS, mirroring `add_child`: the
  /// ceiling (`children.max_per_family`) for every plan, and from
  /// `children.free_max` on, Premium. The server is the rule; this only keeps
  /// the page from offering a door it would refuse. A downgraded family keeps
  /// every child it has — it only meets [ChildAddBlock.freeCap] on the next.
  static ChildAddBlock addBlock({
    required int childrenTaken,
    required bool isPremium,
    required int freeMax,
    required int maxPerFamily,
  }) {
    if (childrenTaken >= maxPerFamily) return ChildAddBlock.maxCap;
    if (!isPremium && childrenTaken >= freeMax) return ChildAddBlock.freeCap;
    return ChildAddBlock.none;
  }
}
