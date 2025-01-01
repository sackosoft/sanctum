import difflib
import os
import subprocess
import textwrap

from pathlib import Path
from sys import argv

if __name__ == "__main__":
    if len(argv) != 3:
        file_name = Path(__file__).name
        print(f"Invalid arguments. Expected usage: `python {file_name} <path_to_executable_to_test> <path_to_test_suite_directory>`")
        exit(1)

    exe = argv[1]
    if not os.access(exe, os.X_OK):
        print(f"Unable to run program, '{argv[1]}' is not executable.")
        exit(1)

    suite = Path(argv[2])
    if not suite.is_dir():
        print(f"Invalid test suite: '{argv[2]}', expected a path to a directory.")
        exit(1)

    for p in suite.glob("*.assert"):
        expected = p.read_text()
        spell = p.with_suffix(".spell.lua")
        command = [exe, "cast", str(spell.resolve())]

        result = subprocess.run(command, capture_output=True)
        if result.returncode != 0:
            print(f"FAIL: Exited with non-zero exit code {result.returncode}")
            print("stdout:")
            print(textwrap.indent(result.stdout.decode("utf-8"), '  '))
            print("stderr:")
            print(textwrap.indent(result.stderr.decode("utf-8"), '  '))
            exit(1)

        try:
            actual = result.stderr.decode("utf-8")
        except UnicodeDecodeError:
            actual = str(result.stderr)
            print("FAIL: Unable to decode test run output")
            print("stderr:")
            print(actual)
            exit(1)

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

    print("PASS")
    exit(0)
