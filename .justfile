set shell := ["/bin/bash", "-uc"]

abs := "readlink -f $1"
regression_tester := shell(abs, "./src/tests/regression.py")
regression_suite := shell(abs, "./src/tests/regression-tests/")

sanctum := shell(abs, "./zig-out/bin/sanctum")

test: build (_test regression_tester sanctum regression_suite)
_test script executable suite:
    @python3 {{script}} {{executable}} {{suite}}

build:
    zig build
