# Contributing to Sanctum

Currently playing it fast and loose with dependencies, tools and process. I'll document here whatever tools that I install for
doing development work on Sanctum. Currently, Sanctum is only being designed to run on Linux hosts. I only know that Sanctum
works on my Debian machine (the only current official target). I expect that it should would work on Windows with WSL; however,
you may see build or runtime issues on Apple devices, or other Linux distributions; my apologies in advance.

## Known issues for initial checkouts

* `just build` does not work until after `zig build` has been run, since the output directory and files do not exist for a clean checkout.

## Dependencies and Tools

Developers working on Sanctum will probably need to install these tools in order to run the normal development and testing workflow.

- The [Zig][ZIGLANG] compiler and toolset.
    - It is recommended that you use [Zig Version Manager (zvm)][ZVM] to install and update zig.
    - Sanctum is developed on builds of zig from the `master` branch.

[ZIGLANG]: https://github.com/ziglang/zig
[ZVM]: https://github.com/tristanisham/zvm

- The [GNU Project Debugger (gdb)][GDB]
    - Works for debugging 

[GDB]: https://www.sourceware.org/gdb/download/

- The [just][JUST] command runner.
    - Used for common build/test/debug commands.

[JUST]: https://github.com/casey/just

- A recent (> 3.9) release of [Python][PYTHON].
    - Currently used for running test suite.
    - I haven't tested with anything except 3.11.2
    - Currently no package dependencies. If some are added later, they will be added to [requirements.txt][PYTHON-REQ].

[PYTHON]: https://www.python.org/downloads/
[PYTHON-REQ]: ./docunomicon/requirements.txt
