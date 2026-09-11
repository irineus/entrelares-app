/// U-27 — the shared component set. One import for the pieces every screen
/// repeats, so a screen never has to decide what a badge looks like.
///
/// U-28 added the three the adoption pass proved were missing: the app had
/// three hand-built bulleted lists, two danger zones that had decayed into
/// loose paragraphs, and two event logs that had lost their rail.
///
/// * [AppSectionHeader], [AppCard], [AppListRow], [AppBulletList],
///   [AppTimelineEntry] — structure
/// * [showAppSheet], [AppSheetFrame], [AppFieldLabel], [AppInfoTip] — sheets
/// * [AppBanner], [AppBadge], [AppEmptyState], [AppDangerZone] — state
/// * [AppTextField], [AppSegmented], [AppActionPair], [AppAvatar] — action
library;

export 'controls.dart';
export 'signals.dart';
export 'surfaces.dart';
export 'sheets.dart';
export 'skeleton.dart';
