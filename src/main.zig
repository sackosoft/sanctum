const std = @import("std");
const ziglua = @import("ziglua");
const sanctum = @import("libsanctum");

const Lua = ziglua.Lua;
const LuaType = ziglua.LuaType;

const debug_verbose = false;

const spell_name: []const u8 = "spell_of_decrementing_counter";
const spell: [:0]const u8 =
    \\local spell_of_decrementing_counter = {
    \\    cast = function(counter_event)
    \\        if (counter_event["counter"] == nil) then
    \\            return nil
    \\        end
    \\
    \\        if (counter_event.counter == 0) then
    \\            return nil
    \\        end
    \\
    \\        counter_event["counter"] = counter_event["counter"] - 1
    \\        return counter_event
    \\    end,
    \\    prepare = nil,
    \\    unprepare = nil,
    \\}
    \\return spell_of_decrementing_counter
;

pub fn main() !void {
    return main_internal() catch |e| {
        if (e == error.ExplainedExiting) {
            return;
        } else {
            return e;
        }
    };
}

fn main_internal() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const CounterEnergy = struct {
        counter: u32,
    };
    const L = std.DoublyLinkedList(CounterEnergy);

    var event = L.Node{
        .data = .{ .counter = 10 },
    };
    var queue = L{};
    queue.append(&event);

    var lua = try Lua.init(allocator);
    defer lua.deinit();
    lua.doString(spell) catch |e| {
        return try explainError(e, lua);
    };

    var i: usize = 0;
    var v: CounterEnergy = undefined;
    while (queue.popFirst()) |e| {
        // Seems like loading the module does not put the table members in the global namespace, that makes sense.
        // I guess the top of the stack is the table itself.
        // if (try lua.getGlobal("cast") != LuaType.function) {
        //     return error.UncastableSpell;
        // }

        event = e.*;
        try lua.pushAny("cast");
        const valType = lua.getTable(-2);
        if (valType != LuaType.function) {
            return error.UncastableSpell;
        }
        v = e.data;
        try lua.pushAny(event.data);
        lua.protectedCall(.{ .args = 1, .results = 1 }) catch |err| {
            return try explainError(err, lua);
        };

        if (lua.isNil(-1)) {
            // explicit stop condition for now.
            break;
        }
        v = lua.toAny(CounterEnergy, -1) catch |err| {
            return try explainError(err, lua);
        };
        lua.pop(1);
        std.debug.print("Casted {s}: CounterEnergy.counter is {d}\n", .{ spell_name, v.counter });

        i += 1;
        event.data = v;
        queue.append(&event);
    }
}

fn explainError(e: anytype, lua: *Lua) !void {
    if (e == error.LuaSyntax) {
        try explainSyntaxError(lua);
        return error.ExplainedExiting;
    } else if (e == error.LuaRuntime) {
        try explainRuntimeError(lua);
        return error.ExplainedExiting;
    } else {
        const err_text = try lua.toString(-1);
        std.debug.print("Lua Error Text: '{s}'\n", .{err_text});
    }

    return e;
}

fn explainRuntimeError(lua: *Lua) !void {
    const err_text = try lua.toString(-1);
    var line: ?usize = null;
    if (std.mem.indexOf(u8, err_text, ":")) |first_colon| {
        if (std.mem.indexOf(u8, err_text[first_colon + 1 ..], ":")) |second_colon| {
            const line_number_text = err_text[first_colon + 1 .. first_colon + 1 + second_colon];
            const error_message_text = err_text[first_colon + 1 + second_colon ..];

            line = try std.fmt.parseInt(usize, line_number_text, 10);
            std.debug.print("Runtime error in spell on line {s}: {s}", .{ line_number_text, error_message_text });
        }
    }
    std.debug.print("\n", .{});
    printSpellWithLineNumbers(spell, line, 1);
}

fn explainSyntaxError(lua: *Lua) !void {
    var line: ?usize = null;
    std.debug.print("Spell contains Lua syntax error", .{});
    const err_text = try lua.toString(-1);
    var parsed = false;
    if (std.mem.indexOf(u8, err_text, ":")) |first_colon| {
        if (std.mem.indexOf(u8, err_text[first_colon + 1 ..], ":")) |second_colon| {
            const line_number_text = err_text[first_colon + 1 .. first_colon + 1 + second_colon];
            const error_message_text = err_text[first_colon + 1 + second_colon ..];
            std.debug.print(" on line {s}{s}", .{ line_number_text, error_message_text });
            line = try std.fmt.parseInt(usize, line_number_text, 10);
            parsed = true;
        }
    }
    std.debug.print("\n", .{});
    printSpellWithLineNumbers(spell, line, 1);
}

fn printSpellWithLineNumbers(source: [:0]const u8, target_line: ?usize, context_lines: usize) void {
    var lines = std.mem.splitSequence(u8, source, "\n");
    var i: usize = 1;
    var end: usize = std.math.maxInt(usize);
    if (target_line) |l| {
        while (i < (l - context_lines)) {
            _ = lines.next();
            i += 1;
        }
        end = l + context_lines;
    }
    while (lines.next()) |line| {
        if (target_line) |l2| {
            if (i == l2) {
                std.debug.print("---> | {s}\n", .{line});
            } else {
                std.debug.print("{d:>4} | {s}\n", .{ i, line });
            }
        } else {
            std.debug.print("{d:>4} | {s}\n", .{ i, line });
        }

        i += 1;
        if (i > end) {
            break;
        }
    }
}
