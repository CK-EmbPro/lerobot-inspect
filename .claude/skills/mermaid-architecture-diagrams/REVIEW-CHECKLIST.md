# Adversarial self-review

Review your rendered previews through three lenses, in this order. Be hostile: the job is to find what's wrong. "Looks fine" is not a review result.

## Lens 1 — Print legibility & robustness

- [ ] Effective text size: would the smallest text survive printing at document text width (~15.5 cm)? Inspect the *preview*, not the full-res render — it approximates print scale.
- [ ] Zero clipped or wrapped-out-of-box text (subgraph titles are the usual offender)
- [ ] No node/label overlaps; no edge-label collisions; labels visually attached to their edges
- [ ] Edge crossings within budget (≤2–3; zero where achievable)
- [ ] Density: is there dead space in one corner while another corner is crammed?

## Lens 2 — Visual design & consistency

- [ ] Visual hierarchy: does the eye land on the main story first?
- [ ] Color/token compliance: every color carries its declared meaning; accent color used only for "look here"
- [ ] Cross-diagram consistency (sets): identical init, tokens, edge grammar, entity naming, legend treatment
- [ ] Signal-to-ink: every box, line, and word earns its place
- [ ] Legend present where semantics aren't self-evident (in-diagram or explicitly caption-carried)

## Lens 3 — Comprehension & correctness

- [ ] The 5-second test: state aloud the story you grasp in 5 seconds — is it the *right* story?
- [ ] Every required fact present; every omission deliberate and recorded
- [ ] **No invented facts** — every node, edge, port, and label traces to a verified source
- [ ] No misleading geometry (an edge landing on the wrong box, containment implying false shared fate)
- [ ] Useful to the two extreme readers: the on-call engineer at 3 AM and the external auditor

## High-stakes pattern: variant competition

When a diagram set really matters, single-shot authoring underperforms. The pattern that works:

1. **Fix the content contract first**: a facts file every variant must honor (inventions disqualify), and a design brief with the token system.
2. **Wave 1**: generate 5–8 complete variants, each pushing one distinct design direction (zoned layout, minimalist, outline-only, big-type print, shape-coded + legend, …). Each author renders and self-reviews before submitting.
3. **Adversarial judging**: independent judges score every variant through the three lenses above (calibrate: a known baseline ≈ 5/10), producing scores *and concrete flaw lists*.
4. **Wave 2**: recombine — new variants merge the strongest elements of the podium and fix the judges' flaw lists.
5. **Judge again, then polish**: take the winner, fix only its remaining flaws (no redesign), and verify the polish actually beat the original head-to-head.

Keep every candidate; the losers document why the winner won.
