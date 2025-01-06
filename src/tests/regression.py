import difflib
import os
import subprocess
import textwrap

from pathlib import Path
from sys import argv

class TestFiles:
    EVENT_SEED = "seed.lua"
    SPELL = "spell.lua"
    STDOUT = "stdout.assert"
    STDERR = "stderr.assert"

def try_decode_utf8(std_x: bytes) -> str:
    try:
        return std_x.decode("utf-8")
    except UnicodeDecodeError:
        print("FAIL: Unable to decode test run output:")
        print(str(std_x))
        exit(1)

def assert_results_mach_expected(expected: str, actual_bytes: bytes):
    actual = try_decode_utf8(actual_bytes)

    diff = [l for l in difflib.unified_diff(expected, actual)]
    if len(diff) != 0:
        print("FAIL: Output does not match expected")
        print("diff")
        print("".join(diff))
        print()
        print("Expected:")
        print(textwrap.indent(expected, ' > | '))
        print("Actual:")
        print(textwrap.indent(actual, ' ? | '))
        print()
        exit(1)

def try_run_process(command: list):
    result = subprocess.run(command, capture_output=True)
    if result.returncode != 0:
        print(f"FAIL: Exited with non-zero exit code {result.returncode}")
        print("stdout:")
        print(textwrap.indent(result.stdout.decode("utf-8"), '  '))
        print("stderr:")
        print(textwrap.indent(result.stderr.decode("utf-8"), '  '))
        exit(1)
    return result

if __name__ == "__main__":
    if len(argv) != 3:
        file_name = Path(__file__).name
        print(f"Invalid arguments. Expected usage: `python {file_name} <path_to_executable_to_test> <path_to_test_suite_directory>`")
        exit(1)

    exe = argv[1]
    if not os.access(exe, os.X_OK):
        print(f"Unable to run program, '{argv[1]}' is not executable.")
        exit(1)

    test_suite_dir = Path(argv[2])
    if not test_suite_dir.is_dir():
        print(f"Invalid test suite: '{argv[2]}', expected a path to a directory.")
        exit(1)

    tests = [Path(directory[0]) for directory in os.walk(str(test_suite_dir.resolve())) if TestFiles.SPELL in directory[2]]
    for t in tests:
        print(f"Running regression test '{t}'")
        event_seed = t / TestFiles.EVENT_SEED
        spell = t / TestFiles.SPELL
        command = [exe, "cast", str(spell.resolve()), "--seed", str(event_seed.resolve())]

        result = try_run_process(command)

        assertion_files = [
            (TestFiles.STDOUT, result.stdout),
            (TestFiles.STDERR, result.stderr),
        ]
        for (assert_file_name, actual_bytes) in assertion_files:
            assert_file = t / assert_file_name
            if assert_file.is_file():
                expected = assert_file.read_text()
                assert_results_mach_expected(expected, actual_bytes)

    print("PASS")
    exit(0)

