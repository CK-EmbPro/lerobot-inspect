---
name: documentation-writer
description: >
  Produce well-structured, detailed Markdown documentation — READMEs, DESIGN
  notes, architecture docs, usage guides, JSON-schema and exit-code references,
  and API/CLI references. Invoke when asked to write or overhaul .md docs, a
  README, a design note, or any structured technical document. Enforces a
  consistent skeleton, accuracy from real code (zero hallucination), and diagrams
  via the `mermaid-architecture-diagrams` skill. For deep doc systems delegate to
  the `documentation-engineer` agent; for repo READMEs to `readme-generator`.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
metadata:
  version: 1.0.0
---

# Documentation Writer

Write documentation a maintainer can trust and act on. Default output is
**Markdown (.md)**. Every claim must come from real code, config, or observed
behavior — never guess a flag, path, env var, or exit code.

## When this applies

- Writing or overhauling a README, DESIGN note, usage guide, or reference doc.
- Documenting a CLI: flags, dependencies, exit codes, examples.
- Documenting a data contract: JSON schema, field meanings, tolerances.
- Producing architecture docs with diagrams.

## Zero-hallucination protocol

1. Read the source first — scripts, `--help`, tests, config, manifests.
2. Document only what you verified. If a value is unknown, say so or omit it —
   never invent one.
3. Prefer copy-pasted real output (e.g. actual `--help` text) over paraphrase.
4. Keep docs in sync with code: when behavior changes, update the doc in the same
   change.

## Document skeletons

### README

```markdown
# <tool name>

One-sentence purpose.

## Overview        — what it does and why, 2–4 sentences
## Requirements    — dependencies (name + why), versions
## Installation    — exact steps (e.g. chmod +x)
## Usage           — synopsis, then every flag in a table
## Examples        — real, runnable commands with expected output
## Output          — human report + JSON schema link/inline
## Exit codes      — table: code | meaning
## How it works    — brief architecture, link to DESIGN
## Troubleshooting — common errors → cause → fix
```

### DESIGN note (≤1 page)

```markdown
# DESIGN — <tool name>

## Goal          — one paragraph
## Assumptions   — what we take as given (and the risk if wrong)
## Approach      — key decisions and why
## Tradeoffs     — what we chose against, and the cost
## What I'd improve — honest next steps
```

### Flag / exit-code / schema tables

Always tabular, always complete:

```markdown
| Flag            | Argument | Default | Description                     |
|-----------------|----------|---------|---------------------------------|
| `-h`, `--help`  | —        | —       | Show usage and exit             |
| `--json`        | —        | off     | Emit machine-readable JSON      |

| Exit code | Meaning                     |
|-----------|-----------------------------|
| 0         | OK                          |
| 2         | Integrity failure           |
```

## Structure & style rules

- Lead with purpose; put the most-needed info (usage, flags) high.
- One idea per section; use tables for anything enumerable (flags, codes, fields).
- Every code block is copy-paste runnable; show expected output where it clarifies.
- Use relative Markdown links between docs; keep a table of contents for long docs.
- Diagrams: build with [`mermaid-architecture-diagrams`](../mermaid-architecture-diagrams/SKILL.md)
  and embed as ```mermaid fences so they render in Markdown.
- Prefer plain, precise language; define acronyms once; no marketing filler.

## Quality checklist

- [ ] Every flag, env var, path, and exit code is documented and verified.
- [ ] Examples run as written and match real output.
- [ ] JSON schema / data contract documented if the tool emits structured data.
- [ ] DESIGN note covers assumptions, tradeoffs, and improvements.
- [ ] Diagrams render; links resolve; no TODO/placeholder left behind.
- [ ] Doc matches current code behavior (re-checked against source).

For large multi-doc systems, hand off to the
[`documentation-engineer`](../../agents/documentation-engineer.md) agent; for a
repository README built from codebase reality, use
[`readme-generator`](../../agents/readme-generator.md).
