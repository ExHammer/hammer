# AGENTS.md

Hammer is an Elixir rate-limiting library published on Hex as `hammer` (current version 7.5.0). Applications define a module with `use Hammer, backend: ...`, supervise it, and call `hit/3` (or `hit/4`) with a key, a scale in ms and a limit. It ships two in-VM backends (ETS and `:atomics`); external backends live in separate repos (`hammer-backend-redis`, `hammer-backend-mnesia`). It is a library: no database, no web layer, no deploy target. It is released to hex.pm and hexdocs.pm.

This checkout is the **upstream ExHammer repository**: `origin` is `git@github.com:ExHammer/hammer`, and `@source_url` in `mix.exs` is `https://github.com/ExHammer/hammer`. It is not a personal fork. Default branch is `master`.

## Project Overview

| Item | Value |
|---|---|
| Language | Elixir `~> 1.14` in `mix.exs`, but CI tests 1.17-1.20 only (see Gotchas) |
| Dev toolchain | Elixir 1.20.4 / OTP 29.0.5 (`.tool-versions`, `mise.toml`) |
| CI matrix | Elixir 1.17/OTP 27, 1.18/27, 1.19/27+28, 1.20/28+29 |
| Runtime deps | None (only `:logger`). `igniter` is `optional: true` (for `mix hammer.install`) |
| Dev/test deps | `credo ~> 1.7`, `dialyxir ~> 1.4`, `ex_doc ~> 0.34` (dev only), `benchee ~> 1.2` (`:bench` env only) |
| Application | `:hammer`; no supervision tree of its own (users start the generated module) |
| CI | GitHub Actions: `.github/workflows/ci.yml` (test + format), `publish.yml` (hex publish on any tag) |
| Docs | ExDoc; extras are `CHANGELOG.md`, `README.md`, `guides/*.md` |
| Coverage | `test_coverage: [summary: [threshold: 90]]` |
| License | MIT |

## Essential Commands

There are no custom mix aliases. There is no `precommit` alias. The quality gate is whatever CI runs.

```bash
# Setup
mix deps.get
```

```bash
# Test
mix test
mix test test/hammer/ets/token_bucket_test.exs          # single file
mix test test/hammer/ets/token_bucket_test.exs:12       # single test by line
mix test --warnings-as-errors --cover                   # exactly what CI runs
```

```bash
# Quality gate (run all before committing; mirrors CI)
mix deps.unlock --check-unused
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict --format=oneline
mix test --warnings-as-errors --cover
mix dialyzer                                            # not in CI, but configured (plt_add_apps: [:mix])
```

```bash
# Docs and benchmarks
mix docs
MIX_ENV=bench LIMIT=1 SCALE=5000 RANGE=200000 PARALLEL=600 mix run bench/base.exs   # env knobs: LIMIT, SCALE, RANGE, PARALLEL, PROFILE
```

```bash
# Installer (generates MyApp.RateLimit in a host app; needs igniter)
mix igniter.install hammer
mix hammer.install --backend ets      # or atomic | redis
```

If the shell does not pick up the pinned toolchain, `.claude/settings.local.json` allows `mise exec *`, so `mise exec -- mix test` works.

## Architecture

### The `use Hammer` flow

1. `lib/hammer.ex` defines the `Hammer` behaviour and `__using__/1`. It stores opts in `@hammer_opts`, requires `:backend` (raises `ArgumentError` otherwise), maps `:ets` to `Hammer.ETS` and `:atomic` to `Hammer.Atomic` (any other value is treated as a backend module), and registers `@before_compile backend`.
2. The backend's `__before_compile__/1` macro (in `Hammer.ETS`, `Hammer.Atomic`) reads `:algorithm` from `@hammer_opts`, resolves it to an algorithm module, then generates `child_spec/1`, `start_link/1`, and conditionally `hit/3`, `hit/4`, `inc/3`, `set/3`, `get/2`, `expires_at/2` by checking `function_exported?(@algorithm, name, arity)`. Which functions exist on a user's limiter therefore depends on the algorithm.
3. `start_link/1` injects `:table` (the user's module name) and defaults `:clean_period` to 1 minute, then calls `Hammer.ETS.start_link/1` / `Hammer.Atomic.start_link/1`, which start a GenServer that creates the table and periodically sends itself `:clean`.
4. Hot-path calls (`hit`, `inc`, ...) go straight from the user's module to `Algorithm.hit(table, key, ...)` against ETS/atomics. The GenServer is not on the hit path; it only owns the table and runs cleanup.

### Backend behaviour contract (`Hammer` callbacks)

- Only `hit/3` is required in the type sense; `hit/4`, `inc/2`, `inc/3`, `set/3`, `get/2`, `expires_at/2` are `@optional_callbacks`.
- `hit(key, scale, limit)` and `hit(key, scale, limit, increment)` return `{:allow, count} | {:deny, retry_after_ms}`.
- `inc` and `set` return the new count; `get` returns the current count; `expires_at` returns an absolute ms timestamp (0 if no active window) and exists for `:fix_window` only.
- `key` is `term()` for ETS/Atomic; the Redis backend requires string/binary keys.
- Types in `lib/hammer.ex`: `key`, `scale` (pos_integer ms), `limit`, `count`, `increment`.
- External backends (`Hammer.Redis`, `Hammer.Mnesia`) follow the same pattern: `use Hammer, backend: Hammer.Redis` triggers their own `__before_compile__` that generates `start_link/1` and `hit/3,4`. They declare `hammer` as a dependency, so a change to a callback signature, return shape, or option name breaks sibling repos. Redis adds `hit_many/1` and supports `:sliding_window`.

### Algorithm modules (verified in `lib/`)

Each algorithm module is plain functions over a table/atomic, not a process. It implements `ets_opts/0` (or atomic equivalent), `hit/4|5`, `clean/1`, `select_expired/1`, `normalize_expired/1` (the last two support `:before_clean`), plus optional `inc`, `set`, `get`, `expires_at`.

| Algorithm atom | ETS module | Atomic module |
|---|---|---|
| `:fix_window` (default) | `Hammer.ETS.FixWindow` | `Hammer.Atomic.FixWindow` |
| `:fix_window_per_key` | `Hammer.ETS.FixWindowPerKey` | `Hammer.Atomic.FixWindowPerKey` |
| `:sliding_window` | `Hammer.ETS.SlidingWindow` | none (see Gotchas) |
| `:leaky_bucket` | `Hammer.ETS.LeakyBucket` | `Hammer.Atomic.LeakyBucket` |
| `:token_bucket` | `Hammer.ETS.TokenBucket` | `Hammer.Atomic.TokenBucket` |

Notes by algorithm:

- Bucket algorithms (`LeakyBucket`, `TokenBucket`) take `hit(table, key, rate, capacity, cost)` rather than `(scale, limit)`; the generated `hit/3,4` just forwards positional args, so the meaning of args 2-3 changes with the algorithm. They do not export `inc/set/expires_at`.
- ETS `TokenBucket` uses millisecond refill resolution and carries the sub-token remainder across hits.
- Atomic `TokenBucket`/`LeakyBucket` pack state into a 64-bit atomic and update with `:atomics.compare_exchange` (CAS loop). The atomic reference is stored in ETS; it must be initialized before being inserted (7.5.0 fix, #202).
- `Hammer.ETS` and `Hammer.Atomic` map algorithm module to a name via private `algorithm_name/1` for `before_clean`; add a clause when adding an algorithm.

### Supporting modules

```
lib/
  hammer.ex                    Hammer behaviour, types, __using__/1
  hammer/ets.ex                ETS backend: __before_compile__, GenServer (table owner + :clean timer), now/0, update_counter/4
  hammer/atomic.ex             Atomic backend: same shape, option :algorithm_module instead of :algorithm
  hammer/clean_utils.ex        @moduledoc false; invoke_before_clean/3 (rescues, logs warning), delete_expired/2
  hammer/ets/*.ex              fix_window, fix_window_per_key, sliding_window, leaky_bucket, token_bucket
  hammer/atomic/*.ex           fix_window, fix_window_per_key, leaky_bucket, token_bucket
  mix/tasks/hammer.install.ex  Igniter installer (Mix.Tasks.Hammer.Install); compiled only when igniter is available
test/
  test_helper.exs              just ExUnit.start()
  support/clean_test_helpers.ex  Hammer.CleanTestHelpers.eventually/3 (polling), Hammer.CallbackHandler (MFA before_clean target); compiled via elixirc_paths(:test)
  hammer/ets_test.exs, hammer/atomic_test.exs           backend-level tests (start_link, use macro, options)
  hammer/ets/<algo>_test.exs, hammer/atomic/<algo>_test.exs   per-algorithm tests
  hammer/{ets,atomic}/clean_test.exs                    cleanup and before_clean behaviour
  term_keys_test.exs, atomic_term_keys_test.exs         non-string key types
  mix/tasks/hammer.install_test.exs                     Igniter test
bench/base.exs                 Benchee comparison across algorithms (MIX_ENV=bench)
guides/                        Tutorial.md, upgrade-v7.md, distributed-ets.md (shipped as ExDoc extras)
```

Runtime options (identical for both backends unless noted): `:clean_period` (default 1 min), `:key_older_than` (default 24 h in code; the `Hammer.ETS` moduledoc says 1 hour, which is stale), `:before_clean` (fun/2 or `{m, f, extra_args}`; receives `(algorithm_atom, [%{key:, value:, expired_at:}])`; exceptions are rescued and logged, entries are still deleted), `:algorithm`, plus GenServer opts `:debug`, `:spawn_opt`, `:hibernate_after`. Unknown opts only log a warning.

## Conventions

- Formatter is stock (`.formatter.exs` covers `{mix,.formatter}.exs` and `{lib,test}/**/*.{ex,exs}`); default 98-column line length. Credo runs `strict: true` with the default check set in `.credo.exs`; use `# credo:disable-for-next-line Credo.Check.X` sparingly, as `__before_compile__` does for cyclomatic complexity.
- Public modules have `@moduledoc` with a usage example and, for algorithms, an explanation of the algorithm plus when to use it. Internal modules use `@moduledoc false`. Public functions carry `@doc` and `@spec` (see `lib/hammer/ets/fix_window.ex`).
- Return values are tagged tuples `{:allow, count}` / `{:deny, retry_after_ms}`. Do not raise on a denied hit.
- Hot-path functions use `@compile inline:` and direct `:ets.update_counter`/`:atomics` operations; keep them lock-free and avoid GenServer calls on the hit path.
- Time is wall-clock milliseconds via `Hammer.ETS.now/0` (`System.system_time(:millisecond)`). Windows and expiry are stored as absolute ms timestamps.
- Every algorithm in both backends must expose the same shape (`ets_opts/0`, `hit`, `clean/1`, `select_expired/1`, `normalize_expired/1`) so `Hammer.ETS`/`Hammer.Atomic` stay algorithm-agnostic.
- Behaviour changes are documented in `CHANGELOG.md` with an explicit **Behaviour change:** callout (see 7.5.0).

## Testing

- Plain ExUnit, no property tests, no Mox, no time-mocking library. All test files use `async: true`.
- Isolation pattern: each test module defines its own limiter module (`defmodule RateLimitTokenBucket do use Hammer, backend: :ets, algorithm: :token_bucket end`) or creates a throwaway ETS table with `:ets.new(:name, Algorithm.ets_opts())` in `setup`, so tests do not share state.
- Time-dependent behaviour is tested with real small scales (tens/hundreds of ms) and `Process.sleep`, or with the polling helper `Hammer.CleanTestHelpers.eventually/3` (import from `test/support`). Prefer `eventually` for anything asynchronous such as cleanup; a 7.1.0 changelog entry replaced timing-dependent tests with it for CI reliability.
- Concurrency is tested with `Task.async` fan-out (see `test/hammer/atomic/fix_window_test.exs`); CAS and insert races have regression tests, so add one when fixing a race.
- Cover new behaviour in both `test/hammer/ets/` and `test/hammer/atomic/` when the algorithm exists in both, and in `term_keys_test.exs` style when key handling changes.
- Example (from `test/hammer/ets/token_bucket_test.exs`):

```elixir
setup do
  table = :ets.new(:hammer_token_bucket_test, TokenBucket.ets_opts())
  {:ok, table: table}
end

test "returns {:allow, 9} tuple on first access", %{table: table} do
  assert {:allow, 9} = TokenBucket.hit(table, "key", 10, 10, 1)
end
```

- Coverage threshold is 90% (`mix test --cover` fails below it).

## Elixir Guidelines

- Pattern match and use `with`; avoid nested `case`. Use `@impl true` on callbacks (`init/1`, `handle_info/2`).
- Never call `String.to_atom/1` on keys or any user input; keys are arbitrary terms and must stay terms.
- The library has zero runtime dependencies; do not add one. HTTP clients, Jason, telemetry and similar do not belong here (external backends carry their own deps). Dev-only tooling goes under `only:` as in `mix.exs`.
- Because the library supports Elixir 1.17+ (nominally 1.14), avoid newer-only syntax and stdlib functions unless CI's oldest matrix entry compiles them.
- ETS tables are `:public`, `:named_table`, named after the user's module. Cleanup must stay in the owning GenServer; do not let `hit` paths create tables.
- Let the GenServer crash on unexpected state; only `before_clean` callbacks are wrapped in rescue/catch, because user code runs there.
- Avoid `Process.sleep` in new tests where `eventually/3` or a deterministic assertion works.
- Macros: `__before_compile__` runs at the user's compile time. Keep generated code minimal, and make errors `ArgumentError` with an example, as existing code does.

## Workflow for Agents

1. Read the algorithm module and its two tests (ETS and Atomic) plus the relevant backend macro (`lib/hammer/ets.ex` or `lib/hammer/atomic.ex`).
2. Write or adjust the failing test first, in both backends if applicable.
3. Implement. If you change a callback signature, option, return shape, or `ets_opts/0` contract, check `/Users/manu/Projects/hammer-backend-redis` and `/Users/manu/Projects/hammer-backend-mnesia` for impact and mention it in the CHANGELOG.
4. Run the quality gate from "Essential Commands".
5. Update `CHANGELOG.md` (user-visible changes) and the moduledoc/guides if behaviour or options changed.
6. Commit with Conventional Commit style, as in history: `fix(ets): ...`, `feat: ...`, `chore: Release 7.5.0`, `ci: ...`, `build(deps): ...`. PRs are squash-merged with the number suffix (`(#202)`). Work on a branch, not `master`.

Release (maintainers): bump `@version` in `mix.exs`, add a `## X.Y.Z - YYYY-MM-DD` section to the top of `CHANGELOG.md` with PR numbers, commit as `chore: Release X.Y.Z (#NNN)`, merge, then push a git tag. Any tag triggers `publish.yml` (`hipcall/github_action_publish_hex`, secret `HEX_API_KEY`). `RELEASE.md` is a short, partly stale checklist. Docs use `source_ref: "v#{@version}"`, so the tag must be `vX.Y.Z`.

## Constraints - Never Do

- Do not bypass the quality gate or use `--no-verify`. Do not hand-edit `mix.lock`.
- Do not add runtime dependencies or a global application config; Hammer deliberately has none (limits are given per call).
- Do not put GenServer calls or table creation on the `hit` path.
- Do not change a public callback signature or `{:allow, n} | {:deny, ms}` return shape without a major-version decision and a sibling-backend check.
- Do not wire `:sliding_window` into the Atomic backend by only adding a module name; no such module exists (see Gotchas).
- Do not commit `IO.inspect`, `dbg`, `IEx.pry`, secrets, `erl_crash.dump`, or generated `cover/`, `doc/`, `_build/`, `deps/` (all gitignored).
- Do not tag or publish to Hex unless explicitly asked.
- Do not edit the sibling backend repos from here.

## Gotchas

- **Atomic `:sliding_window`**: `Hammer.Atomic.__before_compile__` has a `:sliding_window` clause pointing to `Hammer.Atomic.SlidingWindow`, but `lib/hammer/atomic/` has no such file. `Code.ensure_loaded!/1` will raise at compile time of the user's module. Docs list only four Atomic algorithms. Sliding window is ETS-only (and Redis).
- **`:ets` / `:atomic` as `:algorithm` value** are accepted as aliases for `:fix_window` in the macros; they are not meaningful names.
- **`hit/3,4` arg meaning varies**: for `:token_bucket`/`:leaky_bucket` the second and third args are refill/leak rate and capacity, not scale and limit. Docs for each algorithm explain this.
- **Token bucket deny value**: since 7.5.0 `{:deny, ms}` is the real time until enough tokens exist (can be small, e.g. 19). Callers should round up and floor at 1 s for `retry-after` headers.
- **Default `key_older_than`** is 24 h in both `start_link` implementations; the `Hammer.ETS` moduledoc claims 1 hour. Trust the code.
- **`mix.exs` says `elixir: "~> 1.14"`** but 7.2.0 dropped 1.14 and CI tests 1.17+. Older versions are unsupported in practice.
- **`dialyzer: [plt_add_apps: [:mix]]`** exists because the installer task references Mix; dialyzer is not run in CI.
- **Distributed use**: ETS/Atomic are node-local. For cluster-wide limits use the Redis backend or see `guides/distributed-ets.md`.
- `bench/base.exs` has a TODO about cleaning ETS between scenarios; benchmark numbers in `BENCHMARKS.md` were taken on a local M1 Max.
- Sub-token and window-boundary behaviour is subtle (fixed windows allow a 2x burst at the boundary by design); read the algorithm moduledoc before "fixing" it.

## Key Files

- `lib/hammer.ex` - behaviour definition, types, `use Hammer` macro
- `lib/hammer/ets.ex` - ETS backend macro, GenServer, option handling, `:clean` loop
- `lib/hammer/atomic.ex` - Atomic backend macro and GenServer
- `lib/hammer/clean_utils.ex` - `before_clean` invocation and deletion helpers
- `lib/hammer/ets/token_bucket.ex` - most intricate ETS algorithm (refill remainder, deny timing)
- `lib/hammer/atomic/token_bucket.ex` - CAS-packed atomics implementation
- `lib/hammer/ets/fix_window.ex` - reference implementation of the algorithm module shape
- `lib/mix/tasks/hammer.install.ex` - Igniter installer
- `test/support/clean_test_helpers.ex` - `eventually/3` and MFA callback handler
- `test/hammer/ets/clean_test.exs` - cleanup and `before_clean` semantics
- `CHANGELOG.md` - release notes; read the top entries for current behaviour
- `guides/Tutorial.md` - end-user integration guide (plug example, key design)
- `mix.exs` - version, deps, docs/package config, coverage threshold
- `.github/workflows/ci.yml` - the authoritative quality gate
