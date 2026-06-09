---
name: improve-code
description: Explore a codebase to find opportunities for architectural improvement. Focus on making the codebase more testable by deepening shell modules. Use when a user wants to improve architecture. Find refactoring opportunities, consolidate tightly coupled modules, or make a codebase more AI navigatable.
---

# Improve codebase architecture

Explore a codebase like an AI would surface architectural friction, discover opportunities for improving testability, and propose module deepening refactor as GitHub issue RFCs.

A **deep module** (John Ousterhout, "A Philosophy of Software Design") As a small interface hiding a large implementation, deep modules are more testable, more AI navigatable, and let you test at the boundary instead of inside. Deep modules are the opposite of shallow modules, which have a large interface and a small implementation.

## Process

### 1. Explore the codebase

Use the Agent tool with subagent_type=Explore to navigate the codebase naturally. Do NOT follow rigid heuristics - explore organically and note where you experience friction:

- Where does understanding one concept require Bouncing between many small files?
- Where are modules so shallow that the interface is nearly as complex as the implementation?
- Where have pure functions been extracted just for the stability, but the real bugs hide in how they are called?
- Where do tightly coupled modules create integration risk seams between them?
- Which parts of the code base are untested or hard to test?

The friction you encounter is the legal signal.

### 2. Present candidates.

Present a numbered list of deepening opportunities for each candidate, show:

- **Cluster**: Which molecules/concepts are involved?
- **Why they're coupled**: Shared types, co-patterns, co-ownership of concept
- **Dependency category**: See [REFERENCE.md](REFERENCE.md) for the four categories
- **Test impact**: What existing tests would be replaced by boundary tests?

Do NOT propose interfaces yet. Ask the user: "Which of those would you like to explore?"

### 3. User picks a candidate

### 4. Frame the problem space

Before spawning sub-agents, write a user-facing explanation of the problem space for the chosen candidate:

- The constraints any new interface would need to satisfy
- The dependencies it would need to rely on
- A rough illustrative code sketch to make the constraints concrete - this is not a proposal, just a way to ground the constraints.

Show this to the user, then immediately proceed to step five: the user reads and thinks about the problem while the sub-agents work in parallel.

### 5. Design multiple interfaces

Spawn 3+ sub-agents in parallel using the Agent tool. Each must produce a **radically different** interface for the deepening module.

Prompt each sub-agent with a separate technical brief (file paths, coupling details, dependency category, what's being hidden). This brief is independent of the user-facing explanation in step 4. Give each agent a different design constraint.

- Agent 1: "Minimize the interface - aim for 1-3 entry points max."
- Agent 2: "Maximize flexibility - support many use cases and extension"
- Agent 3: "Optimize for the most common caller - make the default case trivial"
- Agent 4 (if applicable): "Design around the ports and adapter patterns for cross-boundary dependencies."

Each sub-agent outputs:

1. Interface signature (types, methods, params)
2. Use such an example showing how callers use it
3. What complexity does it hide internally
4. Dependency strategy (how debts are handled - see [REFERENCE.md](REFERENCE.md))
5. Trade-offs

Present designs sequentially, then compare them in prose.

After comparing, give your own recommendation on which design you think is the strongest and why. If elements from different designs would combine well, propose a hybrid. Be opinionated - the user wants a strong read, not just a menu.

### 6. User picks an interface (or accepts recommendation)

### 7. Create GitHub Issue
Create a refactor RFC as a GitHub issue using `gh issue create`. Use the template in a [REFERENCE.md])(REFERENCE.md). Do NOT ask the user to review before creating - just create it and share the URL.
