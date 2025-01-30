local topic_counter = {
    topic = { "counter", "other-counter" },
    cast = function(event)
        _ = event
        print("Received an event!")
    end,
}
return topic_counter
