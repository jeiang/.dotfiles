// Draws icons on report labels and links in assistant replies. The same renderer as the emphasis
// extension in pi-extensions.
// Adapted from github.com/johnlindquist/pi-emphasis, MIT, Copyright (c) 2026 John Lindquist.
import { type ExtensionAPI, theme } from "@oh-my-pi/pi-coding-agent";

const LABELS: Record<string, string> = {
  finding: "\uf002", plan: "\uf0ae", result: "\uf11e", changed: "\uf040", checked: "\uf00c", remains: "\uf141",
  "needs you": "\uf007", risk: "\uf071", next: "\uf061", cause: "\uf0e7", fix: "\uf0ad",
};
const URL_ICON = "\uf08e";
const FILE_ICON = "\uf15b";

const FENCE = /^ {0,3}(`{3,}|~{3,})/;
const HEADING = /^( {0,3}#{1,6}\s+)(.+)$/;
const LEAD = /^(\s*(?:[-*+]|\d+\.)?\s*(?:[├└]──\s*)?\*\*)([^*`\n]{1,32})(\*\*)/;
const LINK = /(?<!!)\[([^\]\n]+)\]\(([^)\s#][^)\s]*)\)/g;

const withIcon = (label: string) => {
  const icon = LABELS[label.replace(/[:\s]+$/, "").toLowerCase()];
  return icon ? `${icon} ${label}` : label;
};

const decorateProse = (prose: string) =>
  prose
    .replace(LINK, (_, label: string, target: string) => `[${/^[a-z][a-z\d+.-]*:/i.test(target) ? URL_ICON : FILE_ICON} ${label}](${target})`)
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

// omp's instructions do not name the labels, so the renderer tells the model.
const GUIDANCE = `A heading or a line's leading bold label gets an icon when it is one of: ${Object.keys(LABELS)
  .map((word) => word[0].toUpperCase() + word.slice(1))
  .join(", ")}. Links get one too. Never type icon glyphs.`;

export default function emphasis(pi: ExtensionAPI) {
  pi.on("before_agent_start", (event, ctx) => (ctx.mode === "tui" ? { systemPrompt: [...event.systemPrompt, GUIDANCE] } : undefined));
  pi.registerAssistantTextRenderer(({ text }) => decorate(text));
}
