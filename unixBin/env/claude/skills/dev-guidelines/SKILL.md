---
name: dev-guidelines
description: Use when planning features, implementing code, refactoring, writing tests, or creating implementation plans. Applies to any software development task that involves writing or modifying code.
---

# Development Guidelines

Apply these guidelines when planning, implementing, or refactoring code.

## Core Principles

- **SOLID Principles**: Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion
- **DRY**: Don't Repeat Yourself - extract common logic into reusable functions
- **KISS**: Keep It Simple, Stupid - simple solutions are usually better
- **Maintainability**: Code should be flexible, testable, readable, and maintainable (see Design for Testability, Efficiency and Concurrency below)

## Design for Testability and Maintenance

- Separate I/O from logic: pure functions decide, thin edges read and write. *Why: pure functions are tested without setup.*
- Pass dependencies in (clock, file system, network client, subprocess runner) instead of creating them inside the function. *Why: a test substitutes them without patching.*
- Use a design pattern only for a concrete need you can name (a second implementation, a test double, a real variation point); write the need in one sentence. *Why: a pattern without a need is complexity.*
- Do NOT over-complicate the code: the simple solution usually wins. Ask if unsure whether a pattern is needed.
- Prefer composition over inheritance

## Efficiency

Simple and cheap first; optimize only with evidence (a measurement or a clear cost estimate), and state it.

- Do work once: no repeated read, subprocess or API call for the same data; read once and pass the result on. *Why: cost grows with every repeat.*
- Move loop-invariant work out of loops (compiling a pattern, loading a config, resolving an id).
- Batch calls to external systems: one request for many items, not one request per item. *Why: round trips and rate limits dominate.*
- No accidental quadratic behaviour: no nested scans of the same collection, no membership test on a list inside a loop (use a set or dict), no building a large string or list by repeated concatenation.
- No needless copies of large data; iterate or stream when one pass is enough.

## Concurrency

Sequential by default. Multi-threading, async or multiprocessing only where the gain is real and larger than the complexity it adds.

- Appropriate when the tasks are independent (no shared mutable state) AND either I/O-bound with many waits (threads or async) or CPU-heavy with enough work per task to pay for the start-up (processes).
- Not appropriate when: the work is small or dominated by one call; the tasks depend on each other or on ordering; the tasks share mutable state that needs locks; the target is rate-limited (parallel calls only hit the limit sooner); or the gain is not measured or estimated.
- When used: bounded number of workers, deterministic result order, errors propagate to the caller, and a test covers it. Say in the PR why it is worth it.

## Refactoring Rules

- Do NOT keep any backwards compatibility when refactoring
- Remove unused code completely - no `_unused_var` patterns or `# removed` comments
- Prefer early returns to reduce nesting

## Test-Driven Development (TDD)

- Use TDD when refactoring or implementing - write tests FIRST
- Create valid baseline test data in the arrange block, then copy and modify for each test case
- This avoids bloated tests with many lines of setup code

## Unit Testing Best Practices

- Import packages at the file level, NOT inside test functions (faster test execution)
- Do NOT mock the logger - log output can change without affecting test validity
- Follow 1:1 mapping between production and test files with `test_` prefix
- Use pytest parametrize for testing multiple similar cases

## Code Quality

- Do NOT use hard-coded strings - use `StrEnum` or constants instead
- `StrEnum` is preferred over constants (usually already defined somewhere)
- Use Python type hints for better IDE support and documentation
- Keep functions small and focused (Single Responsibility)
- Use descriptive names that reveal intent

## Error Handling

- Validate inputs early (fail-fast principle)
- Be specific with exceptions - avoid catching generic `Exception`
- Use Single Exception Boundary pattern - catch exceptions at well-defined boundaries

## Documentation

- Update documentation when modifying code
- Use Mermaid diagrams to visualize architecture or flow
- Visual documentation is always better for understanding code

## Progress Tracking

- Create a new section in `docs/todo/todo_list.md` to track progress on features
- Use checkboxes `[x]` to mark completed items
- Include phase breakdowns for larger features
