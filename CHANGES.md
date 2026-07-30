# v1.6.0 (2026-07-28)

## Summary

Adds **lazy variable evaluation**: events can mark a variable as `unfetched`,
and the search yields a continuation instead of forcing the caller to
materialize every variable up front. The caller resolves only the variables
actually needed to decide the outcome, then resumes. Built on top of the
be-tree submodule's flat-tree/tri-state search (bumped to `v1.6.0`).

---

## New Erlang API Functions

| Function | Description |
|----------|-------------|
| `betree_prepare_flat/1` | Flattens the tree (must be called once, after all subs are inserted, before `betree_search_lazy/2,3`) |
| `betree_search_lazy/2,3` | Search an event that may contain `unfetched` variables; returns `{ok, MatchedIds}` or `{continue, Continuation, PartialMatchedIds}`. The `/3` form also returns elapsed time, like `betree_search_stats_t`/`betree_search_t` |
| `betree_search_continue/3,4` | Resume a `Continuation` with `[{VarIdx, Value \| undefined}]` updates; returns `{ok, MatchedIds}` or another `{continue, ...}`. The `/4` form also returns elapsed time |

Both `betree_search_lazy` and `betree_search_continue` accept either a
`Betree` reference or a stats accumulator (as returned by
`betree_stats_start/1`) as their first argument, matching the existing
`betree_search_stats` convention. The two calls do **not** need to share the
same accumulator — stats context is supplied independently at each resume,
while the continuation itself carries only a reference to the originating
betree (verified against the caller's betree/accumulator on `continue`, to
reject use across different trees).

Marking an event variable `unfetched` (e.g. `{ev, 1, unfetched, 3}`) tells the
search not to evaluate anything that depends on it until a real value (or
`undefined`) is supplied via `betree_search_continue`. Thanks to tri-state
short-circuit in the underlying flat search, many subs resolve without ever
needing the unfetched variable (e.g. `false and unknown`), so `continue` is
only required when at least one sub's outcome is genuinely undecided.

---

## NIF Layer (c_src/betree.c)

- **Flat/lazy search functions**: `nif_betree_prepare_flat`,
  `nif_betree_search_lazy`, `nif_betree_search_continue`, and timed `_t`
  wrappers, backed by the be-tree submodule's `betree_flatten` /
  `betree_search_flat` / `BETREE_UNFETCHED` API.
- **`MEM_CONTINUATION` resource type**: holds the originating
  `betree_resource`, the in-progress `betree_event`, and the opaque
  `flat_search_state` between yields. Continuation creation is deferred until
  a yield actually occurs, avoiding an allocation on the non-yielding path.
- **`parse_variable()`**: type-switch logic extracted out of
  `add_variables`/`add_variables_lazy` so it can be reused by
  `nif_betree_search_continue` when applying per-variable updates.
- **`betree_search_continue` update handling**: updates are only applied to
  event slots still holding `BETREE_UNFETCHED` — updates for variables that
  already have a real value, or that were never marked unfetched, are
  silently ignored rather than raising `badarg`. Supplying `undefined`
  clears the slot to `NULL` (not-set) rather than leaving the sentinel in
  place, so the flat search does not yield on it again.
- **Simplified yield/continue accounting**: removed
  `make_needed_vars_list`, `save_partial_subs`, `make_final_result`, and the
  `partial_subs`/`partial_count`/`partial_capacity` fields on
  `continuation_resource`. Each `betree_search_lazy`/`betree_search_continue`
  call now returns only the matches found in that call; the Erlang caller is
  responsible for accumulating matches across yields (see the updated
  `betree_lazy_tests.erl` for the pattern).

---

## Build

- **macOS linker**: replaced the deprecated `-flat_namespace -undefined
  suppress` with `-undefined dynamic_lookup`.
- **`libbetree.a` as a Makefile dependency**: the NIF `.so` is now relinked
  automatically whenever `libbetree.a` changes, instead of requiring a clean
  rebuild.
- **`betree_prepare_subs`/`betree_prepare_flat` made idempotent**: calling
  both (or either twice) no longer double-allocates the per-cdir subs-data
  arrays.

---

## Tests

- `betree_lazy_tests.erl`: new suite covering `betree_prepare_flat`,
  single- and multi-yield lazy search, resuming with real values and with
  `undefined`, `allow_undefined` vs `disallow_undefined` semantics for a
  variable resolved to `undefined`, ignoring updates for non-unfetched
  variables, mismatched-betree and mismatched-stats-accumulator `continue`
  calls, and using separate stats accumulators for the lazy and continue
  phases of the same search.

---

## Dependencies

- **be-tree submodule bumped to `v1.6.0`**, which adds flat tree
  serialization and continuation-based search, tri-state expression
  evaluation (`match_node_tri`/`match_sub_tri`, `MATCH_UNKNOWN`), and the
  `BETREE_PRED_UNFETCHED` sentinel-pointer representation for unfetched
  variables (see be-tree's own `CHANGES.md` for details).

---

# v1.5.1 (2026-07-10)

## Removed

Dropped several code paths that have no callers in any downstream consumer,
to shrink the NIF surface area ahead of further optimization work:

- **`TRACE_LAST_VAR` instrumentation** — the `#ifdef TRACE_LAST_VAR` debug
  blocks in the NIF C layer (see the "Conditional tracing" note under
  v1.5.0 below; the underlying be-tree submodule also drops this).
- **`*_err` error-reason API** — `betree_make_err/1`, `betree_make_event_err/2,3`,
  `betree_make_sub_err/4`, `betree_insert_sub_err/2`, `betree_search_err/2,3`,
  `betree_search_ids_err/3,4`, `betree_parse_reasons/1`, `betree_write_dot_err/2`,
  and the dedicated `betree_search_reason_tests.erl` suite.
- **Yield-variant search API** — `betree_search_yield/2,3`, `search_yield_count/2,5`,
  `search_yield/3,4`, `search_next_yield/3`, `betree_search_ids_yield/3,4`,
  `search_ids_yield/5`, and `betree_yield_tests.erl`.
- **`search_iterator` API** — `search_iterator/2`, `search_next/1`, `search_all/1`,
  `search_iterator_release/1`, and `betree_iterator_test.erl`. This was the
  Erlang-scheduler-cooperation mechanism described in
  `Erlang_Scheduler_friendly_processing_with_BE_Tree.md` (now removed along
  with the feature); the counting-based reduction bookkeeping it relied on
  is removed from the be-tree submodule as well.
- **`*_ids` subset-search API** — `betree_search_ids/3,4` and the NIF
  functions backing them, plus the corresponding ids-specific test cases in
  `betree_search_tests.erl`. This path restricted matching to a
  caller-supplied subset of subscription IDs; the underlying be-tree
  submodule also drops its ids-search implementation.
- **be-tree submodule bumped to `v1.5.2`**, which drops the corresponding
  `TRACE_LAST_VAR`, `_counting`, `*_err`, and `*_ids` code paths on the C
  side (see be-tree's own `CHANGES.md` for details).

---

# v1.5.0 (2026-06-26)

## Summary

This branch extends the erl-be-tree NIF with domain ranking, per-subscription
and per-group no-match statistics tracking, a debug search mode that reports
per-subscription pass/fail reasons, and a session-based group statistics accumulator.
Build infrastructure is modernized by replacing the ad-hoc clone script with a git
submodule and a top-level Makefile.

---

## Build System

- **Git submodule**: `be-tree` is now a git submodule (pinned at `v1.5.1` from
  `github.com/x0id/be-tree`) instead of being cloned at build time by
  `c_src/build_betree`. The old clone script and `rebar3` binary are removed.
- **Makefile**: New top-level `Makefile` wraps `rebar3 compile/eunit/clean` with
  automatic `git submodule update --init --recursive`.
- **rebar.config**: Pre/post hooks updated to `make -C be-tree NIF=true` and
  `make -C be-tree clean`.

---

## New Erlang API Functions

| Function | Description |
|----------|-------------|
| `betree_make/2` | Create betree with domain ranking map |
| `betree_add_sub/4` | Add subscription (make + insert in one call) |
| `betree_add_sub/5` | Add subscription with group ID |
| `betree_prepare_subs/1` | Allocate internal stats arrays after all subs are inserted |
| `betree_search_debug/2,3` | Search returning per-sub pass/fail with failure-reason atoms |
| `betree_search_stats/2,3` | Search accumulating no-match statistics |
| `betree_stats/1,2` | Retrieve per-subscription stats map (optional atomic reset) |
| `betree_group_stats/1,2` | Retrieve per-group stats map (optional atomic reset) |
| `betree_stats_start/1` | Start a group stats accumulator session |
| `betree_stats_stop/1` | Stop session, transfer counts to global group stats |
| `betree_stats_stop_return/1` | Stop session, return `#{Var => [GroupId]}` map |
| `betree_group_vars/1` | Return `#{GroupId => [VarAtom]}` — variables used by each group |
| `betree_print/1` | Print betree structure to stderr (debug/IO-bound) |

---

## NIF Layer (c_src/betree.c)

### Resource model refactoring

- The NIF resource is now `struct betree_resource` wrapping the raw `struct betree*`
  plus subscription index, group mappings, and statistics counters.
- New `MEM_SEARCH_STATS` resource type for the session-based stats accumulator.
- `cleanup_betree` updated to free all associated arrays and the separately-allocated
  `struct betree`.

### Domain ranking

- `betree_make/2` accepts an optional `#{AtomName => Rank}` map.
- `add_domains()` calls `betree_add_ranked_*_variable()` variants passing
  per-variable rank values.
- After adding domains, `attr_var.data` is set to the corresponding Erlang atom for
  efficient variable-name lookup during callbacks.

### Subscription indexing and groups

- `struct sub_info` stores `sub_id`, `group_idx`, and a direct pointer to
  `betree_sub`.
- `index_sub()` dynamically grows the subscription index and assigns the sub a slot.
- `find_or_add_global_group()` maintains a deduplicated group ID array in the
  betree resource.
- `betree_prepare_subs()` allocates `subs_data`, `sub_stats`, and `group_stats`
  arrays.

### Search variants

- **`betree_search_debug`**: Uses `acc_ret`/`acc_arr` callbacks that populate
  thread-local `subs[]` and `rets[]` arrays. Returns `{ok, [SubId], [Reason]}`
  where reason is `ok` for pass or the failing variable atom.
- **`betree_search_stats`**: Uses `update_stats`/`bulk_update_stats` callbacks that
  atomically increment per-sub failure counters and collect matches.
- **`betree_search_stats` with accumulator**: When called with a `stats_resource`,
  uses `update_group_stats`/`bulk_update_group_stats` callbacks. Records the
  *first* failing variable per group per search (value 0 = no decision, 1 = passed,
  var_idx+2 = first failure reason).

### Statistics retrieval

- `build_stats_map()`: Returns `#{SubId => #{VarAtom => Count}}`, optionally
  resetting counters atomically.
- `build_group_stats_map()`: Returns `#{GroupId => #{VarAtom => Count}}`.
- `build_accumulator_stats_map()`: Returns `#{VarAtom => [GroupId]}` — groups
  grouped by their first failing variable.

### Group variable introspection

- `nif_betree_group_vars()`: Walks all subs, ORs their `attr_vars` bitmasks per
  group, then returns `#{GroupId => [VarAtom]}`.

### Thread-local storage

- `subs`, `rets`, `allocated_size`, `subs_count` are `__thread`-local dynamic
  arrays shared across debug/stats search variants, avoiding per-call allocation.

### NIF variant selection

- Two `ErlNifFunc` tables: `nif_functions` (normal) and `nif_functions_` (dirty
  schedulers for search). Selected at load time via `DIRTY_SEARCH` environment
  variable using a custom `ERL_NIF_INIT_` macro.

### Robustness

- All `enif_alloc`/`enif_alloc_resource` calls now check for NULL and return
  `{error, mem_alloc_failed}`.
- `match_be_tree()` call signature updated to pass `config` and an optional
  report pointer.

---

## Conditional tracing (`TRACE_LAST_VAR`)

When compiled with `-DTRACE_LAST_VAR`, the group stats callbacks emit
`fprintf(stderr, ...)` traces for a hardcoded flight ID (`TRACE_FLIGHT_ID`),
showing per-callback pass/fail decisions. This is a debug aid, not enabled in
normal builds.
