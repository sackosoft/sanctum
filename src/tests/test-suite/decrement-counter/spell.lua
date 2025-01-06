local decrement_counter = {
    cast = function(event)
        if event.counter <= 1 then
            print(string.format("The counter has reached 0, stopping.", event.counter))
            return nil
        end

        event.counter = event.counter - 1
        print(string.format("The counter is now %d.", event.counter))
        return event
    end,
}
return decrement_counter
