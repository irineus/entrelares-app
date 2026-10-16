/// F-07 (owner's QA, 29/09/2026) — the pieces the calendar's people need
/// once the children have avatars too: a child's initials, the legend's
/// short name, where a carer's chip leads, and how the split day fits its
/// avatars in one cell.
library;

import 'dart:math' as math;

import 'calendar_rules.dart' show MemberView, displayInitials;

/// A child's avatar letters, per child id — the carers' rule itself
/// ([displayInitials], F-28), by the owner's decision (29/09/2026, round 3:
/// "a mesma regra de nome e avatar para os dois"): one letter while unique;
/// on a collision, the first and last words' initials ("Ana Clara" → "AC");
/// still colliding, those plus the place in id order ("B1", "B2").
Map<int, String> childInitials(Map<int, String> names) {
  final views = [
    for (final MapEntry(key: id, value: name) in names.entries)
      MemberView(id: id, fullName: name),
  ];
  return {for (final v in views) v.id: displayInitials(v.id, views)};
}

/// The short name on a person's chip — a carer's in the legend and, since
/// round 3 (owner, 29/09/2026), a child's in the lane row too: the first
/// word while it is unique in the family, else that word and the last
/// word's initial ("Ana S.", "Ana C.").
/// The role left the legend (owner, 29/09/2026) — the chip leads to the
/// person instead.
Map<int, String> legendNames(Map<int, String> fullNames) {
  List<String> parts(String n) =>
      n.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  String first(String n) {
    final p = parts(n);
    return p.isEmpty ? '?' : p.first;
  }

  return {
    for (final MapEntry(key: id, value: name) in fullNames.entries)
      id: () {
        final f = first(name);
        final clash =
            fullNames.values.where((n) => first(n) == f).length > 1;
        final p = parts(name);
        if (!clash || p.length < 2) return f;
        return '$f ${p.last[0].toUpperCase()}.';
      }(),
  };
}

/// Where a carer's legend chip leads.
enum MemberLinkTarget { ownProfile, memberProfile, family }

/// My own chip opens my profile; an admin opens anyone's (F-16: another
/// member's profile is an ADMIN surface); anyone else lands on the Família,
/// where the roster says who the person is.
MemberLinkTarget memberLinkTarget({required bool isOwn, required bool iAmAdmin}) =>
    isOwn
        ? MemberLinkTarget.ownProfile
        : iAmAdmin
            ? MemberLinkTarget.memberProfile
            : MemberLinkTarget.family;

/// How the split day's columns fit one cell.
class SplitCellFit {
  /// The carer avatar's and the child avatars' diameters, in dp.
  final double carerDiameter;
  final double childDiameter;

  /// Per column: how many child avatars are drawn, and how many more hide
  /// behind a "+N" (0 = no badge).
  final List<int> shown;
  final List<int> more;

  const SplitCellFit({
    required this.carerDiameter,
    required this.childDiameter,
    required this.shown,
    required this.more,
  });

  /// Initials are drawn at these fractions of the diameter.
  static const double carerLetter = 0.55;
  static const double childLetter = 0.6;

  /// The floors of exception D (no_tiny_text_test): a child avatar never
  /// under 10 dp (its letter never under 6), a carer's never under 14.
  static const double minCarer = 14;
  static const double minChild = 10;

  /// Child avatars overlap by a third of their size, as in the mockup.
  static const double overlap = 1 / 3;
}

/// F-07 (owner's QA, 29/09/2026) — the split day in columns: one per carer
/// (the carer's avatar on top, the children below), sized to the cell's
/// [width]. [avatarDiameter] is the cell's usual avatar (the U-39 step);
/// [childrenPerColumn] counts each carer's children, in column order.
///
/// A column that cannot hold every child shows as many as fit, the last
/// place taken by the "+N" badge.
SplitCellFit fitSplitCell({
  required double width,
  required double avatarDiameter,
  required List<int> childrenPerColumn,
}) {
  final n = math.max(1, childrenPerColumn.length);
  final column = width / n;
  final carer = math.max(
      SplitCellFit.minCarer, math.min(avatarDiameter, column - 2));
  final child = math.max(SplitCellFit.minChild, carer * 0.66);
  final step = child * (1 - SplitCellFit.overlap);
  // How many overlapping child avatars fit the column's width.
  final capacity = math.max(1, ((column - child) / step).floor() + 1);
  final shown = <int>[];
  final more = <int>[];
  for (final kids in childrenPerColumn) {
    if (kids <= capacity) {
      shown.add(kids);
      more.add(0);
    } else {
      // The badge takes the last place.
      final visible = math.max(0, capacity - 1);
      shown.add(visible);
      more.add(kids - visible);
    }
  }
  return SplitCellFit(
    carerDiameter: carer,
    childDiameter: child,
    shown: shown,
    more: more,
  );
}
