---
name: brainstorming
description: "Use before building a new feature or making an architectural change in Glass Monitor: agree on what to build through short questions and 2-3 approaches before writing code."
---

# Brainstorming

Turn a rough idea into an agreed design before any code is written. The design can be a
few sentences in chat; it has to exist, and the user has to agree to it.

## When to use it

New features, new pages or cards, new data sources (an API, a sensor, a system framework),
changes to how the panel or models are structured. Skip it for bug fixes and small, obvious
tweaks.

## How

1. **Look first.** Read the relevant code and find the nearest existing feature that works
   the same way (a card, a page, a poller). Summarise your understanding in 2-3 sentences.
   Never ask the user something the code answers.
2. **Ask one question at a time**, multiple choice where possible, with your recommended
   answer first and a one-line reason.
3. **Propose 2-3 approaches** with trade-offs; lead with the recommendation and say what it
   gives up.
4. **YAGNI.** The smallest version that solves the problem; no extra options or settings
   nobody asked for.
5. **Write the agreed design in chat**: what changes, which files, edge cases, and how it will
   be verified (tests, a `./dev.sh` scenario, a Debug-menu simulation).
6. Start coding only after the user says go.

## Questions for anything that talks to the outside world

When the feature adds a network call, a system API, or stored state, the design answers:

- **Source of truth** — where the data comes from, and is any copy only a cache?
- **Freshness and cost** — how often it is fetched, the rate limits, and the backoff on failure.
- **Failure** — what the user sees when it is offline, slow or broken; keep the last good value?
- **Privacy** — what leaves the Mac, which permission prompt appears, and whether a token or
  the location is involved.
- **Testability** — which part is a pure function that `swift test` can cover, and how to
  simulate the rest in the Debug menu.

## Anti-patterns

- Writing code before agreement.
- Several questions in one message.
- Only one approach presented.
- A long spec for a small change.
