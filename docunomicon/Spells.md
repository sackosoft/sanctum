# Spells

*Spells are cast with the etherial energies derived from the magical streams. Spells channel these energies into worldly actions
or create new energies conferred into other magical streams.*

Spells are modules written in [Lua][LUA-LANG]. Spells are invoked with events from the event stream. A spell may use that as a trigger
to perform an action, update internal state maintained for that spell, or produce new events for other spells to consume. Novice sorcerers
should refer to the [5.4 version of the Tome of Lua Wisdom][LUA-MANUAL].

[LUA-LANG]: https://www.lua.org/download.html
[LUA-MANUAL]: https://www.lua.org/manual/5.4/manual.html


## Writing Spells

In order for a spell to be cast in the Sanctum, it must follow the structure demanded by the elders. Valid spells are Lua modules that
return a table with well-known function names. When started, Sanctum will `prepare()` the spell, cast the spell with events found in the
event stream until shutdown, then `unprepare()` the spell before exiting.

```lua
local spell_of_decrementing_counter = {
    prepare = function(config)
        -- An optional step performed once when the spell is first loaded into the sanctum.
    end,
    cast = function(counter_event)
        if (counter_event.counter == 0) then
            return nil
        end

        counter_event.counter = counter_event.counter - 1
        return counter_event
    end,
    unprepare = function()
        -- An optional step performed once when the sanctum is closing.
        -- The spell will not be cast again.
    end,
}
return spell_of_decrementing_counter
```
