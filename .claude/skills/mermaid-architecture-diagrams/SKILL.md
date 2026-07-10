---
name: mermaid-architecture-diagrams
description: Author print-quality Mermaid architecture and ops diagrams (system sketches, deployment pipelines, monitoring and data-flow maps) using a semantic color system and a mandatory render-and-inspect loop. Use when creating, styling, or reviewing Mermaid diagrams; when asked for an architecture diagram, system sketch, or flowchart destined for documentation (Quarto/pandoc/PDF, GitHub README, wikis); or when a Mermaid diagram renders ugly, clipped, or unreadable. Covers verified pipeline-specific gotchas (Quarto vs mermaid-cli) and their workarounds.
metadata:
  version: 1.2.0
---

# Mermaid Architecture Diagrams

Produce diagrams that are **correct, legible in print, and consistent as a set** — not just syntactically valid Mermaid.

## The one non-negotiable rule

**Never trust unrendered diagram code.** Mermaid layout is emergent: label widths, edge routing, and subgraph sizing only exist after rendering. The loop is:

1. Author the `.mmd`
2. Render it: `scripts/render-mmd.sh diagram.mmd`
3. **Look at the preview image** (the script writes a `*-preview.png` sized for inspection)
4. Fix clipping, overlaps, label collisions, edge crossings — re-render
5. Repeat until clean (minimum one fix round; diagrams are never right first try)

A diagram you haven't looked at is a draft, not a deliverable.

## Workflow

1. **Purpose first.** One diagram, one purpose, one audience. Write the 5-second story the reader must grasp (*what talks to what, through what, where the boundaries are*) before drawing. If a diagram needs two stories, make two diagrams.
2. **Pick the flow direction.** Topology/containment reads top-down (`TB`); pipelines read left-to-right (`LR`) — **but for print/PDF destinations, tall-and-narrow TB beats wide LR**: an LR pipeline scaled to text width prints at ~4–5pt. Verified repeatedly.
3. **Apply the design system.** Use the semantic tokens, edge grammar, and label rules in [DESIGN-SYSTEM.md](DESIGN-SYSTEM.md). Color means something or it isn't used. **Default to the glass + elevation look (Look 2, judged 8/10); the flat look (5/10) is the exception** — reach for it only when colorblind-safety or compliance is explicitly required. "Unknown audience" or "just show me X" is a Look 2 case. See DESIGN-SYSTEM.md's decision rule; don't pick flat because it's listed first.
4. **Author within the verified allowlist.** [TECHNIQUES.md](TECHNIQUES.md) contains only constructs verified through real render pipelines, each tagged with where it works. The headline trap: **never set `themeVariables.fontFamily` for Quarto-destined diagrams** — it clips every label.
5. **Render with the destination's pipeline** (table below).
6. **Self-review adversarially** against [REVIEW-CHECKLIST.md](REVIEW-CHECKLIST.md) — legibility, design consistency, comprehension/correctness. Fix and re-render.
7. **High stakes?** Run a variant competition (sketch in REVIEW-CHECKLIST.md): several styled variants, adversarial judging, recombine winners.

## Which pipeline renders the truth?

Preview with whatever will render the diagram in production — otherwise you are tuning against the wrong engine:

| Destination | Render with | Notes |
|---|---|---|
| Quarto / pandoc document (PDF, docx) | `render-mmd.sh -p quarto` | The document's own engine; what you see is what ships |
| GitHub README / wiki / GitLab | `render-mmd.sh -p mmdc` | mermaid-cli tracks current Mermaid, closest to GitHub's renderer |
| MkDocs / Docusaurus / Hugo site | The site's own build; fall back to `mmdc` for quick iteration | Site plugins pin their own Mermaid versions |
| Slides, standalone images | `mmdc` (`-o out.svg` for vectors) | |

`render-mmd.sh` auto-detects (`-p auto`, the default): prefers Quarto when installed, falls back to mermaid-cli. Both paths produce a full-resolution PNG plus an inspection preview.

## Engine reality check

Quarto bundles its own Mermaid (e.g. 11.6.0) with its own screenshot machinery; `mmdc` ships current Mermaid (e.g. 11.12). Same major version — **different behavior**: parser strictness, font handling, and theme defaults all differ. That is why TECHNIQUES.md tags every construct `[universal]`, `[quarto]`, `[mmdc]`, or `[version-sensitive]`, and why the portable strategy is to **author inside the intersection**: full classDef tokens (never rely on theme defaults), no fontFamily override, filters via `themeCSS` not classDef, subgraph titles ≤24 characters. Diagrams written that way render near-identically in both pipelines.

When you meet a new pipeline (different SSG, different Mermaid version), spike it first: render TECHNIQUES.md's probe snippets through it and note divergences before authoring real diagrams.

## Bundled references

- [DESIGN-SYSTEM.md](DESIGN-SYSTEM.md) — semantic color tokens (colorblind-safe default palette), edge grammar, layout, label and legend rules
- [TECHNIQUES.md](TECHNIQUES.md) — verified syntax allowlist with pipeline tags, gotcha table, probe snippets
- [REVIEW-CHECKLIST.md](REVIEW-CHECKLIST.md) — adversarial self-review lenses + the variant-competition pattern
- [scripts/render-mmd.sh](scripts/render-mmd.sh) — adaptive render + preview loop (Quarto or mermaid-cli)
