// Draws [[Word]] status pills and label icons in assistant replies.
// Adapted from github.com/johnlindquist/pi-emphasis, MIT, Copyright (c) 2026 John Lindquist.
import { type ExtensionAPI, theme } from "@oh-my-pi/pi-coding-agent";

type Tone = {
  meaning: string;
  words: Record<string, string>;
  fg?: Parameters<typeof theme.getFgAnsi>[0];
  bg?: Parameters<typeof theme.getBgAnsi>[0];
  sgr?: number;
};

// The last tone also colors any unknown word.
const TONES: Tone[] = [
  { meaning: "Red, something is wrong", fg: "error", bg: "toolErrorBg", words: { Failed: "\uf00d", Blocked: "\uf05e", Broken: "\uf127", Unsafe: "\uf132" } },
  { meaning: "Yellow, look here", fg: "warning", bg: "toolPendingBg", words: { "Needs you": "\uf007", Decision: "\uf126", Unverified: "\uf128", Partial: "\uf042", Skipped: "\uf04e", "In progress": "\uf110", Pending: "\uf017", "At risk": "\uf071" } },
  { meaning: "Green, settled", fg: "success", bg: "toolSuccessBg", words: { Done: "\uf00c", Passed: "\uf00c", Observed: "\uf06e", Fixed: "\uf0ad", Live: "\uf135", Recommended: "\uf005", Keep: "\uf08d" } },
  { meaning: "Solid red, consequences, required before taking the action", sgr: 31, words: { "Costs money": "\uf155", Destructive: "\uf1f8", Irreversible: "\uf023" } },
  { meaning: "Cyan, the kind of work, opening every substantive reply", sgr: 36, words: { Brainstorm: "\uf0eb", Investigate: "\uf002", Preview: "\uf06e", Implement: "\uf0ad", Qualify: "\uf0c3" } },
  { meaning: "Blue, ownership of anything changed outside the task's own files", sgr: 34, words: { Owned: "\uf007", Shared: "\uf0c0", Foreign: "\uf023" } },
  { meaning: "Soft blue, context, or any other short label", fg: "text", bg: "selectedBg", words: { Inferred: "\uf0eb", New: "\uf067", Changed: "\uf040", Optional: "\uf10c" } },
];

const LABELS: Record<string, string> = {
  finding: "\uf002", result: "\uf11e", status: "\uf012", evidence: "\uf06e", cause: "\uf0e7", effect: "\uf140",
  fix: "\uf0ad", risk: "\uf071", limits: "\uf071", cost: "\uf155", decision: "\uf126", options: "\uf0ca",
  plan: "\uf0ae", next: "\uf061", why: "\uf059", how: "\uf013", rule: "\uf0e3", example: "\uf121",
  checked: "\uf00c", verdict: "\uf0e3", rollback: "\uf0e2", undo: "\uf0e2", review: "\uf06e",
};

const ACTIONS: Record<string, string> = {
  check: "\uf046", do: "\uf0a4", next: "\uf061", unblock: "\uf09c", left: "\uf141", run: "\uf04b", guard: "\uf132", undo: "\uf0e2", see: "\uf08e",
};

const PILLS = TONES.flatMap((tone) => Object.entries(tone.words).map(([word, icon]) => ({ tone, word: word.toLowerCase(), icon }))).sort(
  (a, b) => b.word.length - a.word.length,
);

const FENCE = /^ {0,3}(`{3,}|~{3,})/;
const HEADING = /^( {0,3}#{1,6}\s+)(.+)$/;
const LEAD = /^(\s*(?:[-*+]|\d+\.)?\s*(?:[├└]──\s*)?\*\*)([^*`\n]{1,32})(\*\*)/;
const ACTION = new RegExp(`\\*\\*(${Object.keys(ACTIONS).join("|")}):\\*\\*`, "gi");
const PILL = /\[\[([^[\]\n]{1,32})\]\]/g;

function pill(label: string): string {
  const text = label.replace(/\s+/g, " ").trim();
  const lower = text.toLowerCase();
  const known = PILLS.find(({ word }) => lower.startsWith(word) && /^(?:$|[ :])/.test(lower.slice(word.length)));
  const tone = known?.tone ?? TONES[TONES.length - 1];
  // No-break spaces keep a two-word pill on one line when the paragraph wraps.
  const body = (known ? `${known.icon} ${text}` : text).replace(/ /g, "\u00a0");
  const bg = tone.bg && theme.getBgAnsi(tone.bg);
  const [fill, cap] = bg && tone.fg ? [bg + theme.getFgAnsi(tone.fg), bg.replace("\x1b[48;", "\x1b[38;")] : [`\x1b[${tone.sgr}m\x1b[7m`, `\x1b[${tone.sgr}m`];
  return `${cap}\ue0b6\x1b[39m${fill}\x1b[1m${body}\x1b[22;27;39;49m${cap}\ue0b4\x1b[39m`;
}

const withIcon = (label: string) => {
  const icon = LABELS[label.replace(/[:\s]+$/, "").toLowerCase()];
  return icon ? `${icon} ${label}` : label;
};

const decorateProse = (prose: string) =>
  prose
    .replace(ACTION, (_, word: string) => `**${ACTIONS[word.toLowerCase()]} ${word}:**`)
    .replace(PILL, (match, label: string) => (label.trim() ? pill(label) : match))
    .replace(/[✓✔]/g, (mark) => theme.fg("success", mark))
    .replace(/[✗✘]/g, (mark) => theme.fg("error", mark))
    .replace(/→/g, (mark) => theme.fg("accent", mark))
    .replace(/[├└]──/g, (mark) => theme.fg("dim", mark));

function decorate(markdown: string): string {
  let fence: string | undefined;
  return markdown
    .split("\n")
    .map((line) => {
      const marker = line.match(FENCE)?.[1];
      if (fence) {
        if (marker && marker[0] === fence[0] && marker.length >= fence.length) fence = undefined;
        return line;
      }
      if (marker) {
        fence = marker;
        return line;
      }
      if (HEADING.test(line)) return line.replace(HEADING, (_, hashes: string, title: string) => hashes + withIcon(title));
      return line
        .replace(LEAD, (_, before: string, label: string, after: string) => before + withIcon(label) + after)
        .split(/(`+[^`]*?`+)/g)
        .map((part, i) => (i % 2 ? part : decorateProse(part)))
        .join("");
    })
    .join("\n");
}

const GUIDANCE = `<reply_style>
This terminal draws \`[[Word]]\` as a colored pill with an icon and adds icons to known labels. Never type icon glyphs.
- Put a pill beside the subject it describes, at most one per bullet or table cell, never in headings, code, paths, commands, or literal output, and none when the user asks for plain text or an exact format. Use only these words; one may carry short detail, as in [[Passed 12/12]] or [[Failed: 3 tests]].
${TONES.map((tone) => `  - ${tone.meaning}: ${Object.keys(tone.words).join(", ")}.`).join("\n")}
- Every failure, blocker, ask, and unchecked claim carries its pill. Mark evidence claims Observed, Inferred, or Unverified. Needs you is an action only the user can take; Decision is a call only the user makes.
- After each red, yellow, solid red, or Inferred pill, give the one fact needed to act on it behind a bold lead-in: ${Object.keys(ACTIONS).map((word) => `**${word[0].toUpperCase()}${word.slice(1)}:**`).join(", ")}.
- A \`##\` heading or a line's leading bold label gets an icon when it is one of: ${Object.keys(LABELS).map((word) => word[0].toUpperCase() + word.slice(1)).join(", ")}.
- Use \`├──\` and \`└──\` for hierarchy, \`→\` for a sequence, and \`✓\` or \`✗\` beside a checked item.
</reply_style>`;

export default function emphasis(pi: ExtensionAPI) {
  pi.on("before_agent_start", (event, ctx) => (ctx.mode === "tui" ? { systemPrompt: [...event.systemPrompt, GUIDANCE] } : undefined));
  pi.registerAssistantTextRenderer(({ text }) => decorate(text));
}
