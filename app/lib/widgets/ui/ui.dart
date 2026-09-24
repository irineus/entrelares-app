/// U-27 — the shared component set. One import for the pieces every screen
/// repeats, so a screen never has to decide what a badge looks like.
///
/// U-28 added the three the adoption pass proved were missing: the app had
/// three hand-built bulleted lists, two danger zones that had decayed into
/// loose paragraphs, and two event logs that had lost their rail.
///
/// * [AppSectionHeader], [AppCard], [AppListRow], [AppBulletList],
///   [AppTimelineEntry] — structure
/// * [showAppSheet], [AppSheetFrame], [AppSheetConfirmation],
///   [AppSheetDangerAction], [AppClearToggle], [AppFieldLabel], [AppInfoTip]
///   — sheets (U-38 added the middle three)
/// * [AppBanner], [AppBadge], [AppEmptyState], [AppDangerZone] — state
/// * [AppTextField], [AppTimeField], [AppSegmented], [AppActionPair],
///   [AppAvatar] — action
/// * [AppShrinkToFit] — a one-liner that shrinks to fit, never under 0.85×
///   (U-48: the floor `FittedBox.scaleDown` never had)
library;

export 'controls.dart';
export 'fit.dart';
export 'signals.dart';
export 'surfaces.dart';
export 'sheets.dart';
export 'confirm_sheet.dart';
export 'skeleton.dart';
