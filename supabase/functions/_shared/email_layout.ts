// U-26 — the ONE visual layer every e-mail this product sends is built from.
//
// THE DEFECT. Closed alpha, 12/08/2026, with a screenshot: the invitation's
// header band and its "Criar minha conta" button were near-black (#212529), and
// on a mail client in dark theme both vanished. A dark client repaints the light
// surfaces dark and leaves a near-black one alone, so a black button ends up on
// a black card. The invitation is the product's growth loop; an invisible button
// is a family that never arrives.
//
// And the layer did not exist. `send-swap-email` carried its own card shell,
// while `send-account-email` and `send-auth-email` each wrote a bare `<div>` with
// a text colour and NO background at all — so the same fix had to land three
// times, and the sender with no fallback behind it (`send-auth-email`: with the
// Send Email Hook on, GoTrue sends nothing itself) had exactly the failing
// button. Now all three compose from this file and write no style of their own.
//
// THE RULES THAT SURVIVE A DARK CLIENT — none of them relies on a media query:
//
//   1. Every style sets `color` AND `background-color`, and every table cell
//      also carries `bgcolor`. What disappears in dark mode is text on an
//      INHERITED background: a client that repaints the page repaints only what
//      it can see declared.
//   2. No dark surface. The header is white with a hairline (owner, 16/09/2026:
//      neutral identity, colour only on the primary action — the U-27 rule); the
//      only saturated surface is the call to action, brand indigo under white
//      text, which holds its contrast whether a client inverts it or not.
//   3. No `@media (prefers-color-scheme: dark)`. Apple Mail honours it, Gmail
//      ignores it and applies its own inversion — a fix that needs the query is
//      a fix for one client. The `color-scheme: light only` meta is a HINT to the
//      clients that read it, not a dependency.
//   4. Every pair of text and background clears WCAG AA (4.5:1). The old footnote
//      greys (#9ca3af, #868e96) did not, even on white.
//
// All of it is pinned by `email_layout_guard_test.dart` (entrelares_core), which
// reads this file and the three senders: every colour lives in `S` below, as a
// literal, and the guard checks each entry's pair, contrast and surface. The
// U-27 `no_color_literal_test` guards the Flutter `lib/` only — without this
// guard nothing would fail the build if a #000 came back.
//
// Markup notes: tables, not divs, carry anything with a background (Outlook and
// some webmail keep a cell's `bgcolor` when they strip styles). The button is
// the "bulletproof" shape — the cell paints the surface, so a client that drops
// the link's background still shows the button.

/** Every style an e-mail may use. Literal hex only: the guard reads these. */
const S = {
  body: "margin:0;padding:0;width:100%;color:#111827;background-color:#f4f4f5;font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;",
  page: "padding:32px 16px;color:#111827;background-color:#f4f4f5;",
  card: "max-width:480px;width:100%;border:1px solid #e5e7eb;border-radius:12px;color:#111827;background-color:#ffffff;",
  header: "padding:20px 24px;border-bottom:1px solid #e5e7eb;color:#111827;background-color:#ffffff;",
  wordmark: "margin:0;font-size:18px;font-weight:700;color:#111827;background-color:#ffffff;",
  content: "padding:28px 24px;color:#374151;background-color:#ffffff;",
  footerNote: "margin:20px 0 0;font-size:12px;line-height:1.6;color:#6b7280;background-color:#ffffff;",
  footerNoteNext: "margin:4px 0 0;font-size:12px;line-height:1.6;color:#6b7280;background-color:#ffffff;",

  headingNeutral: "margin:0 0 16px;font-size:20px;line-height:1.3;color:#111827;background-color:#ffffff;",
  headingSuccess: "margin:0 0 16px;font-size:20px;line-height:1.3;color:#15803d;background-color:#ffffff;",
  headingDanger: "margin:0 0 16px;font-size:20px;line-height:1.3;color:#b91c1c;background-color:#ffffff;",
  headingWarning: "margin:0 0 16px;font-size:20px;line-height:1.3;color:#b45309;background-color:#ffffff;",
  headingRevert: "margin:0 0 16px;font-size:20px;line-height:1.3;color:#6d28d9;background-color:#ffffff;",

  paragraph: "margin:0 0 12px;line-height:1.6;color:#374151;background-color:#ffffff;",
  paragraphLast: "margin:0 0 20px;line-height:1.6;color:#374151;background-color:#ffffff;",
  paragraphAfter: "margin:12px 0 0;line-height:1.6;color:#374151;background-color:#ffffff;",
  small: "margin:16px 0 0;font-size:12px;line-height:1.6;color:#6b7280;background-color:#ffffff;",
  smallSpaced: "margin:20px 0 0;font-size:12px;line-height:1.6;color:#6b7280;background-color:#ffffff;",
  linkRow: "margin:20px 0 0;color:#374151;background-color:#ffffff;",
  link: "font-size:13px;text-decoration:underline;color:#6b7280;background-color:#ffffff;",
  smallLink: "text-decoration:underline;color:#6b7280;background-color:#ffffff;",
  rawUrl: "word-break:break-all;text-decoration:underline;color:#6b7280;background-color:#ffffff;",
  list: "margin:0 0 12px;padding-left:20px;line-height:1.6;color:#374151;background-color:#ffffff;",
  listItem: "margin:0 0 4px;color:#374151;background-color:#ffffff;",

  codeTable: "margin:0 0 12px;border-collapse:separate;color:#374151;background-color:#ffffff;",
  code: "padding:12px 16px;border-radius:8px;font-size:28px;font-weight:700;letter-spacing:4px;color:#111827;background-color:#f3f4f6;",

  buttonTable: "margin:4px 0 0;border-collapse:separate;color:#374151;background-color:#ffffff;",
  buttonCell: "border-radius:8px;color:#ffffff;background-color:#4f46e5;",
  button: "display:inline-block;padding:12px 24px;border:1px solid #4f46e5;border-radius:8px;font-size:15px;font-weight:600;text-decoration:none;color:#ffffff;background-color:#4f46e5;",

  bannerTable: "margin:0 0 16px;border-collapse:separate;color:#374151;background-color:#ffffff;",
  bannerDanger: "padding:10px 14px;border:1px solid #f87171;border-radius:8px;font-size:13px;font-weight:700;text-align:center;color:#b91c1c;background-color:#fef2f2;",
  bannerWarning: "padding:10px 14px;border:1px solid #ffc107;border-radius:8px;font-size:13px;font-weight:700;text-align:center;color:#856404;background-color:#fff3cd;",
} as const;

/** The `bgcolor` attribute of each surface cell — the same values as `S`. */
const BG = {
  page: "#f4f4f5",
  card: "#ffffff",
  code: "#f3f4f6",
  button: "#4f46e5",
  bannerDanger: "#fef2f2",
  bannerWarning: "#fff3cd",
} as const;

export type HeadingTone = "neutral" | "success" | "danger" | "warning" | "revert";
export type BannerTone = "danger" | "warning";

const HEADING: Record<HeadingTone, string> = {
  neutral: S.headingNeutral,
  success: S.headingSuccess,
  danger: S.headingDanger,
  warning: S.headingWarning,
  revert: S.headingRevert,
};

/**
 * The whole message: page, card, header, the caller's body and its footer lines.
 *
 * `title`, `body` and `footer` are inserted as given — the catalogue text is ours
 * and carries its own `<strong>`; USER DATA must reach here already escaped, as
 * each sender did before this file existed.
 */
export function emailDocument(opts: {
  htmlLang: string;
  title: string;
  body: string;
  footer: string[];
}): string {
  const footer = opts.footer
    .map((line, i) => `<p style="${i === 0 ? S.footerNote : S.footerNoteNext}">${line}</p>`)
    .join("\n          ");
  return `<!DOCTYPE html>
<html lang="${opts.htmlLang}">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="color-scheme" content="light only" />
  <meta name="supported-color-schemes" content="light only" />
  <title>${opts.title}</title>
</head>
<body bgcolor="${BG.page}" style="${S.body}">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${BG.page}" style="${S.body}">
    <tr><td align="center" bgcolor="${BG.page}" style="${S.page}">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${BG.card}" style="${S.card}">
        <tr><td bgcolor="${BG.card}" style="${S.header}">
          <p style="${S.wordmark}">👨‍👩‍👧 Entrelares</p>
        </td></tr>
        <tr><td bgcolor="${BG.card}" style="${S.content}">
          ${opts.body}
          ${footer}
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

export function heading(text: string, tone: HeadingTone = "neutral"): string {
  return `<h2 style="${HEADING[tone]}">${text}</h2>`;
}

/** Body text. `last` leaves room before a button; `after` follows a paragraph. */
export function paragraph(html: string, spacing: "normal" | "last" | "after" = "normal"): string {
  const style = spacing === "last" ? S.paragraphLast : spacing === "after" ? S.paragraphAfter : S.paragraph;
  return `<p style="${style}">${html}</p>`;
}

/** Fine print. `spaced` opens more room above it. */
export function small(html: string, spaced = false): string {
  return `<p style="${spaced ? S.smallSpaced : S.small}">${html}</p>`;
}

/** A secondary link, standalone (`link`) or inside fine print (`smallLink`). */
export function link(href: string, label: string): string {
  return `<a href="${href}" style="${S.link}">${label}</a>`;
}

export function smallLink(href: string, label: string): string {
  return `<a href="${href}" style="${S.smallLink}">${label}</a>`;
}

/** A secondary link on a row of its own. */
export function linkRow(href: string, label: string): string {
  return `<p style="${S.linkRow}">${link(href, label)}</p>`;
}

/**
 * A URL printed for copying, which may break anywhere.
 *
 * An ANCHOR, never plain text: Gmail auto-links a bare URL and paints it in
 * ITS OWN link colour, which in dark theme is a pale blue — measured on the
 * owner's device (16/09/2026, U-26 matrix) as near-invisible on the white card.
 * An `<a>` that declares its colour keeps it, as the privacy link beside it did.
 */
export function rawUrl(url: string): string {
  return `<a href="${url}" style="${S.rawUrl}">${url}</a>`;
}

export function list(items: string[]): string {
  return `<ul style="${S.list}">${items.map((i) => `<li style="${S.listItem}">${i}</li>`).join("")}</ul>`;
}

/** A one-time code the reader types into the app. */
export function code(value: string): string {
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" bgcolor="${BG.card}" style="${S.codeTable}"><tr><td bgcolor="${BG.code}" style="${S.code}">${value}</td></tr></table>`;
}

/** The primary action. One per message. */
export function button(href: string, label: string): string {
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" bgcolor="${BG.card}" style="${S.buttonTable}"><tr><td bgcolor="${BG.button}" style="${S.buttonCell}"><a href="${href}" style="${S.button}">${label}</a></td></tr></table>`;
}

export function banner(text: string, tone: BannerTone): string {
  const [style, bg] = tone === "danger" ? [S.bannerDanger, BG.bannerDanger] : [S.bannerWarning, BG.bannerWarning];
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="${BG.card}" style="${S.bannerTable}"><tr><td bgcolor="${bg}" style="${style}">${text}</td></tr></table>`;
}
