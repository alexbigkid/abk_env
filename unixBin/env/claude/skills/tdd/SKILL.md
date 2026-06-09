---
name: tdd
description: Test during development with red-green-refactor loop. Use when user wants to build features or fix bugs using TDD. Mention red-green-refactor once integration tests or ask for test-first development. Use the red-green-refactor loop to guide the user through the process.
---

# Test-Driven Development

## Philosophy

**Core principle**: Tests should verify behavior through public interfaces, not implementation details. Code can change entirely, tests shouldn't!

**Good tests** are integration-style: they exercise real code paths through public APIs. They describe _what_ the system does, not _how_ it does it. A good test reads like a specification - "user can check out with valid cart" tells you exactly what capability exist. These tests survive  refactors because they don't care about internal structure.

**Bad tests** are coupled to implementation. They mock internal collaborators test private methods or verify through external means (like querying a database directly instead of using the interface). The warning sign: your test breaks when you refactor, but behavior hasn't changed. If you rename an internal function and the test fails, those tests were testing implementation, not behavior.

See [test.md](test.md) for examples and [mocking.md](mocking.md) for mocking guidelines.

## Anti-Pattern Horizontal Slices
**DO NOT write all paths first, then all implementations.** This is "horizontal slicing" - treating RED as "write all tests" and GREEN as "write all code".

This produces **bad tests**:

- Tests written in bulk test _imagined_ behavior, not _actual_ behavior. You end up testing the shape of things: data structures, function signatures, rather than the user-facing behavior.
- Tests become insensitive to real changes - they pass when behavior breaks, fail when behavior is fine.
- You outrun your headlights, committing to test structure before understanding the implementation.

**Correct approach**: Vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle, because you just wrote that code. You know exactly what behavior matters and how to verify it.

```
WRONG (horizontal):
  RED:    test1, test2, test3, test4, test5
  GREEN:  impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
  RED→GREEN: test4→impl4
  RED→GREEN: test5→impl5
```

## Workflow

### 1. Planning

Before writing any code:

- [ ] Confirm with user what interface changes are needed
- [ ] Confirm with user which behaviors to test (prioritize)
- [ ] Identify opportunities for [deep modules](deep-modules.md) (small interfaces, deep implementation)
- [ ] Design interfaces for [testability](interface-design.md)
- [ ] List the behaviors to test (not implementation steps).
- [ ] Get user approval on the plan.

Ask: "what the public interface should look like? Which behaviors are most important to test?"

**You can't test everything.** Confirm with the user exactly which behavior matter most. Focus testing effort on critical paths and complex logic, not every possible edge case.

### 2. Tracer Bullet

Write one test that confirms one thing about the system:
```
RED:   Write test for first behavior -> test fails
GREEN: Write minimal code to pass test -> test passes
```

This is your tracer bullet - prove the path works end to end.

### 3. Incremental Loop

For each remaining behavior:
```
RED:   Write test for next behavior -> test fails
GREEN: Write minimal code to pass test -> test passes
```

Rules:
- One test at a time.
- Only enough code to pass current test.
- Don't anticipate future tests.
- Keep test focus on observable behavior.


### 4. Refactor

After all tests pass, look for refactor candidates:

- [ ] Extract duplication.
- [ ] Deepen modules (move complexity behind simple interfaces).
- [ ] Apply SOLID principles where natural.
- [ ] Improve testability.
- [ ] Improve readability.
- [ ] Consider what the new code reveals about existing code.
- [ ] Run tests after each refactor step.
- [ ] Mark places where design pattern can improve code. (Factory, Strategy, etc.)

**Never refactor while RED.** Get to GREEN first.

## Checklist Per Cycle

```
[ ] Test describes behavior, not implementation.
[ ] Test uses public interface only.
[ ] Test would survive an internal refactor.
[ ] Code is minimal for this test.
[ ] No speculative features added.
```
