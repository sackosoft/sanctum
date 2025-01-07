import difflib
import os
import subprocess
import textwrap

from pathlib import Path
from sys import argv
from typing import Optional

FAILED = 1
PASSED = 0

class TestFiles:
    EVENT_SEED = "seed.lua"
    SPELL = "spell.lua"
    EXPECTED_STDOUT = "stdout.assert"
    EXPECTED_STDERR = "stderr.assert"
    EXPECTED_EXIT_CODE = "exitcode.assert"

def try_decode_utf8(std_x: bytes) -> str:
    try:
        return std_x.decode("utf-8")
    except UnicodeDecodeError:
        print("FAIL: Unable to decode test run output:")
        print(str(std_x))
        exit(1)

def assert_results_mach_expected(expected: str, actual_bytes: bytes) -> int:
    actual = try_decode_utf8(actual_bytes)

    diff = [l for l in difflib.unified_diff(expected, actual)]
    if len(diff) != 0:
        print("FAIL: Output does not match expected")
        # I'm not finding this output particularly useful.. removing it for now.
        # print("diff")
        # print("".join(diff))
        # print()
        print("Expected:")
        print(textwrap.indent(expected, ' > | '))
        print("Actual:")
        print(textwrap.indent(actual, ' ? | '))
        print()
        return FAILED
    else:
        return PASSED

def try_run_process(command: list, expected_exit_code: Optional[int]):
    expected_exit_code = expected_exit_code if expected_exit_code != None else 0
    result = subprocess.run(command, capture_output=True)
    if result.returncode != expected_exit_code:
        print(f"FAIL: Exited with non-zero exit code {result.returncode}")
        print("stdout:")
        print(textwrap.indent(result.stdout.decode("utf-8"), '  '))
        print("stderr:")
        print(textwrap.indent(result.stderr.decode("utf-8"), '  '))
        return (FAILED, result)
    else:
        return (PASSED, result)

def _assert_outputs(test_dir_path, result):
    """
    Attempts to load the `stdout.assert` and `stderr.assert` files for the given test case,
    and compares them against the actual output from the program. If the expected output
    does not match the actual output, the program is halted with an error: a test case failed.
    """
    outcome = 0
    assertion_files = [
        (TestFiles.EXPECTED_STDOUT, result.stdout),
        (TestFiles.EXPECTED_STDERR, result.stderr),
    ]
    for (assert_file_name, actual_bytes) in assertion_files:
        assert_file = t / assert_file_name
        if assert_file.is_file():
            expected = assert_file.read_text()
            if PASSED != assert_results_mach_expected(expected, actual_bytes):
                outcome = FAILED
    return outcome

def _freeze_outputs(test_dir_path, result):
    """
    As breaking changes and refactorings are introduced to sanctum, it's common to find that
    the new actual output does not match the saved expected output files. In such a case, after
    verifying that the new output is correct, we can "freeze" those actual outputs to the expected
    output files. This sets the current output from Sanctum as the "golden output" for future tests.
    """
    assertion_files = [
        (TestFiles.EXPECTED_STDOUT, result.stdout),
        (TestFiles.EXPECTED_STDERR, result.stderr),
    ]
    for (assert_file_name, actual_bytes) in assertion_files:
        actual = try_decode_utf8(actual_bytes)
        assert_file = t / assert_file_name
        assert_file.write_text(actual)
    return PASSED

# A mapping from the command line 'action' argument to information about how to run the action.
# The action tuple contains a function to execute with the output from running the executable as a subprocess;
# as well as a boolean indicating whether the action should be run on failure (True) or if the action
# should be skipped when the subprocess fails with a non-zero exit code (False)
TEST_ACTIONS = {
    "--test": (_assert_outputs, False),
    "--freeze": (_freeze_outputs, True),
}

if __name__ == "__main__":
    if len(argv) != 4:
        file_name = Path(__file__).name
        print(f"Invalid number of arguments.\n    Usage: `python {file_name} <path_to_executable_to_test> <path_to_test_suite_directory> [--test|--freeze]`")
        exit(1)

    [_, exe, test_suite_dir, action_arg] = argv
    if not os.access(exe, os.X_OK):
        print(f"Unable to run program, '{argv[1]}' is not executable.")
        exit(1)

    test_suite_dir = Path(test_suite_dir)
    if not test_suite_dir.is_dir():
        print(f"Invalid test suite: '{argv[2]}', expected a path to a directory.")
        exit(1)

    attempts = 0
    failures = 0

    tests = [Path(directory[0]) for directory in os.walk(str(test_suite_dir.resolve())) if TestFiles.SPELL in directory[2]]
    for t in tests:
        attempts += 1
        print(f"Running '{action_arg.replace('-', '')}' on test case '{t}'")
        event_seed = t / TestFiles.EVENT_SEED
        spell = t / TestFiles.SPELL
        exit_code = t / TestFiles.EXPECTED_EXIT_CODE
        expected_exit_code = int(exit_code.read_text().strip()) if exit_code.is_file() else None
        command = [exe, "cast", str(spell.resolve()), "--seed", str(event_seed.resolve())]

        (after_run_action, run_on_failure) = TEST_ACTIONS[action_arg]
        (run_outcome, result) = try_run_process(command, expected_exit_code)

        if run_outcome == PASSED or run_on_failure:
            failures += after_run_action(t, result)
        else:
            failures += FAILED

    if failures == 0:
        print("PASS")
        exit(0)
    else:
        print(f"FAILED {failures} / {attempts} tests")
        exit(1)
