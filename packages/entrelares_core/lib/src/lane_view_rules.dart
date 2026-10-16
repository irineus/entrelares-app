/// F-07 (PR 4) — what the calendar shows when a family plans per child.
///
/// The month holds every lane's rows. The screen shows ONE of two things:
///
/// * a child's lane — that child's rows, exactly as a single-plan family's;
/// * **Todas** (no lane) — one row per date: the family row where there is one
///   (a single-plan day, including the past of a family that switched), else
///   the first child's row in the family's order; and, where the children are
///   with DIFFERENT carers that day, the date is DIVERGENT and carries every
///   lane's row, so the cell can paint the split and a tap can ask which child.
///
/// Generic over the row type: core cannot see the contracts package, and the
/// rule is the same for a schedule row and a swap request.
library;

class LaneView<T> {
  /// One row per ISO date (`yyyy-MM-dd`) — what the cell paints.
  final Map<String, T> byIso;

  /// The dates whose lanes disagree on the carer, with every lane's row in
  /// the family's child order. Always empty in a child's lane.
  final Map<String, List<T>> divergent;

  const LaneView(this.byIso, this.divergent);
}

abstract final class LaneViewRules {
  static LaneView<T> view<T>({
    required List<T> rows,
    required String Function(T) isoOf,
    required int? Function(T) childOf,
    required int Function(T) effectiveOf,
    required int? lane,
    required List<int> childOrder,
  }) {
    if (lane != null) {
      return LaneView({
        for (final r in rows)
          if (childOf(r) == lane) isoOf(r): r,
      }, const {});
    }

    int rank(T r) {
      final child = childOf(r);
      if (child == null) return -1;
      final i = childOrder.indexOf(child);
      return i < 0 ? childOrder.length : i;
    }

    final grouped = <String, List<T>>{};
    for (final r in rows) {
      (grouped[isoOf(r)] ??= []).add(r);
    }
    final byIso = <String, T>{};
    final divergent = <String, List<T>>{};
    for (final MapEntry(key: iso, value: dayRows) in grouped.entries) {
      dayRows.sort((a, b) => rank(a).compareTo(rank(b)));
      byIso[iso] = dayRows.first;
      final lanes = [for (final r in dayRows) if (childOf(r) != null) r];
      if ({for (final r in lanes) effectiveOf(r)}.length > 1) {
        divergent[iso] = lanes;
      }
    }
    return LaneView(byIso, divergent);
  }
}
