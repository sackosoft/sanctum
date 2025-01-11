<div align="center">

# Sanctum
**Welcome, sorcerer, to the Sanctum. Write spells in Lua for transforming and acting on event streams of magical energy.**

![GitHub License](https://img.shields.io/github/license/sackosoft/sanctum)

<!--
TODO: Capture attention with a visualization, diagram, demo or other visual placeholder here.
![Placeholder]()
-->

</div>

## About

Sanctum is an event streaming, storage and processing platform. It lets you, the sorcerer, craft powerful spells in Lua to process
and transform streams of events. Sanctum handles the complexities of storage, state and routing these energies across the ethereal
planes, so that you can focus on writing the spells for your use case.

For more detailed reference information and documentation, refer to the [`docunomicon`](./docunomicon).

## Features

* ✨ **Spells**: User-defined Lua code for actions or transformations, invoked with events from the event stream.
* 🔓 **Flexible**: Write stateful or stateless spells, use the storage system provided by the runtime or bring your own backend.
* ⏩ **Fast**: Written in Zig so that you don't have to worry about performance.

## Installation

Options for installing and hosting Sanctum can be found in the [`docunomicon`](./docunomicon/install.md).

## Usage

Sanctum uses the [`just`][JUST] command runner. Refer to [`CONTRIBUTING.md`](./CONTRIBUTING.md) for more information about
dependencies. The commonly used commands are described below.

- `just test`
    - Runs Sanctum against the regression test suite, compares output against "golden output" files.

- `just freeze`
    - Runs Sanctum updating the regression test suite "golden output" files with current output.

- `just debug`
    - Runs Sanctum in [GDB - The GNU Project Debugger][GDB] using a regression test as input.

[JUST]: https://github.com/casey/just
[GDB]: https://www.sourceware.org/gdb/download/

<br>

## Roadmap

# Release Roadmap

## v0.1 Proof of Concept - **Active**

Demonstrates event processing with Spells on a throw-away runtime. Sanctum runs as a CLI application and
covered by a suite of regression tests to enable building and refactoring the core engine. Runs on a
single node (no networking, no persistence).

- [ ] Docunomicon - Definition and example of Lua spells
    - [x] Minimal documentation for spells in the runtime.
- [ ] Spell Casting
    - [x] Spells can be loaded dynamically into the sanctum from files.
        - [ ] Spells are loaded and unloaded with the prepare and unprepare lifecycle hooks.
    - [x] Counting loop spell is added with a reusable regression test.
        - [x] Many reusable regression tests can be defined.
        - [x] Regression tests are fully self-contained. Seed events, the initial event loop event,
              can be specified in Lua and loaded by the runtime.
    - [x] Malformed spells (spell parse failure) are handled gracefully.
        - [x] Handle parsing failing line number from errors Lua message.
    - [x] Unstable magic (internal spell failures) is handled gracefully.
    - [x] Add support to serialize and deserialize magical energies as MessagePack buffers.
    - [x] Spells can produce magical energy or act as a terminal action, producing nothing.
    - [ ] Spells can be bound to energy streams subscriptions.
        - [ ] Support for topic-based subscriptions
        - [ ] Support for filter-based subscriptions
    - [ ] Build a proof of concept sanctum application for demo/validation.
        - [ ] Should sanctum spells be bundled/packaged into an app?
    - [ ] Remove this section from the README, create release notes and initial release artifacts.

## v0.2 Prototype - Pending

Upgrades the runtime with persistence for events and spell state. Sanctum can be used for real workloads with no guarantees.
Runs on a single node (no networking).

- [ ] Storage Engine MVP
    - [ ] Durable event logging.
    - [ ] Durable spell state
        - [ ] Spells can leverage a library for saving and loading data.
        - [ ] Spells can use a key value store.
        - [ ] Spells can leverage range queries (e.g. SELECT * FROM state WHERE v > 10 AND v < 20). I.e. support clustering in state store.
  - [ ] (Option) Link SQLite?
  - [ ] (Option) Provide simple data structures, serialize and save to disk?
- [ ] Add initial logging and metrics to identify performance characteristics.

## v1.0 Beta - Pending

Sanctum fully featured as an MVP.

- [ ] Production Readiness
  - [ ] Crash recovery guarantees.
  - [ ] Limits defined and scale targets established.
- [ ] Platform Stability
  - [ ] API contracts
  - [ ] Documentation
  - [ ] Performance optimization

## Work Triage

- [ ] Wrap the Lua VM so that detailed telemetry can be emitted, per instance.
    - memory usage, spell execution count+time, event input and output counters.
- [ ] Support N:M event inputs and outputs for spells (currently only supports 1:0 and 1:1).

## Glossary

Novice sorcers may struggle to uncover the mysteries of the Sanctum:

| Mystical Term | Technical Meaning |
|---------------|-------------------|
| Sanctum | A scriptable event streaming and storage platform. |
| Sorcerers | Developers building on Sanctum. |
| Spells | User-defined modules invoked with events in an event stream. Spells may cause new events to be created. |
| Energy Streams | Ordered event streams with immutable data. |
| Runes | Configuration options. |
| Runeset | YAML configuration file of options which can be used by the Sanctum or its Spells. | 

## Want to help?

Thank you, brave scholar of the dark arts, please refer to [CONTRIBUTING.md][CONT].

[CONT]: ./Contributing.md

## Project Status

Incubation.

*This mystical undertaking is still in its early phases.*

