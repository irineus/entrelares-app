import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-07 (PR 4) — the calendar's view of a family that plans per child.
typedef _Row = ({String iso, int? child, int carer});

void main() {
  LaneView<_Row> view(List<_Row> rows, {int? lane}) => LaneViewRules.view(
        rows: rows,
        isoOf: (r) => r.iso,
        childOf: (r) => r.child,
        effectiveOf: (r) => r.carer,
        lane: lane,
        childOrder: const [20, 10],
      );

  const lia = 20, theo = 10, ana = 1, bruno = 2;

  test("a child's lane is that child's rows and nothing else", () {
    final v = view([
      (iso: '2026-10-01', child: lia, carer: ana),
      (iso: '2026-10-01', child: theo, carer: bruno),
      (iso: '2026-10-02', child: theo, carer: ana),
    ], lane: theo);
    expect(v.byIso.keys, ['2026-10-01', '2026-10-02']);
    expect(v.byIso['2026-10-01']!.carer, bruno);
    expect(v.divergent, isEmpty);
  });

  test('Todas: the children agree — one row, not divergent', () {
    final v = view([
      (iso: '2026-10-01', child: theo, carer: ana),
      (iso: '2026-10-01', child: lia, carer: ana),
    ]);
    expect(v.byIso['2026-10-01']!.child, lia,
        reason: "the family's order puts Lia first");
    expect(v.divergent, isEmpty);
  });

  test('Todas: the children disagree — the date carries every lane, in order',
      () {
    final v = view([
      (iso: '2026-10-03', child: theo, carer: bruno),
      (iso: '2026-10-03', child: lia, carer: ana),
    ]);
    expect([for (final r in v.divergent['2026-10-03']!) r.child], [lia, theo]);
    expect(v.byIso['2026-10-03']!.child, lia);
  });

  test("Todas: a family row (single-plan past) wins and is never split", () {
    final v = view([
      (iso: '2026-09-01', child: null, carer: bruno),
    ]);
    expect(v.byIso['2026-09-01']!.child, isNull);
    expect(v.divergent, isEmpty);
  });

  test('a date only one child has planned is shown, not divergent', () {
    final v = view([(iso: '2026-10-05', child: theo, carer: bruno)]);
    expect(v.byIso['2026-10-05']!.child, theo);
    expect(v.divergent, isEmpty);
  });
}
