/// The `children` row — a child of the family (F-55).
///
/// Only the first name and an order, on purpose: it is the minimum the agenda
/// and the PDF need, and the minimum the privacy policy has to disclose. Only
/// an admin writes it, and only through `add_child` / `rename_child` /
/// `remove_child`; every member of the family reads it.
class Child {
  final int id;
  final int familyId;

  /// The first name, already trimmed and collapsed by the server (1–40).
  final String firstName;

  /// Display order — v1 renders one child; a selector will read this.
  final int sortOrder;

  const Child({
    required this.id,
    required this.familyId,
    required this.firstName,
    required this.sortOrder,
  });

  factory Child.fromJson(Map<String, dynamic> json) => Child(
        id: json['id'] as int,
        familyId: (json['family_id'] as int?) ?? 0,
        firstName: (json['first_name'] as String?) ?? '',
        sortOrder: (json['sort_order'] as int?) ?? 0,
      );
}
