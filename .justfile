set shell := ["/bin/bash", "-uc"]

root := justfile_directory()
regression_tester := root / "src/tests/regression.py"
regression_suite := root / "src/tests/test-suite"
sample_spell := root / "src/tests/test-suite/decrement-counter/spell.lua"
sample_event := root / "src/tests/test-suite/decrement-counter/seed.lua"
sanctum := root / "zig-out/bin/sanctum"
debug := root / "tools/debug.sh"

test: build
    python3 {{regression_tester}} {{sanctum}} {{regression_suite}} --test

freeze: build
    python3 {{regression_tester}} {{sanctum}} {{regression_suite}} --freeze

run: build
    {{sanctum}} cast {{sample_spell}} --seed {{sample_event}}

debug: build
    {{debug}} {{sanctum}} cast {{sample_spell}} --seed {{sample_event}} --dump-events

build:
    zig build
