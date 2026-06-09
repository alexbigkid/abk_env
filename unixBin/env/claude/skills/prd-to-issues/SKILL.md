---
name: prd-to-issues
description:
version: 1.0.0
---

# PRD to Issues
Break a PRD into independently-grabbable GitHub issues using vertical slices (tracer bullets).

## Process

### 1. Locate the PRD
Ask the user for the PRT GitHub issue number (or URL)..

If the PRD is not already in your contacts window, fetch it with the `gh issue view <number>` (with comments).

### 2. Export a codebase (optional)
If you have not already explored the code base, do so to understand the current state of the code.

### 3. Draft vertical slices
Break the PRD into tracer bullet issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.
Slices may be 'HITL' or 'AFK'. 'HITL' slices require human interaction, such as an architectural decision or design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but complete path through every layer (schema, API, UI, tests).
- Completed slice is demoable or verifiable on its own.
- Prefer many thin slices over a few thick ones.
</vertical-slice-rules>

### Quiz user
