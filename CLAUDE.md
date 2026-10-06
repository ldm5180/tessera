# tessera

Narrow Parquet reading for Ada 2022: the subset of Apache Parquet that
pyarrow writes for flat tables, and nothing else, with a SPARK-proven
core.  Anything outside the subset is refused by name, never misread.
No C dependency, no floating-point type: `FLOAT` and `DOUBLE` columns
are handed over as their 32- and 64-bit patterns.  The plan, with the
wire rules of the subset, is `docs/tessera-plan.md`.

## Commands

- `make build`    — build the library (`alr build`)
- `make test`     — AUnit suite in BOTH modes (release -O3, debug -O0), offline
- `make features` — the Gherkin features under `tests/features/` in both
  modes, on fabula, printing the report as it goes (in colour on a
  terminal); checks the summary line, since fabula exits 0 for a
  missing path.  `alr test` runs them too
- `make features-report` — the living documentation: the features with
  `--report-json`, rendered by multiple-cucumber-html-reporter
  (`tools/features-report`, node) into `obj/features-report/html`
- `make prove`    — SPARK proof, level 2, `--checks-as-errors=on`; must
  exit 0.  Stopped after 30 minutes if it wedges
- `make format`   — `gnatformat --check` over all committed Ada sources
- `make validation` — `alr build --validation`: warnings and style as
  errors (79 columns, `and then` in contracts)
- `make no-float` — fails on any floating-point type named in a source
- `make ci`       — every gate above, cheapest first
- `python tools/make_fixtures.py` — rewrite `tests/data/` (pyarrow,
  seeded; versions in `tools/requirements.txt`).  CI never runs Python;
  the fixtures are committed

## Layout

- `src/core/` — the SPARK core: every unit carries `SPARK_Mode`, does
  zero IO, and may `with` only other core units and `Sml.*`.  Decoders
  that walk states (the Thrift struct reader, the Snappy element reader,
  a chunk's page sequence) are sml machines whose actions write a
  request the driver executes; the inner loops are plain loops with
  contracts.
- `src/app/`  — `Tessera.Files`, the one unit that touches the disk.
- `tests/` — AUnit suite (`test_tessera.gpr`, driver `test_runner.adb`)
  and the features: `tests/features/*.feature` run by
  `tessera_features.ads` (Fabula.Main over `Tessera_Steps`).  The steps
  are sml machines run by `Tessera_Steps.Flows`, one region per feature
  vocabulary, each offered every step; a step none takes fails, naming
  every region's state.  Fixtures are `tests/data/*.parquet`, each with
  a `.expected.csv` beside it.
- `proof/` — gnatprove harness (`proof.gpr`; sources `../src/core` and
  the sml pin directly and withs nothing).
- `docs/tdd-log.md` — git-ignored TDD audit log.

## Reading contracts (do not break)

- Never trust a length, a count or an offset from the file: each is
  checked against the buffer it indexes before use.  The proofs depend
  on it.
- Never raise from the library: every failure is an `Outcome` naming a
  `Refusal`, the column and the offending value where there is one.
- Never read a whole file: the footer, then the column chunks asked for.
- Never start a task inside the library: decoding a chunk is a pure
  function of its bytes; the consumer runs chunks in parallel.
- Never commit a real data file.

## SPARK

- Every `src/core` unit carries `SPARK_Mode`. After any core change,
  `make prove` must exit 0. No `pragma Assume`.
- Prefer results over exceptions; bound inputs by subtypes; state
  contracts (`Pre`, `Post`, loop invariants).

## TDD protocol (strict)

- Red/green/refactor every cycle: failing test first (RED = compile
  error or failed assertion), the minimal code (GREEN), then a refactor
  pass looking outward from the diff -- duplication, names, shape,
  stale comments.  "Nothing to refactor" is stated with its reason.
- Log every cycle in `docs/tdd-log.md` (git-ignored, newest on top):
  date, change, exact RED output, GREEN pass counts, refactor result.
- One `<unit>_tests.ads/.adb` pair per library unit under `tests/src/`,
  registered in `tessera_suite.adb`.
- Tests are layers.  A unit test holds the mechanism (bytes, counts,
  branches) and covers its function completely.  A feature states what
  a caller sees, in a reader's words.  Feature steps are sml machines:
  real states, every condition a guard, a guarded row followed by an
  unguarded fallback row whose action fails the step with the reason.

## Shape

Subprograms at most 40 statement lines and 60 in all, nesting at most
3, no nested subprogram bodies (expression functions of at most 3
lines excepted), at most 5 parameters and 2 `out` parameters (more is a
record), no adjacent `Boolean` parameters, body files at most 1,000
lines, no bare numeric literal of 100 or more outside a named constant.
Comments: the first sentence says what; at most 8 lines on a
declaration.  Event literals take an `E_` prefix.

## Commit style

- gitmoji `:code:` shortcode prefix + capitalized, imperative subject, no
  trailing period; the body says why.
- Never put test / prove / format result counts in commit messages.
