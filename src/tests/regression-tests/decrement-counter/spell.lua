local decrement_counter = {
    cast = function(counter_event)
        if counter_event.counter == 0 then
            return nil
        end

        counter_event.counter = counter_event.counter - 1
        return counter_event
    end,
}
return decrement_counter
