# Sanctum

Welcome, sorcerer, to the Sanctum. Write spells in Lua for transforming and acting on event streams of magical energy.

## What is Sanctum?

Sanctum is a platform that enables sorcerers to craft powerful spells that process and transform event streams. Sorcerers
focus on writing spells in their preferred language, while Sanctum handles the complexities of event storage, state and routing
these energies across the ethereal planes.

For more detailed reference information and documentation, refer to the [`docunomicon`](./docunomicon).

## Roadmap

# Release Roadmap

## v0.1 Proof of Concept - **Active**

Demonstrates event processing with Spells on a throw-away runtime. Runs on a single node (no networking, no persistence).

- [ ] Docunomicon - Definition and example of Lua spells
    - [ ] Documentation for spells in the runtime.
- [ ] Spell Casting
    - [ ] Spells can be loaded dynamically into the sanctum from files.
    - [ ] Counting loop spell is added with a reusable regression test.
    - [ ] Malformed spells (spell parse failure) are handled gracefully.
        - [ ] Handle parsing failing line number from errors Lua message.
    - [ ] Unstable magic (internal spell failures) is handled gracefully.
    - [ ] Spells can consume magical energy (events).
    - [ ] Spells can produce magical energy or act as a terminal action, producing nothing.

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

