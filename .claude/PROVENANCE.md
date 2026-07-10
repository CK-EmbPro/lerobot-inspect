# Provenance — where each artifact came from

This bundle groups artifacts drawn from the source folders alongside it, plus
new skills authored specifically for this project.

## Copied verbatim from provided sources

| Bundle path | Source |
|-------------|--------|
| `skills/bash/` | `public-skills-main/skills/bash/` (repo-specific `CLAUDE.md` removed) |
| `skills/detecting-data-anomalies/` | `detecting-data-anomalies/` |
| `skills/mermaid-architecture-diagrams/` | `public-skills-main/skills/mermaid-architecture-diagrams/` |
| `skills/wizard/` | `claude-wizard/.claude/skills/wizard/` |
| `agents/data-engineer.md` | `awesome-claude-code-subagents/categories/05-data-ai/` |
| `agents/data-scientist.md` | `awesome-claude-code-subagents/categories/05-data-ai/` |
| `agents/ml-engineer.md` | `awesome-claude-code-subagents/categories/05-data-ai/` |
| `agents/cli-developer.md` | `awesome-claude-code-subagents/categories/06-developer-experience/` |
| `agents/documentation-engineer.md` | `awesome-claude-code-subagents/categories/06-developer-experience/` |
| `agents/readme-generator.md` | `awesome-claude-code-subagents/categories/06-developer-experience/` |
| `agents/code-reviewer.md` | `awesome-claude-code-subagents/categories/04-quality-security/` |
| `agents/qa-expert.md` | `awesome-claude-code-subagents/categories/04-quality-security/` |

## Authored for this project

| Bundle path | Purpose |
|-------------|---------|
| `CLAUDE.md` | Main project description + working guidance |
| `settings.json` | Registers the shellcheck PostToolUse hook |
| `hooks/shellcheck-hook.sh` | Enforces shellcheck-clean shell scripts |
| `skills/lerobot-inspector/` | LeRobot domain knowledge + the 14 checks + references |
| `skills/dataset-handling/` | General ML dataset analysis/prep/processing pipeline |
| `skills/documentation-writer/` | Structured Markdown documentation standards |
| `README.md`, `PROVENANCE.md` | Bundle guide + this provenance record |

## Sources present in the parent folder but not bundled (and why)

- `awesome-claude-code-subagents-main/`, `public-skills-main (2)/`,
  `claude-customisations/` — duplicate copies of the sources above.
- `public-skills-main/skills/quarto-doc-setup/`, `from-pdf-skill-builder/` —
  out of scope (PDF/LaTeX publishing and skill-generation); the project asked for
  detailed **Markdown** docs, covered by `documentation-writer`.
- The remaining ~60 subagents in the catalog — outside the focused set chosen for
  this project (data/ML, CLI, docs, quality).
