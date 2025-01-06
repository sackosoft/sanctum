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


### Writing Spells

*Only spells following the guidance of the ancient elders may be cast in the sanctum.*

A spell is a Lua module that exports a table with specific function names. The table must contain a `cast` function and may
optionally include `prepare` and `unprepare` lifecycle functions.

```lua
local decrementing_counter_spell = {
    prepare = function(config)
        -- Called once when the spell is loaded.
    end,

    cast = function(event)
        if event.counter == 0 then
            -- Exit without producing a new event.
            return nil
        end

        event.counter = event.counter - 1

        -- Produce a new event.
        return event
    end,

    unprepare = function()
        -- Called once before sanctum exits
    end,
}
return decrementing_counter_spell
```

Spells must define required functions, but optional functions do not need to be added to the spell's table.

```lua
local decrementing_counter_spell = {
    cast = function(event)
        if event.counter == 0 then
            return nil
        end

        event.counter = event.counter - 1
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

