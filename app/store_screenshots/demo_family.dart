// T-97 — the demo family the Play screenshots show, and the app shell they
// show it in.
//
// The family is FICTIONAL (owner, 02/10/2026): Ana (mãe) and Bruno (pai),
// their children Lia and Theo, the grandmother Rosa and the nanny Carla as a
// Visualizador. Every screen below is the app's real widget, reading this
// family through the same fake data source the widget suites use
// (`test/calendar_slice_test.dart`); nothing on the phone is drawn by hand.
//
// The calendar has no clock to inject, so every date is relative to the day
// the harness runs: the month on screen is always populated.
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/screens/communication_screen.dart';
import 'package:entrelares_app/screens/expenses_screen.dart';
import 'package:entrelares_app/screens/family_screen.dart';
import 'package:entrelares_app/screens/home_shell.dart';
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/screens/reports_screen.dart';
import 'package:entrelares_app/services/account_identity.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/chat_view.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/chat_message.dart';
import 'package:entrelares_db_contracts/models/child.dart';
import 'package:entrelares_db_contracts/models/child_event.dart';
import 'package:entrelares_db_contracts/models/expense.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/report_attestation.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../test/calendar_slice_test.dart' show FakeCustodyDataSource;

// ─────────────────────────────────────────────────────────── people ──

const roleMother = Role(id: 1, roleName: 'mother');
const roleFather = Role(id: 2, roleName: 'father');
const roleGrandmother = Role(id: 3, roleName: 'grandmother');
const roleNanny = Role(id: 4, roleName: 'nanny');

/// The signed-in member on every screen: the fake's own profile is the first
/// member of the list.
const ana = Member(
  id: 1,
  familyId: 7,
  fullName: 'Ana Martins',
  colorSlot: 1,
  userId: 'u1',
  isAdmin: true,
  roleId: 1,
  email: 'ana@exemplo.com',
);
const bruno = Member(
  id: 2,
  familyId: 7,
  fullName: 'Bruno Costa',
  colorSlot: 2,
  userId: 'u2',
  roleId: 2,
  email: 'bruno@exemplo.com',
);

/// A third caregiver — beyond `free_caregivers`, so a scene with her in it is
/// a Premium family's.
const rosa = Member(
  id: 3,
  familyId: 7,
  fullName: 'Rosa Martins',
  colorSlot: 3,
  userId: 'u3',
  roleId: 3,
  email: 'rosa@exemplo.com',
);

/// A Visualizador: sees the plan, writes nothing, never on a day.
const carla = Member(
  id: 4,
  familyId: 7,
  fullName: 'Carla Nunes',
  userId: 'u4',
  roleId: 4,
  membershipType: 'viewer',
  email: 'carla@exemplo.com',
);

const lia = Child(id: 5, familyId: 7, firstName: 'Lia', sortOrder: 0);
const theo = Child(id: 6, familyId: 7, firstName: 'Theo', sortOrder: 1);

/// The modules live in production since S-22 (25/09/2026), F-75 and F-07 —
/// the same switches a real family's app reads. The `*.premium_only` keys are
/// left at their seeds (Premium).
const productionFlags = {
  'feature.child_agenda': 'true',
  'feature.viewers': 'true',
  'feature.report_attestation': 'true',
  'feature.expenses': 'true',
  'feature.chat': 'true',
  'feature.day_account_replies': 'true',
  'feature.per_child_schedule': 'true',
};

// ─────────────────────────────────────────────────────────── dates ──

DateTime get now => DateTime.now();
DateTime get today => DateTime(now.year, now.month, now.day);
DateTime day(int offset) =>
    DateTime(today.year, today.month, today.day + offset);

/// The plan: Ana during the week, Bruno every Wednesday and every other
/// weekend (Friday to Sunday) — one of the most common arrangements.
int plannedCarer(DateTime d) {
  final week =
      DateTime(
        d.year,
        d.month,
        d.day,
      ).difference(DateTime(2026, 1, 5)).inDays ~/
      7;
  if (d.weekday == DateTime.wednesday) return bruno.id;
  if (d.weekday >= DateTime.friday && week.isEven) return bruno.id;
  return ana.id;
}

/// The next day, from [from] on, that [test] accepts.
DateTime nextDay(DateTime from, bool Function(DateTime d) test) {
  var d = from;
  while (!test(d)) {
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return d;
}

/// The Saturday Bruno asks for: Ana's weekend, at least two days ahead.
DateTime get requestedSaturday => nextDay(
  day(2),
  (d) => d.weekday == DateTime.saturday && plannedCarer(d) == ana.id,
);

/// A day already swapped: Bruno has the Thursday after one of his Wednesdays,
/// at least three days ahead.
DateTime get swappedDay => nextDay(
  day(3),
  (d) => d.weekday == DateTime.thursday && d != requestedSaturday,
);

/// Days already swapped in the past, each to the other parent — what the
/// Resumo counts as given and received.
List<DateTime> get pastSwaps => [day(-23), day(-51), day(-86), day(-120)];

/// From the 1st of January (December, in January) to four months ahead: the
/// Resumo's year is a whole year of history, no "the plan ends" strip
/// appears, and every month the calendar can show is painted.
///
/// [carerOf] replaces [plannedCarer] for the days it answers (the T-102 ad
/// kit's holiday scene); the transitions and their times follow from it.
List<CareSchedule> plan({int? Function(DateTime d)? carerOf}) {
  final start = DateTime(today.year, today.month == 1 ? 0 : 1, 1);
  final end = DateTime(today.year, today.month + 4, 1);
  final rows = <CareSchedule>[];
  var id = 1000;
  int? previous;
  for (
    var d = start;
    d.isBefore(end);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    final carer = carerOf?.call(d) ?? plannedCarer(d);
    final other = carer == ana.id ? bruno.id : ana.id;
    final swappedTo = d == swappedDay
        ? bruno.id
        : pastSwaps.contains(d)
        ? other
        : null;
    final swapped = swappedTo != null && swappedTo != carer;
    final effective = swapped ? swappedTo : carer;
    rows.add(
      CareSchedule.fromJson({
        'id': id++,
        'schedule_date': CareSchedule.isoDate(d),
        'scheduled_parent_id': carer,
        'actual_parent_id': swapped ? swappedTo : null,
        'revision': 1,
        'revision_token': 'tok-$id',
        if (previous != null && previous != effective)
          'handoff_time': effective == bruno.id ? '18:00' : '08:00',
      }),
    );
    previous = effective;
  }
  return rows;
}

// ─────────────────────────────────────────────────────────── texts ──

/// The family's own words — what they typed, in the screenshot's language.
class DemoTexts {
  final bool en;
  const DemoTexts(this.en);

  String get swapMessage => en
      ? "Can I have them this Saturday? It's my dad's birthday."
      : 'Posso ficar com eles no sábado? É o aniversário do meu pai.';

  String pick(String pt, String english) => en ? english : pt;
}

/// The Conversa between Ana and Bruno, oldest first — short enough that the
/// Conversa's own notice and every message fit the screen whole.
List<ChatMessage> chatHistory(DemoTexts t) => [
  chatLine(
    1,
    ana.id,
    t.pick(
      'A Lia tem dentista na quinta, às 15h. A carteirinha está na mochila.',
      "Lia has the dentist on Thursday at 3 pm. Her card is in her backpack.",
    ),
    ago: const Duration(days: 1, hours: 3),
  ),
  chatLine(
    2,
    bruno.id,
    t.swapMessage,
    ago: const Duration(hours: 2),
    quotedDay: requestedSaturday,
  ),
];

/// Who read what: each side has read the other's messages, so no line reads
/// "not read yet".
List<ChatRead> chatReadsOf(List<ChatMessage> messages) => [
  for (final m in messages)
    ChatRead(
      messageId: m.id,
      profileId: m.authorProfileId == ana.id ? bruno.id : ana.id,
      readAt: m.createdAt.add(const Duration(minutes: 12)),
    ),
];

/// Shared expenses of the last weeks, newest first — all in the family's
/// group (the screen opens on it), so the list shows every one of them.
List<Expense> expenseList(DemoTexts t) => [
  expense(
    1,
    description: t.pick('Mensalidade', 'School fees'),
    category: 'school',
    amountCents: 98000,
    paidBy: ana.id,
    daysAgo: 1,
  ),
  expense(
    2,
    description: t.pick('Consulta da pediatra', 'Pediatrician visit'),
    category: 'health',
    amountCents: 35000,
    paidBy: bruno.id,
    daysAgo: 4,
  ),
  expense(
    3,
    description: t.pick('Natação', 'Swimming lessons'),
    category: 'activities',
    amountCents: 19000,
    paidBy: bruno.id,
    daysAgo: 6,
  ),
  expense(
    4,
    description: t.pick('Tênis novo', 'New sneakers'),
    category: 'clothes',
    amountCents: 22990,
    paidBy: ana.id,
    daysAgo: 9,
  ),
  expense(
    5,
    description: t.pick('Material escolar', 'School supplies'),
    category: 'school',
    amountCents: 15640,
    paidBy: ana.id,
    daysAgo: 12,
  ),
];

/// The agenda of [date]: both children, the kinds a family uses most.
List<ChildEvent> agendaOf(DateTime date, DemoTexts t) => [
  agendaItem(
    1,
    date,
    'school',
    child: lia,
    start: '07:30',
    body: t.pick(
      'Excursão ao museu: levar lanche',
      'Museum field trip: pack a snack',
    ),
  ),
  agendaItem(
    2,
    date,
    'health',
    child: lia,
    start: '15:00',
    body: t.pick('Dentista, Dra. Helena', 'Dentist, Dr. Helen'),
  ),
  agendaItem(
    3,
    date,
    'activity',
    child: theo,
    start: '17:00',
    end: '18:00',
    body: t.pick('Natação', 'Swimming'),
  ),
  agendaItem(
    6,
    date,
    'activity',
    child: lia,
    start: '16:30',
    end: '17:30',
    body: t.pick('Balé', 'Ballet'),
  ),
  agendaItem(
    4,
    date,
    'medicine',
    child: theo,
    start: '20:00',
    body: t.pick('Xarope, 5 ml', 'Cough syrup, 5 ml'),
  ),
  agendaItem(
    5,
    date,
    'note',
    body: t.pick(
      'Casaco do Theo ficou na casa da avó',
      "Theo's coat is at grandma's",
    ),
  ),
];

// ───────────────────────────────────────────────────── data sources ──

FakeCustodyDataSource familySource({
  required bool premium,
  List<Member> members = const [ana, bruno],
  List<Child> children = const [lia],
  int? Function(DateTime d)? carerOf,
}) => FakeCustodyDataSource(members: members, days: plan(carerOf: carerOf))
  ..family = Family(
    id: 7,
    name: 'Martins Costa',
    plan: premium ? 'premium' : 'free',
  )
  ..roles = const [roleMother, roleFather, roleGrandmother, roleNanny]
  ..children = List.of(children)
  ..publicSettings = productionFlags
  ..chatActorId = ana.id
  ..expenseActorId = ana.id;

/// Bruno's pending request for [requestedSaturday], awaiting Ana.
SwapRequest pendingRequest(DemoTexts t) => SwapRequest.fromJson({
  'id': 10,
  'schedule_date': CareSchedule.isoDate(requestedSaturday),
  'requesting_profile_id': bruno.id,
  'target_profile_id': ana.id,
  'proposed_actual_parent_id': bruno.id,
  'status': 'pending',
  'request_message': t.swapMessage,
  'created_at': now
      .subtract(const Duration(hours: 2))
      .toUtc()
      .toIso8601String(),
});

ChildEvent agendaItem(
  int id,
  DateTime date,
  String kind, {
  Child? child,
  String? start,
  String? end,
  String? body,
}) => ChildEvent(
  id: id,
  familyId: 7,
  childId: child?.id,
  eventDate: date,
  kind: kind,
  startTime: start,
  endTime: end,
  body: body,
  createdBy: ana.id,
  createdAt: now.subtract(Duration(days: 2, minutes: id)).toUtc(),
);

ChatMessage chatLine(
  int id,
  int author,
  String body, {
  required Duration ago,
  DateTime? quotedDay,
  int? quote,
}) => ChatMessage(
  id: id,
  authorProfileId: author,
  body: body,
  quotedDay: quotedDay,
  quoteId: quote,
  createdAt: now.subtract(ago).toUtc(),
);

Expense expense(
  int id, {
  required String description,
  required String category,
  required int amountCents,
  required int paidBy,
  required int daysAgo,
}) => Expense(
  id: id,
  description: description,
  category: category,
  amountCents: amountCents,
  paidBy: paidBy,
  spentOn: day(-daysAgo),
  splitMethod: 'equal',
  createdBy: paidBy,
  createdAt: day(-daysAgo).toUtc(),
  shares: [
    ExpenseShare(profileId: ana.id, weight: 1, shareCents: amountCents ~/ 2),
    ExpenseShare(
      profileId: bruno.id,
      weight: 1,
      shareCents: amountCents - amountCents ~/ 2,
    ),
  ],
);

/// The verifiable reports issued for the last two months, both still valid.
List<ReportAttestation> issuedReports() => [
  for (final back in [1, 2])
    ReportAttestation(
      id: '3f2c9a1e-7b4d-4c2a-9e8f-0a1b2c3d4e5$back',
      periodFrom: DateTime(today.year, today.month - back, 1),
      periodTo: DateTime(today.year, today.month - back + 1, 0),
      issuedAt: DateTime(today.year, today.month - back + 1, 2).toUtc(),
      expiresAt: DateTime(today.year + 1, today.month - back + 1, 2).toUtc(),
      sha256: '${back}b' * 32,
    ),
];

// ──────────────────────────────────────────────────────────── shell ──

/// The five tabs a caregiver sees in production with every module on.
enum ShellTab { calendar, family, communication, expenses, reports }

/// The app as main.dart builds it, minus the session: the same shell, the
/// same branches, the same screens, against [ds].
Widget shellApp(
  FakeCustodyDataSource ds, {
  required AppLanguage language,
  required ShellTab tab,
  bool openOnChat = false,
}) {
  final adminMode = AdminMode();
  final identity = AccountIdentity()
    ..adopt(fullName: ana.fullName, colorSlot: ana.colorSlot);
  final badge = NotificationBadge(ds)..chatOn = true;
  final expensesTab = ValueNotifier(true);
  final chatTab = ValueNotifier(true);
  final l = Localization(language);
  final router = GoRouter(
    initialLocation: switch (tab) {
      ShellTab.calendar => '/',
      ShellTab.family => '/family',
      ShellTab.communication => '/notifications',
      ShellTab.expenses => '/expenses',
      ShellTab.reports => '/reports',
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(
          shell: shell,
          adminMode: adminMode,
          identity: identity,
          onSignOut: () async {},
          onOpenProfile: () {},
          onOpenHelp: () {},
          badge: badge,
          expensesTab: expensesTab,
          chatTab: chatTab,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => CalendarScreen(
                  dataSource: ds,
                  adminMode: adminMode,
                  onOpenMember: (_, _) {},
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/family',
                builder: (_, _) => FamilyScreen(
                  dataSource: ds,
                  adminMode: adminMode,
                  sudo: SudoService(ds),
                  onOpenProfile: (_, _) {},
                  onOpenPlan: () {},
                  onOpenAdminMode: () {},
                  onOpenDeletion: () {},
                  onOpenCustomRoles: () {},
                  onOpenChildren: () {},
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notifications',
                builder: (_, _) => CommunicationScreen(
                  badge: badge,
                  openOnChat: openOnChat,
                  chat: ChatView(dataSource: ds, onOpenPlan: () {}),
                  notifications: NotificationsScreen(
                    dataSource: ds,
                    badge: badge,
                    embedded: true,
                    landing: openOnChat ? null : NotificationLanding.incoming,
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/expenses',
                builder: (_, _) =>
                    ExpensesScreen(dataSource: ds, onOpenPlan: () {}),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                builder: (_, _) =>
                    ReportsScreen(dataSource: ds, onOpenCalendar: () {}),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  return AppL10n(
    l: l,
    setLanguage: (_) async {},
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: l.isEnglish ? const Locale('en') : const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: router,
    ),
  );
}
