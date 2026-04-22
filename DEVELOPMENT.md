# Development Notes

## Summary

This project is an exploration of the **personal software** space — software built for and by an individual, optimized entirely for their own context rather than for general audiences or production scale.

The experiment: build a working end-to-end system (LLM-driven agents controlling a physical Vestaboard display) while intentionally staying hands-off on the code. The goal was to see how far Claude Code could take a non-trivial hardware + LLM integration with minimal direct intervention on the implementation details.

## Insights

### E2E tests as a feedback loop for real-world behavior

The biggest insight from this project was creating a **dedicated E2E test suite that probes real-world conditions** — not just unit correctness — and using it as a loop for the LLM to discover and fix its own bugs.

Unit tests verify logic in isolation. But hardware integrations fail in ways that unit tests can't anticipate: the board crashes under rapid-fire writes, read-back responses come back in an unexpected JSON format, frame timing assumptions break down physically. The E2E suite surfaced all of these.

The pattern that worked well:
1. Write an E2E test that asserts the *observable behavior* you care about (e.g. "the snake head moves exactly one cell per frame")
2. Run it against the real board in a loop
3. Let the failures guide the fix — the assertion message becomes the bug report

This is a tighter loop than the typical "write code, manually test, write more code" cycle, and it scales naturally as the system gets more complex.
