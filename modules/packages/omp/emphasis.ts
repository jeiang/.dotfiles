// pi-emphasis targets upstream pi: omp has no registerMarkdownTransformer, no
// systemPromptOptions.sections in before_agent_start, and no searchMatchBg theme token.
import { type ExtensionAPI, theme } from "@oh-my-pi/pi-coding-agent";
import { createPalette, decorate, replyGuidance, type Palette } from "@piEmphasis@/index.ts";

export default function emphasis(pi: ExtensionAPI) {
  let built: { source: unknown; palette: Palette } | undefined;
  const palette = () => {
    if (built?.source !== theme) {
      built = {
        source: theme,
        palette: createPalette(
          {
            fg: (color: never, text: string) => theme.fg(color, text),
            getFgAnsi: (color: never) => theme.getFgAnsi(color),
            getBgAnsi: (color: never) => theme.getBgAnsi((color === "searchMatchBg" ? "toolPendingBg" : color) as never),
          },
          process.env.PI_EMPHASIS_COLOR || "mdLink",
        ),
      };
    }
    return built.palette;
  };

  pi.on("before_agent_start", (event, ctx) => {
    if (ctx.mode !== "tui" || process.env.PI_EMPHASIS_GUIDANCE === "0") return;
    return { systemPrompt: [...event.systemPrompt, `<reply_style>\n${replyGuidance()}\n</reply_style>`] };
  });
  pi.registerAssistantTextRenderer(({ text }) => decorate(text, palette()));
}
