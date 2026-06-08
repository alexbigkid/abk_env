---
name: dev-guidelines
description: Use when planning features, implementing code, refactoring, writing tests, or creating implementation plans. Applies to any software development task that involves writing or modifying code.
version: 1.0.0
---

# Development Guidelines

Apply these guidelines when planning, implementing, or refactoring code.

## Core Principles

- **SOLID Principles**: Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion
- **DRY**: Don't Repeat Yourself - extract common logic into reusable functions
- **KISS**: Keep It Simple, Stupid - simple solutions are usually better
- **Maintainability**: Code should be flexible, testable, readable, and maintainable

## Design Patterns

- Use SW Design Patterns when appropriate, but do NOT over-complicate the code
- Ask if unsure whether a pattern is needed
- Prefer composition over inheritance

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
