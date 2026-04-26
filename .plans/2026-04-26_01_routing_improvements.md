# Phase 16 — Agent Routing Improvements

**Branch:** `phase/16-routing-improvements`
**Date:** 2026-04-26

---

## Goal

Replace the current brittle two-tier routing with a smarter two-tier system where **both tiers use confidence**:

1. **Tier 1 — Scored keyword matching**: score every agent by how many of its keywords appear in the prompt; pick the highest scorer. Falls through only when no agent matches at all.
2. **Tier 2 — LLM with confidence**: LLM returns `name:confidence`; if confidence is below threshold, treat as no match and fall through to DynamicAgent.

Current problems this fixes:

- Keyword matching is binary and order-dependent — the first agent whose any keyword appears wins. A prompt like "show the Lakers game score every hour" routes to `ScheduleAgent` (listed before `SportsAgent`) just because "every" matched first.
- LLM routing returns only a name — a low-confidence or hallucinated pick looks identical to a confident one.

The improvements below are in dependency order — each builds on the previous.

---

## 16a — Routing Confidence Score

### What changes

`LLM.route_agent/3` currently returns `{:ok, String.t()}`. Change it to return `{:ok, String.t(), float()}` where the float is a 0.0–1.0 confidence score. The routing prompt will ask the LLM to respond as `name:confidence` (e.g. `weather:0.85`). If confidence is below **0.55**, `Registry.resolve/2` skips to `DynamicAgent` rather than trusting a weak pick.

### Prompt change

```
Reply with ONLY: agent_name:confidence
where confidence is 0.0 to 1.0 (your certainty this is the right handler).
Example: weather:0.9
```

### Parser

```elixir
defp parse_routing_response(raw) do
  case String.split(String.trim(raw), ":") do
    [name, conf] ->
      case Float.parse(conf) do
        {score, _} -> {:ok, String.downcase(name), min(max(score, 0.0), 1.0)}
        :error     -> {:ok, String.downcase(name), 1.0}
      end
    [name] ->
      {:ok, String.downcase(name), 1.0}
    _ ->
      {:error, :bad_response}
  end
end
```

### Registry changes

`resolve/2` receives `{:ok, name, confidence}`. Add a `@routing_confidence_threshold 0.55` module attribute. If `confidence < threshold`, treat as no LLM match → fall through to `DynamicAgent`.

### Files touched

| File | Change |
|---|---|
| `lib/vestaboard_agent/clients/anthropic.ex` | `routing_prompt` appends confidence instruction; `route_agent` spec updated to `{:ok, String.t(), float()}`; new `parse_routing_response/1` private |
| `lib/vestaboard_agent/agent/registry.ex` | `resolve/2` handles 3-tuple; `@routing_confidence_threshold` added |
| `test/vestaboard_agent/clients/anthropic_test.exs` | Update stubs to return `name:0.9`; add test for low-confidence (`name:0.2`) parsing; test missing confidence falls back to 1.0 |
| `test/vestaboard_agent/agent/registry_test.exs` | Add test: LLM returns low-confidence → falls through to DynamicAgent |

---

## 16b — Routing Evaluation Dataset

### What

A new E2E test file that runs `Registry.resolve/2` against the live LLM with a fixed set of 20 labelled prompts and asserts overall accuracy ≥ 85%.

### File

`test/e2e/08_routing_eval_test.exs`

### Dataset

| Prompt | Expected agent |
|---|---|
| "say hello" | greeter |
| "good morning vestaboard" | greeter |
| "what's the weather today?" | weather |
| "how hot is it outside?" | weather |
| "show the forecast" | weather |
| "Lakers score" | sports |
| "did the Chiefs win last night?" | sports |
| "show me NBA scores" | sports |
| "show the time every 10 seconds" | schedule |
| "remind me every hour with the weather" | schedule |
| "play snake" | snake |
| "start a snake game" | snake |
| "who invented the telephone?" | conversational |
| "what is the speed of light?" | conversational |
| "tell me about Einstein" | conversational |
| "display hello world" | display |
| "show bitcoin price" | dynamic |
| "what's the current price of gold?" | dynamic |
| "display a countdown to Friday" | dynamic |
| "show me a fun fact about space" | dynamic |

### Test structure

```elixir
@dataset [
  {"say hello", "greeter"},
  # ... all 20
]

test "routing accuracy >= 85%" do
  results =
    Enum.map(@dataset, fn {prompt, expected} ->
      {:ok, agent} = Registry.resolve(prompt, %{})
      {prompt, expected, agent.name()}
    end)

  correct = Enum.count(results, fn {_, exp, got} -> exp == got end)
  accuracy = correct / length(results)
  
  failures = Enum.reject(results, fn {_, exp, got} -> exp == got end)
  IO.inspect(failures, label: "routing misses")
  
  assert accuracy >= 0.85
end
```

### Notes

- Uses `async: false` (hits live LLM).
- Requires `ANTHROPIC_API_KEY` (guarded in `setup_all`, same pattern as other E2E files).
- Gives a failure list of which prompts were misrouted — feeds directly back into improving the routing prompt or keyword lists.

---

## 16c — Scored Keyword Routing

### Problem with current approach

`Registry.route/1` uses `Enum.find_value` — first agent whose ANY keyword appears in the prompt wins. Order in `@default_agents` is the tiebreaker. This means a prompt with strong sports signals routes to `ScheduleAgent` if it also contains "every".

### New approach

Replace binary first-match with **scored best-match**:

1. Tokenize the prompt: lowercase, split on `~r/[\s,!?.]+/`.
2. For each agent, compute `score = matched_keyword_count / max(prompt_token_count, 1)`.
3. Pick the agent with the highest score, provided `score >= @keyword_score_threshold` (0.05 — even one match out of 20 tokens qualifies).
4. Tie-break by registry order (same semantics as before).
5. If no agent exceeds the threshold, return `{:error, :no_match}` as before.

### Example

Prompt: `"show the Lakers game score every hour"` → tokens: `["show", "the", "lakers", "game", "score", "every", "hour"]` (7 tokens)

| Agent | Matched keywords | Score |
|---|---|---|
| SportsAgent | game, score | 2/7 = 0.29 |
| ScheduleAgent | every | 1/7 = 0.14 |

SportsAgent wins. Previously, ScheduleAgent won because it's earlier in the list.

### Files touched

| File | Change |
|---|---|
| `lib/vestaboard_agent/agent/registry.ex` | Replace `handle_call({:route, ...})` with scored implementation; add `@keyword_score_threshold 0.05` and `score_agent/3` private |
| `test/vestaboard_agent/agent/registry_test.exs` | Add test: multi-keyword ambiguous prompt picks agent with more matches, not first in list |

### Note on "embeddings"

The PLAN.md item says "embedding-based routing." Anthropic doesn't expose an embeddings API, so we implement the spirit of it — score all agents against the prompt and pick best-match — without an external embedding service. This is faster, cheaper (zero API calls), and addresses the same root problem.

---

## Implementation Order

```
16a  →  16c  →  16b
```

- **16a first** — confidence threshold in `resolve/2` is a prerequisite for meaningful eval results.
- **16c next** — scored keyword routing fixes the order-dependence problem before we measure accuracy.
- **16b last** — eval dataset runs against the fully-improved pipeline to measure the real gain.

---

## Definition of Done

- [ ] `mix test` passes (all unit tests green)
- [ ] `mix test.e2e test/e2e/08_routing_eval_test.exs` passes with ≥ 85% accuracy
- [ ] `GET /status` returns routing trace JSON after a `/chat` call
- [ ] Logger shows `[routing]` lines for each dispatch
- [ ] `mix format` clean
