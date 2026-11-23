---
name: review
description: Review the changes since a fixed point (commit, branch, tag, or merge-base) along three axes — Standards (does the code follow this repo's documented coding standards?), Spec (does the code match what the originating issue/PRD asked for?) and Quality (efficiency, concurrency, design for testability). Runs the reviews in parallel sub-agents and reports them side by side. Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to "review since X". Also used by the reviewer agent to review the pull request of an issue in the Review column (see PR-MODE.md).
---

# Review

Three-axis review of the diff between `HEAD` and a fixed point the user supplies:

- **Standards** — does the code conform to this repo's documented coding standards? use `/dev-guidelines` skill.
- **Spec** — does the code faithfully implement the originating issue / PRD / spec?
- **Quality** — is the code efficient, parallel only where that pays, and built so it can be tested and changed? The criteria are the Efficiency, Concurrency and Design for Testability sections of `/dev-guidelines`.

All three axes run as **parallel sub-agents** so they don't pollute each other's context, then this skill aggregates their findings.

The issue tracker should have been provided to you — run `/setup-skill` if `docs/agents/issue-tracker.md` is missing.

## Process

### 1. Pin the fixed point

Whatever the user said is the fixed point — a commit SHA, branch name, tag, `main`, `HEAD~5`, etc. Don't be opinionated; pass it through. If they didn't specify one, ask: "Review against what — a branch, a commit, or `main`?" Don't proceed until you have it.

Capture the diff command once: `git diff <fixed-point>...HEAD` (three-dot, so the comparison is against the merge-base). Also note the list of commits via `git log <fixed-point>..HEAD --oneline`.

### 2. Identify the spec source

Look for the originating spec, in this order:

1. Issue references in the commit messages (`#123`, `Closes #45`, GitLab `!67`, etc.) — fetch via the workflow in `docs/agents/issue-tracker.md`.
2. A path the user passed as an argument.
3. A PRD/spec file under `docs/`, `specs/`, or `.scratch/` matching the branch name or feature.
4. If nothing is found, ask the user where the spec is. If they say there isn't one, the **Spec** sub-agent will skip and report "no spec available".

### 3. Identify the standards sources

Anything in the repo that documents how code should be written. Common locations:

- `CLAUDE.md`, `AGENTS.md`
- `CONTRIBUTING.md`
- `CONTEXT.md`, `CONTEXT-MAP.md`, per-context `CONTEXT.md` files
- `docs/adr/` (architectural decisions are standards)
- For TS projects: `.editorconfig`, `eslint.config.*`, `biome.json`, `prettier.config.*`, `tsconfig.json` (machine-enforced standards — note them but don't re-check what tooling already checks)
- For Python projects: `pyproject.toml`, `ruff.toml`, `mypy.ini`, `setup.cfg` you can use rule `just lint` for linting
- Any `STYLE.md`, `STANDARDS.md`, `STYLEGUIDE.md`, or similar at the repo root or under `docs/`

Collect the list of files. The **Standards** sub-agent will read them.

### 4. Spawn the three sub-agents in parallel

Send a single message with three `Agent` tool calls. Use the `general-purpose` subagent for all.

**Standards sub-agent prompt** — include:

- The full diff command and commit list.
- The list of standards-source files you found in step 3.
- The brief: "Read the standards docs. Then read the diff. Report — per file/hunk where relevant — every place the diff violates a documented standard. Cite the standard (file + the rule). Distinguish hard violations from judgement calls. Skip anything tooling enforces. Under 400 words."

**Spec sub-agent prompt** — include:

- The diff command and commit list.
- The path or fetched contents of the spec.
- The brief: "Read the spec. Then read the diff. Report: (a) requirements the spec asked for that are missing or partial; (b) behaviour in the diff that wasn't asked for (scope creep); (c) requirements that look implemented but where the implementation looks wrong. Quote the spec line for each finding. Under 400 words."

**Quality sub-agent prompt** — include:

- The diff command and commit list.
- The path of the `dev-guidelines` skill.
- The brief: "Read the Efficiency, Concurrency and Design for Testability sections of dev-guidelines. Then read the diff. Report, citing the section and the rule for each (Efficiency, Concurrency or Design for Testability): (a) wasted work: repeated I/O, subprocess or API calls for the same data, avoidable work in loops, needless copies, accidental quadratic behaviour; (b) concurrency, only where the gain is real (independent I/O-bound or CPU-heavy work), otherwise say nothing about it; (c) code that is hard to test or change: I/O mixed into logic, hidden dependencies, a pattern without a named need or a missing seam where a test needs one. Mark each finding as clear (obvious waste, or untestable by design) or judgement call. Skip what the Standards axis covers and what tooling checks. Under 400 words."

If the spec is missing, skip the Spec sub-agent and note this in the final report.

### 5. Aggregate

Present the three reports under `## Standards`, `## Spec` and `## Quality` headings, verbatim or lightly cleaned. Do **not** merge or rerank findings — the axes are deliberately separate so the user can see them independently.

End with a one-line summary: total findings per axis, and the worst single issue (if any) flagged.

## Why separate axes

A change can pass one axis and fail another:

- Code that follows every standard but implements the wrong thing → **Standards pass, Spec fail.**
- Code that does exactly what the issue asked but breaks the project's conventions → **Spec pass, Standards fail.**
- Code that is correct and follows the conventions but wastes work or cannot be tested → **Quality fail.**

Reporting them separately stops one axis from masking another.

## PR mode

The reviewer agent uses the same three axes on the pull request of an issue in the Review column: one review with `[must-fix]` / `[suggestion]` findings, a board move and a round cap. That procedure is in [PR-MODE.md](PR-MODE.md); everything above stays as it is for standalone use.
