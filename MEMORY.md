# VestaboardAgent — Project Memory

Running notes on conventions, decisions, and preferences discovered across conversations.
Update this file whenever something new is learned.

---

## Conventions & Workflow

- **Tests are required for every new module.** Every new `.ex` file needs a matching `_test.exs` mirroring the `lib/` path. Every public function needs at least one happy-path test. Run `mix test` after writing code, not just at the end.

- **Always run `mix format` before committing.** CI enforces it and will fail otherwise.

- **Keep PLAN.md current.** Mark items ✅ when done. Add new planned work to the relevant phase _before_ starting it. Commit PLAN.md alongside related code or separately if plan-only.

- **Detailed plans go in `.plans/`.** Use the naming convention `YYYY-MM-DD_NN_<slug>.md` (zero-padded daily index). Link from the `| Plan | File |` table at the top of PLAN.md. Never write multi-step breakdowns inline in PLAN.md itself.

- **Always update this file.** Whenever a new convention, preference, or decision is established in conversation, add it here so future sessions have full context.

---

## Architecture Decisions

- Routing has three tiers: keyword match → LLM routing → DynamicAgent fallback. All routing logic lives in `Agent.Registry` and agent modules — never add special cases to `do_display/2`.

- All HTTP clients live under `lib/vestaboard_agent/clients/`. Tools delegate to clients and do only filtering/formatting — no HTTP in tool modules.

- Long-running agents use `Process.send_after` + `receive` loops (not `Process.sleep`) so the message token is visible in crash dumps and the process stays interruptible.

- Sandbox scripting (Lua) goes through the `VestaboardAgent.Sandbox` behaviour. Swap runtimes by changing config — nothing else changes.

---

## Security

- **Never call `String.to_atom/1` on user input.** Atoms are not GC'd; exhausting the atom table crashes the VM. Use plain strings, or `String.to_existing_atom/1` if an atom is truly needed. Known instance: `DynamicAgent.derive_tool_name/1` (tracked in Cleanup section of PLAN.md).

---

## Agent Notes

- `ExplainAgent` reads `Registry.last_routing/0` from an ETS table (`:routing_info`). Every `Registry.resolve/2` call writes to it — method is `:keyword`, `:llm`, or `:fallback`; confidence is a float or nil.

---

## Active Branches

None.
