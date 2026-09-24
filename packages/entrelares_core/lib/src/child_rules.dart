/// F-55 — the child entity's client-side mirror.
///
/// The server (`add_child` / `rename_child`, through `child_normalize_name`)
/// is the rule: flag on, caller an admin, name unique in the family ignoring
/// case. Only the two cheap, unambiguous checks live here, and their messages
/// are the RPC's own PT-BR wording byte for byte — the `CustomRoleRules`
/// convention — so a rule that trips on either side reads identically.
library;

abstract final class ChildRules {
  /// The column CHECK and `child_normalize_name` both say 40.
  static const int maxNameLength = 40;

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
}
