# Design system for architecture diagrams

Rules that make a diagram *set* read as one coherent artifact. Adapt the specifics per project; never abandon the principles.

## The 5-second test

A reader must grasp the main story in ~5 seconds: what talks to what, through what, and where the boundaries are. Details (ports, versions, instance sizes) are texture, not story. If the first impression is spaghetti, redesign — don't decorate.

## Semantic color tokens

Color must *mean* something, and the same thing everywhere. Default token set (Okabe-Ito-derived, colorblind-safe, verified in both major pipelines):

| Token | Meaning | Fill | Border |
|-------|---------|------|--------|
| `compute` | Things you run (services, hosts, load balancers, CI) | `#E3EEF6` | `#0072B2` |
| `datastore` | Data at rest (databases, buckets, backup stores) | `#FBEEDB` | `#E69F00` |
| `external` | Third-party SaaS / systems outside your control | `#F2F2F2` | `#8C8C8C` (dashed) |
| `actor` | People and client systems | `#E2F3ED` | `#009E73` |
| `gap` / attention | Known risks, gaps, warnings | keep token fill | `#D55E00`, 2.5px border accent — never a red fill |
| boundary | Real containment only (cloud region, network zone, host) | `#F7F7F5` / `#FAFAF8` | `#BBBBBB` |

Rules of use:

- **≤2 strong hues per diagram** plus neutrals; reserve one accent (the vermillion above) exclusively for "look here" (gaps, alerts).
- Projects may re-map hues (e.g. to brand colors) but must keep *one meaning per color* across the whole diagram set, and should keep contrast ≥ AA for text (`#1A1A1A` on light fills).
- Never rely on Mermaid theme defaults for node colors — they differ between engine versions. Define complete classDefs (see TECHNIQUES.md).

## Edge grammar

Line style is semantic, set-wide:

- **Solid** — runtime traffic / primary flow (`https :443`, `:5432`)
- **Dashed** — automation and background flows (scheduled jobs, image pulls, scrapes, backups)
- **Dashed + accent color** — alert/notification delivery (if used, use it in every diagram of the set)
- Arrowheads point with the payload; the label names the protocol/port or the action (`ssh :22`, `git push`). Terse labels; edge labels get a white background (set `edgeLabelBackground`).

## Layout principles

1. **Direction per purpose**: containment/topology TB, pipelines LR — but prefer TB when the destination is print (LR strips shrink to unreadable type at text width).
2. **Crossing budget**: ≤2–3 edge crossings per diagram, zero is achievable more often than you think. Control it with declaration order and invisible `~~~` links; consider routing an edge to a *boundary* instead of multiple inner nodes (one edge to the security-group box ≫ two crossing edges to its hosts).
3. **Subgraphs are real boundaries only** (region, network zone, host, instance). Max 3 nesting levels. If a box is just a visual grouping with no containment meaning, delete it.
4. **One landing depth per concept**: edges representing the same kind of flow should terminate at the same depth (all clients on the node, not one on the node and one on its enclosing box).
5. **Zoning**: place actors/sources in one band (top or left), your system in the middle, external systems in an outer band. Declaration order drives placement.

## Labels

- Node: short title (≤3 words) + at most one or two `<small>` detail lines. Paragraphs in boxes kill diagrams.
- Subgraph titles: ≤24 characters, single line (longer wraps/clips — verified in both pipelines).
- Break long detail lines explicitly with `<br/>` — auto-wrap breaks mid-token at ~200px.
- When detail doesn't fit, **delegate to the figure caption** and write the caption text alongside the diagram source. A caption-carried legend beats an in-diagram legend when space is tight.

## Set consistency

All diagrams in a set share: identical init block, identical classDef tokens, identical edge grammar, one naming scheme per entity (a host named "Prod server 2" in one diagram is not "Prod host" in the next), and one legend treatment. Inconsistency between sibling diagrams reads as sloppiness even when each diagram is individually fine.

## Two verified looks

**Decision rule: default to Look 2 (glass + elevation).** It won blind adversarial judging 8/10 vs Look 1's 5/10 while keeping the same proven layout, so it is the default for standalone images, READMEs, slides, and any general or unspecified audience. Reach for Look 1 (flat) only when colorblind-safety or a compliance / maximum-print-robustness need is explicitly stated. "Unknown audience" or "just show me the relationships" is a Look 2 case, not a Look 1 case. Don't pick flat because it appears first or feels safer; if a hard constraint is genuinely ambiguous, ask.

### Look 1 — Flat accessible (the token table above)

Colorblind-safe, conservative, print-bulletproof. The right choice when colorblind-safety or compliance is a stated requirement — not the default for general work. In adversarial attractiveness judging it calibrates ~5/10: legible but reads as "default Mermaid".

### Look 2 — Glass + elevation (the default; judged 8/10 vs the flat baseline's 5/10)

A restyle recipe that decisively beat the flat look in blind adversarial judging while preserving its proven layout legibility. The mechanics:

- **Tokens as hue-pairs**: each token = a saturated 2px border + the *same hue* as a translucent fill (`fill-opacity` 0.15–0.25 — below ~0.10 the tint reads as white)
- **Node elevation** via init `themeCSS`: `.node rect, .node path, .node polygon, .node circle { filter: drop-shadow(0 2px 4px rgba(15,23,42,0.3)); }`
- **Tight cluster shadows** to avoid nested-boundary haze: `.cluster rect { filter: drop-shadow(0 3px 8px rgba(51,65,85,0.2)); }`
- **Rounded corners** `rx:14,ry:14` on node classDefs (skip on stadium/cylinder shapes where it fights the silhouette)
- **One reserved accent** (e.g. rose `#E11D48`) for gaps/alerts — pick it perceptually distant from the datastore hue
- Boundary panels in light neutrals (`#F1F5F9`/`#FFFFFF` alternation) so the layering reads
- Example hue set (swap for brand colors freely): compute `#2563EB`, datastore `#F59E0B`/border `#D97706`, external `#64748B` dashed, actor `#10B981`/border `#059669`, edges `#475569`, text `#0F172A`

Trade-off: hue-pair tints are *less* colorblind-robust than the Okabe-Ito flat set (identity leans on border hue + lightness). For accessibility-critical audiences, stay with Look 1 or verify the chosen hues under CVD simulation.

### Lever notes (verified both pipelines)

- **Shadows**: only via init `themeCSS` — classDef `filter:` is a parse error in newer Mermaid. Tune ≥2px offset / ≥0.2 alpha or they vanish in print; expect clipping at canvas edges; don't stack heavy shadows on nested boundaries.
- **Weight**: `font-weight:bold` for key nodes — but bold re-wraps labels (see TECHNIQUES gotchas); re-inspect after applying.
- **Line patterns**: dashed traces better than dotted on long runs; override a `-.->` dot pattern with `linkStyle N stroke-dasharray:9 5` when needed.
