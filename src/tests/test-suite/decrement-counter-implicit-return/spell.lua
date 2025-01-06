local decrement_counter = {
    cast = function(event)
        if event.counter > 1 then
            event.counter = event.counter - 1
            print(string.format("The counter is now %d.", event.counter))
            return event
        end

        print(string.format("The counter has reached 0, stopping.", event.counter))
    end,
}
return decrement_counter
