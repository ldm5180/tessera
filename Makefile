# Thin wrapper around Alire + gprbuild so the common flows are one word.  Every
# target runs through `alr` (so the sml/aunit/fabula dependencies resolve).
# The tests build in two profiles selected with -XMODE (sml-ada convention):
# release (-O3) and debug (-O0).

TESTS := -P tests/test_tessera.gpr

# The Ada sources every source gate reads: the library, its tests, its
# proof harness and the benchmark.
SOURCES = $$(git ls-files 'src/*/*.ad[sb]' 'tests/src/*.ad[sb]' \
                         'proof/src/*.ad[sb]' 'bench/src/*.ad[sb]')

BENCH := -P bench/bench.gpr

.PHONY: all build test features features-report prove format validation \
        no-float bench bench-build ci clean help

all: build

## build       Build the library
build:
	alr build

## test        Build and run the AUnit suite in both modes (per-test output)
test:
	alr exec -- gprbuild -p -j0 -XMODE=debug $(TESTS)
	alr exec -- tests/bin/debug/test_runner
	alr exec -- gprbuild -p -j0 -XMODE=release $(TESTS)
	alr exec -- tests/bin/release/test_runner

## features    Build and run the Gherkin features in both modes, printing
##             the runner's report as it goes -- in colour when make writes
##             to a terminal: fabula colours only a terminal, so the runner
##             then runs under script(1) for a pseudo-terminal while tee
##             keeps a copy.  fabula exits 0 for a missing path or an empty
##             file, so the summary line, not the exit status alone, is
##             what says every scenario passed
features:
	alr exec -- gprbuild -p -j0 -XMODE=debug $(TESTS)
	alr exec -- gprbuild -p -j0 -XMODE=release $(TESTS)
	@log=$$(mktemp) && rc=$$(mktemp) && trap 'rm -f $$log $$rc' EXIT && \
	if [ -t 1 ]; then tty=yes; else tty=; fi; \
	for mode in debug release; do \
	  echo "== features ($$mode)"; \
	  run="alr exec -- tests/bin/$$mode/tessera_features tests/features"; \
	  { if [ -n "$$tty" ]; then script -qefc "$$run" /dev/null; \
	    else $$run; fi; echo $$? > $$rc; } | tee $$log; \
	  [ "$$(cat $$rc)" = 0 ] || \
	    { echo "features: $$mode: the runner failed"; exit 1; }; \
	  sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r$$//' $$log | \
	    grep -qE '^[1-9][0-9]* Scenarios? \([0-9]+ passed\)$$' || \
	    { echo "features: $$mode: a scenario did not pass"; exit 1; }; \
	done; echo 'features: every scenario passed in both modes'

## features-report  The living documentation: run the features (release)
##             with --report-json and render it into
##             obj/features-report/html with multiple-cucumber-html-reporter
##             (tools/features-report).  The page is made even when a
##             scenario fails -- that is when it is most worth reading --
##             and the target then fails with the runner.
features-report:
	alr exec -- gprbuild -p -j0 -XMODE=release $(TESTS)
	@rm -rf obj/features-report && mkdir -p obj/features-report/json
	@alr exec -- tests/bin/release/tessera_features tests/features \
	   --report-json obj/features-report/json/features.json; rc=$$?; \
	 npm ci --prefix tools/features-report --no-audit --no-fund && \
	 node tools/features-report/report.js obj/features-report/json \
	   obj/features-report/html && exit $$rc

## prove       Run the SPARK proof (same flags as CI); a wedged run stops
##             after 30 minutes
#  phase1_guard.py first drops gnatprove's phase-1 ALIs when a
#  `gnatprove -u` left two of them disagreeing on a source's checksum:
#  from there gnatprove's own gprbuild re-reads an ALI its compiler is
#  rewriting and spins until killed.  Its selftest runs first.  The
#  lock holds the guard and gnatprove together, because two gnatprove
#  runs on one tree corrupt each other's output.
PROVE_OBJ := proof/obj
prove: build
	python3 tools/phase1_guard.py --selftest
	@mkdir -p $(PROVE_OBJ)
	flock $(PROVE_OBJ)/.prove.lock sh -c '\
	  python3 tools/phase1_guard.py --obj $(PROVE_OBJ) \
	    proof/src src/core alire/cache/pins && \
	  timeout 30m alr exec -- gnatprove -P proof/proof.gpr \
	    -j0 --level=2 --checks-as-errors=on --warnings=error'

## format      Check formatting (per project, explicit files; no warnings)
format:
	alr exec -- gnatformat -P tessera.gpr --charset utf-8 --check \
	  $$(git ls-files 'src/*/*.ad[sb]')
	alr exec -- gnatformat -P tests/test_tessera.gpr --charset utf-8 --check \
	  $$(git ls-files 'tests/src/*.ad[sb]')
	alr exec -- gnatformat -P proof/proof.gpr --charset utf-8 --check \
	  $$(git ls-files 'proof/src/*.ad[sb]')
	alr exec -- gnatformat $(BENCH) --charset utf-8 --check \
	  $$(git ls-files 'bench/src/*.ad[sb]')

## validation  The warnings-and-style-as-errors build CI runs: 79 columns,
##             `and then` in contracts, every warning an error
validation:
	alr --non-interactive build --validation

## no-float    Fail on any floating-point type named in a source: tessera
##             hands FLOAT and DOUBLE over as bit patterns and never forms
##             a floating-point value
no-float:
	@if grep -nwE 'Float|Long_Float|Long_Long_Float|digits|Elementary_Functions' \
	    $(SOURCES) /dev/null; then \
	  echo 'no-float: a floating-point type is named above'; exit 1; \
	else echo 'no-float: no floating-point type in any source'; fi

## bench       Read named columns of a local file and print rows, megabytes
##             and seconds per column: make bench TESSERA_FILE=<path>
##             [TESSERA_COLUMNS="a b c"] (every column when none is named).
##             Real data stays outside the repository; CI only builds it
bench: bench-build
	@test -n "$(TESSERA_FILE)" || \
	  { echo 'bench: make bench TESSERA_FILE=<path> [TESSERA_COLUMNS=...]'; \
	    exit 2; }
	alr exec -- bench/bin/tessera_bench "$(TESSERA_FILE)" $(TESSERA_COLUMNS)

## bench-build Build the benchmark (release)
bench-build:
	alr exec -- gprbuild -p -j0 $(BENCH)

## ci          Every gate CI runs, cheapest first
ci: no-float format validation test features bench-build prove

## clean       Remove all build artifacts
clean:
	-alr exec -- gprclean -q $(BENCH)
	-alr exec -- gprclean -q -XMODE=release $(TESTS)
	-alr exec -- gprclean -q -XMODE=debug $(TESTS)
	alr clean

## help        List targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
