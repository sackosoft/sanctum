set shell := ["/bin/bash", "-uc"]

abs := "readlink -f $1"
regression_tester := shell(abs, "./src/tests/regression.py")
regression_suite := shell(abs, "./src/tests/test-suite/")

sample_spell := shell(abs, "./src/tests/test-suite/decrement-counter/spell.lua")
sample_event := shell(abs, "./src/tests/test-suite/decrement-counter/seed.lua")

sanctum := shell(abs, "./zig-out/bin/sanctum")

test: build (_test regression_tester sanctum regression_suite "--test")
freeze: build (_test regression_tester sanctum regression_suite "--freeze")
_test script executable suite flags:
    @python3 {{script}} {{executable}} {{suite}} {{flags}}

run: build (_run sanctum sample_spell sample_event)
_run executable spell event:
    @{{executable}} cast {{sample_spell}} --seed {{sample_event}} --dump-events

build:
    zig build
