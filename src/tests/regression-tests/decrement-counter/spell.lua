local decrement_counter = {
    cast = function(counter_event)
        if counter_event.counter <= 1 then
            print(string.format("The counter has reached 0, stopping.", counter_event.counter))
            return nil
        end

        counter_event.counter = counter_event.counter - 1
        print(string.format("The counter is now %d.", counter_event.counter))
        return counter_event
    end,
}
return decrement_counter
