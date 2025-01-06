# Docunomicon

*Even the mightiest archmage is but a novice without their library, for true power lies not in the wielder of magic, but in
the countless tomes of those who came before.*

Welcome to the Docunomicon, the core user documentation for the Sanctum and its inner workings.


## Spells

*Spells harness ethereal streams of energy to manifest worldly changes or birth new magical energies for others to weave.*

Spells are modules written in [Lua][LUA-LANG]. Spells are invoked with events from the event stream. A spell may act upon an event
to perform an action, update internal state maintained by that spell, or produce new events as output for other spells to consume.
Novice sorcerers should refer to the [Tome of Lua 5.4 Wisdom][LUA-MANUAL].

[LUA-LANG]: https://www.lua.org/download.html
[LUA-MANUAL]: https://www.lua.org/manual/5.4/manual.html

Support for spells written in [Wren][WREN-LANG] is planned in later stages of the project; however, only Lua is supported for now.

[WREN-LANG]: https://github.com/wren-lang/wren


### Writing Spells

*Only spells following the guidance of the ancient elders may be cast in the sanctum.*

A spell is a Lua module that returns a table with functions to handle the spell lifeccle and event proessing. The
table itself represents the 'spell' and must contain a `cast` function. Optionally, the `prepare` and `unprepare`
lifecycle functions can be provided for spell initialization and shutdown.

```lua
local decrementing_counter_spell = {
    prepare = function(config)
        -- Called once when the spell is first loaded into sanctum.
    end,

    cast = function(event)
        -- Called to handle an event from an event stream.
    end,

    unprepare = function()
        -- Called once before sanctum exits
    end,
}
return decrementing_counter_spell
```

Spells must define required functions, but optional functions do not need to be added to the spell's table. Events
are data-only tables. Currently, Sanctum spells are expected to accept one event as input and produce zero or one
event as output. Event tables returned by the `cast` function will enter the event stream, and can be picked up
by spells for processing. When the `cast` function returns `nil`, not output event will be produced.

```lua
local decrementing_counter_spell = {
    cast = function(event)
        if event.counter == 0 then
            -- Exit without producing a new event.
            return nil
        end

        event.counter = event.counter - 1

        -- Produce a new event.
        return event
    end,
}
return decrementing_counter_spell
```

| Function Name  | Required | Description |
|----------------|----------|-------------|
| cast           | Yes      | Invoked with relevant events from the event stream. Refer to [Filtering](#filtering) for more information about configuring relevant events for a spell. |
| prepare        | No       | Called once, before first `cast`, when the spell enters into the Sanctum. Use for initialization. |
| unprepare      | No       | Called once when the spell is removed from the Sanctum. Use for cleanup. |

Lua functions implicitly return `nil` when no value is returned. The following `decrementing_counter_spell`
has the same behavior as above without a `return nil` statement.

```lua
local decrementing_counter_spell = {
    cast = function(event)
        if event.counter > 1 then
            event.counter = event.counter - 1
            return event
        end
    end,
}
return decrementing_counter_spell
```

## Filtering

*Different spells draw on different sources of energy to be cast.*

Usually, spells only care about a subset of the events flowing through the event stream. Spells may declaratively
specity the kinds of events they wish to be cast on, or conditions that events must satisfy to be cast by a spell.

The design for event filtering is open, and will change as the prototype of Sanctum is implemented.

