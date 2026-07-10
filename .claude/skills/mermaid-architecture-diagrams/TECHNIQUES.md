# Verified Mermaid techniques & gotchas

Every item here was verified by actually rendering through real pipelines and inspecting the output. Tags:

- `[universal]` — verified identical in Quarto (bundled Mermaid 11.6, own screenshot machinery) and mermaid-cli/mmdc (Mermaid 11.12, puppeteer)
- `[quarto]` / `[mmdc]` — pipeline-specific behavior
- `[version-sensitive]` — differs between Mermaid releases; avoid or guard

When you meet a different pipeline (MkDocs plugin, Docusaurus, kroki, …), re-run the probes at the bottom before trusting any of this there.

## Init block template `[universal]`

Start every diagram with a complete init — never rely on theme defaults (they differ per engine version):

```
%%{init: {
  "theme": "base",
  "themeVariables": {
    "fontSize": "16px",
    "primaryColor": "#E3EEF6",
    "primaryBorderColor": "#0072B2",
    "primaryTextColor": "#1a1a1a",
    "lineColor": "#4d4d4d",
    "edgeLabelBackground": "#ffffff",
    "clusterBkg": "#F7F7F5",
    "clusterBorder": "#BBBBBB"
  },
  "flowchart": { "curve": "basis", "nodeSpacing": 60, "rankSpacing": 70, "padding": 12 }
}}%%
flowchart TB
```

- `fontSize` verified up to 20px. Bigger type + narrower canvas = larger print text.
- The init block must be the first content in the diagram source.

## Gotcha table

| Gotcha | Tag | Detail |
|---|---|---|
| `themeVariables.fontFamily` clips **every label** | `[quarto]` | Quarto's screenshot pipeline measures text with one font and renders with another. Symptom: all labels cut mid-word. Fix: don't set fontFamily for Quarto-destined diagrams. Under mmdc the same override renders fine. |
| Subgraph titles >~24 chars wrap/clip | `[universal]` | Quarto clips past the box edge; mmdc truncates and/or wraps into node content. Keep titles ≤24 chars, single line, no `<br/>`; move detail into a node. |
| `filter:` inside classDef | `[version-sensitive]` | Mermaid 11.6 parses it, 11.12 throws a parse error (parens in classDef values). Use init `themeCSS` instead — stable in both. |
| Theme default colors differ per engine version | `[universal]` | A partially-styled diagram looks different in each pipeline. Always ship full classDefs. |
| Auto-wrap breaks labels mid-token at ~200px | `[universal]` | Break detail lines explicitly with `<br/>`. |
| `nodeSpacing`/`rankSpacing` weaken inside subgraphs | `[universal]` | Known Mermaid limitation. Get whitespace from structure, not config. |
| `direction LR` inside a subgraph unreliable | `[universal]` | Ignored when edges cross the subgraph boundary. Don't depend on it. |
| `linkStyle` indices count invisible `~~~` links | `[universal]` | Index = order of *every* edge statement. Count carefully. |
| LR pipelines print tiny | `[universal]` | A 6:1 LR strip scaled to text width yields ~4–5pt type. Prefer TB for print destinations. |
| Shadows clip at canvas edge; subtle shadows vanish in print | `[universal]` | Keep drop-shadows modest but visible (≥2px offset, ≥0.2 alpha); expect clipping on edge-hugging nodes. |
| **`linkStyle default` resurrects invisible `~~~` links** | `[universal]` | `linkStyle default` applies stroke to *every* edge — including invisible `~~~` spacer links, which render as phantom edges fabricating connections (verified: this disqualified a competition variant whose author never noticed across two self-review rounds). Set the base edge color via `themeVariables.lineColor`; use *indexed* `linkStyle` only, for accents. |
| `font-weight:bold` re-wraps labels | `[universal]` | Bold widens text past the ~200px wrap budget: previously single-line titles wrap, and the whole canvas geometry shifts. After adding bold, re-inspect every label; break lines explicitly. |
| `fill-opacity` ≤ 0.10 reads as white | `[universal]` | Tints only land visually at ~0.15–0.25 over a solid border; below that the "tint" disappears at arm's length and color identity rides on the border alone. |
| Nested cluster shadows stack into haze | `[universal]` | Three nested shadowed boundaries produce gray bands where panes meet. Keep cluster shadows tight (~`0 3px 8px @ 0.20`) and put the elevation on nodes instead. |
| Long dotted runs are hard to trace | `[universal]` | Prefer dashed over dotted for long edge runs; a `-.->` dot pattern can be overridden per edge with `linkStyle N stroke-dasharray:9 5`. |
| mmdc can't find Chrome | `[mmdc]` | puppeteer wants its own pinned download. Either `npx puppeteer browsers install chrome-headless-shell`, or point at system Chrome with `-p puppeteer-config.json`: `{"executablePath": "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}` (adjust per OS). |
| Output sizing | pipeline-specific | Quarto: `%%| fig-width: N` cell option, PNGs ~2960px wide. mmdc: `-w` page width, `-s` scale factor, `-b white` background. |

## Class tokens `[universal]`

```
classDef compute fill:#E3EEF6,stroke:#0072B2,stroke-width:1.5px,color:#1a1a1a
classDef datastore fill:#FBEEDB,stroke:#E69F00,stroke-width:1.5px,color:#1a1a1a
classDef external fill:#F2F2F2,stroke:#8C8C8C,stroke-width:1.5px,color:#1a1a1a,stroke-dasharray:5 3
classDef actor fill:#E2F3ED,stroke:#009E73,stroke-width:1.5px,color:#1a1a1a
classDef gap stroke:#D55E00,stroke-width:2.5px
```

Tag nodes `node:::compute`; stack a second class with `class node gap` (border accent on top of token fill).

## Shapes `[universal]`

- Service: `id["Label"]` · Datastore: `id[("Label")]` · Actor: `id(["Label"])` · Decision: `id{"Label"}`
- Labels: quote everything; `<br/>` line breaks and `<small>detail</small>` secondary lines verified in both pipelines.

## Subgraphs `[universal]`

```
subgraph zone["Cloud region x"]
  ...
end
style zone fill:#FAFAF8,stroke:#BBBBBB
```

Per-subgraph `style` overrides cluster theme defaults. Rounded boundaries: append `,rx:10,ry:10`.

## Edges `[universal]`

```
a -->|"https :443"| b      %% solid runtime
a -.->|"nightly sync"| b   %% dashed automation
a ~~~ b                    %% invisible, layout nudging only
linkStyle 3 stroke:#D55E00 %% accent one path (index counts ~~~ too)
```

Base edge color belongs in `themeVariables.lineColor` — **never `linkStyle default`**, which also styles invisible `~~~` links into phantom edges (see gotcha table).

## Aesthetics `[universal unless noted]`

```
classDef card fill:#E3EEF6,stroke:#0072B2,stroke-width:1.5px,rx:12,ry:12   %% rounded corners
classDef tint fill:#0072B2,fill-opacity:0.12,stroke:#0072B2                 %% translucent tint
classDef key  fill:#E3EEF6,stroke:#0072B2,font-weight:bold                  %% bold label
```

Drop-shadows — **only** via init `themeCSS` (classDef `filter:` is `[version-sensitive]`, parse error in Mermaid ≥11.12):

```
"themeCSS": ".node rect { filter: drop-shadow(2px 3px 4px rgba(0,0,0,0.25)); } .cluster rect { filter: drop-shadow(2px 3px 6px rgba(0,0,0,0.15)); }"
```

## Probe snippets for a new pipeline

Render these three probes through any unfamiliar pipeline and inspect before authoring:

1. **Font probe**: any diagram with `"fontFamily": "Helvetica, Arial, sans-serif"` in themeVariables → if labels clip, the pipeline has the Quarto-style measurement mismatch: drop fontFamily.
2. **Title probe**: a subgraph titled with 30+ characters → observe wrap/clip behavior, set your title budget.
3. **Style probe**: the class tokens + one `rx:12` class + a `themeCSS` drop-shadow → confirms styling fidelity and filter support.
