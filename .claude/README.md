# LeRobot Dataset Inspector — `.claude` bundle

A **self-contained, portable Claude Code configuration** for building
`lerobot-inspect` (see the project brief `LeRobot_Dataset_Inspector_Mini_Project-1.pdf`).
Move this whole `.claude/` folder into the repo where the tool will live and its
skills, agents, and hooks activate automatically.

## What's inside

```
.claude/
├── CLAUDE.md              # main project description + how to work here
├── settings.json          # registers the shellcheck hook
├── README.md              # this file
├── hooks/
│   └── shellcheck-hook.sh # PostToolUse: shellcheck every shell edit (zero-warning gate)
├── skills/                # invoke each as /<name>
│   ├── wizard/            # architect-mode planning + TDD + adversarial review
│   ├── bash/              # bash best practices (structure, parsing, error handling)
│   ├── lerobot-inspector/ # LeRobot layout + the 14 required checks (+ references/)
│   ├── dataset-handling/  # profile / validate / clean / transform / report
│   ├── detecting-data-anomalies/ # outlier detection (+ references/, scripts/)
│   ├── documentation-writer/     # structured Markdown docs (README, DESIGN, refs)
│   └── mermaid-architecture-diagrams/ # architecture diagrams for docs
└── agents/                # focused delegate set
    ├── cli-developer.md          ├── data-engineer.md
    ├── data-scientist.md         ├── ml-engineer.md
    ├── documentation-engineer.md ├── readme-generator.md
    ├── code-reviewer.md          └── qa-expert.md
```

## Quick start

1. Place this `.claude/` folder at the root of the target project.
2. (Recommended) install the linters the tool relies on: `shellcheck`, `jq`,
   `ffmpeg`/`ffprobe`, and a parquet reader (`duckdb` or `python3` + pyarrow).
3. Open Claude Code in that directory. Start with `/wizard` to plan, `/bash` and
   `/lerobot-inspector` while implementing, and `/documentation-writer` for docs.

## Notes

- **Scaffolding only** — the `lerobot-inspect` script is intentionally not written
  yet; it will be built against the real dataset once provided.
- The shellcheck hook uses `$CLAUDE_PROJECT_DIR`; if your setup doesn't provide
  it, edit the path in `settings.json`.
- Everything here is provenance-tracked in [`PROVENANCE.md`](PROVENANCE.md).
