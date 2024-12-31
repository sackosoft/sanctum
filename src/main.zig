const std = @import("std");
const ziglua = @import("ziglua");
const sanctum = @import("libsanctum");

const Lua = ziglua.Lua;
const LuaType = ziglua.LuaType;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const selected_spell = blk: {
        const args: [][:0]u8 = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);
        break :blk try loadSpellOrDefault(args, default_spell);
    };

    return cast_spell(alloc, selected_spell) catch |e| {
        if (e == error.ExplainedExiting) {
            return;
        } else {
            return e;
        }
    };
}

const Spell = struct {
    name: []const u8,
    lua: [:0]const u8,
};

const default_spell = Spell{
    .name = "counter_decrementing_spell",
    .lua =
    \\local counter_decrementing_spell = {
    \\    cast = function(counter_event)
    \\        if (counter_event.counter == 0) then
    \\            return nil
    \\        end
    \\
    \\        counter_event.counter = counter_event.counter - 1
    \\        return counter_event
    \\    end,
    \\}
    \\return counter_decrementing_spell
    ,
};

fn loadSpellOrDefault(args: [][:0]u8, default: Spell) !Spell {
    // TODO: Load from file based on specified arguments.
    _ = args;
    return default;
}

fn cast_spell(alloc: std.mem.Allocator, spell: Spell) !void {
    const CounterEvent = struct {
        counter: u32,
    };
    const L = std.DoublyLinkedList(CounterEvent);

    var event = L.Node{
        .data = .{ .counter = 10 },
    };
    var queue = L{};
    queue.append(&event);

    var lua = try Lua.init(alloc);
    defer lua.deinit();
    lua.doString(spell.lua) catch |e| {
        return try explainError(e, lua, spell);
    };

    var i: usize = 0;
    var v: CounterEvent = undefined;
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
            return try explainError(err, lua, spell);
        };

        if (lua.isNil(-1)) {
            // explicit stop condition for now.
            break;
        }
        v = lua.toAny(CounterEvent, -1) catch |err| {
            return try explainError(err, lua, spell);
        };
        lua.pop(1);
        std.debug.print("Casted {s}: CounterEvent.counter is {d}\n", .{ spell.name, v.counter });

        i += 1;
        event.data = v;
        queue.append(&event);
    }
}

fn explainError(e: anytype, lua: *Lua, spell: Spell) !void {
    if (e == error.LuaSyntax) {
        try explainSyntaxError(lua, spell);
        return error.ExplainedExiting;
    } else if (e == error.LuaRuntime) {
        try explainRuntimeError(lua, spell);
        return error.ExplainedExiting;
    } else {
        const err_text = try lua.toString(-1);
        std.debug.print("Lua Error Text: '{s}'\n", .{err_text});
    }

    return e;
}

fn explainRuntimeError(lua: *Lua, spell: Spell) !void {
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
    printSourceCodeContext(spell.lua, line, 1);
}

fn explainSyntaxError(lua: *Lua, spell: Spell) !void {
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
    printSourceCodeContext(spell.lua, line, 1);
}

fn printSourceCodeContext(source: [:0]const u8, focus_line: ?usize, context_line_count: usize) void {
    var lines = std.mem.splitSequence(u8, source, "\n");
    var i: usize = 1;
    var end: usize = std.math.maxInt(usize);
    if (focus_line) |l| {
        while (i < (l - context_line_count)) {
            _ = lines.next();
            i += 1;
        }
        end = l + context_line_count;
    }
    while (lines.next()) |line| {
        if (focus_line) |l2| {
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
