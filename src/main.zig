const std = @import("std");
const ziglua = @import("ziglua");
const sanctum = @import("libsanctum");

const Lua = ziglua.Lua;
const LuaType = ziglua.LuaType;

const MAX_SPELL_SIZE_BYTES: usize = 1024 * 512;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const run_command_args = blk: {
        const args: [][:0]u8 = try std.process.argsAlloc(alloc);
        defer std.process.argsFree(alloc, args);

        break :blk RunCommandArgs{
            .spell = try loadSpell(alloc, args),
            .event_seed_lua = try loadEventSeed(alloc, args),
        };
    };
    defer alloc.free(run_command_args.spell.name);
    defer alloc.free(run_command_args.spell.lua);
    defer alloc.free(run_command_args.event_seed_lua);

    return runCommand(alloc, run_command_args) catch |e| {
        if (e == error.ExplainedExiting) {
            std.process.exit(1);
        } else {
            return e;
        }
    };
}

const RunCommandArgs = struct {
    spell: Spell,
    event_seed_lua: [:0]const u8,
};

const Spell = struct {
    name: []const u8,
    lua: [:0]const u8,
};

fn printExpectedUsage() void {
    std.debug.print("Usage: `sanctum cast <path_to_spell> --seed <path_to_seed_file>`\n", .{});
}

fn loadSpell(alloc: std.mem.Allocator, args: [][:0]u8) !Spell {
    if (args.len < 3) {
        std.debug.print("Expected at least two commandline arguments, but found {d}.\n", .{args.len});
        printExpectedUsage();
        return error.InvalidArguments;
    }

    const command = args[1];
    if (!std.mem.eql(u8, "cast", command)) {
        std.debug.print("Unrecognized command '{s}', expected one of ['cast']\n", .{command});
        printExpectedUsage();
        return error.InvalidArguments;
    }

    const path = args[2];
    const dir = std.fs.cwd();
    var f = dir.openFile(path, .{}) catch |e| {
        std.debug.print("Unable to open spell file '{s}'\n", .{path});
        return e;
    };
    defer f.close();

    const start_of_file_name = std.mem.lastIndexOfAny(u8, path, "/");
    const name: []const u8 = try alloc.dupe(u8, (if (start_of_file_name) |s| path[(s + 1)..] else path));
    const spell: [:0]const u8 = try f.readToEndAllocOptions(alloc, MAX_SPELL_SIZE_BYTES, null, 1, 0);
    return Spell{
        .name = name,
        .lua = spell,
    };
}

fn loadEventSeed(alloc: std.mem.Allocator, args: [][:0]u8) ![:0]const u8 {
    for (0..args.len - 1) |i| {
        if (std.mem.eql(u8, "--seed", args[i])) {
            const path = args[i + 1];
            const dir = std.fs.cwd();

            var f = dir.openFile(path, .{}) catch |e| {
                std.debug.print("Unable to open seed event file '{s}'\n", .{path});
                return e;
            };
            defer f.close();

            return try f.readToEndAllocOptions(alloc, MAX_SPELL_SIZE_BYTES, null, 1, 0);
        }
    }

    std.debug.print("Expected to find '--seed <path_to_event_seed_file>' arguments, but they were not found.\n", .{});
    return error.InvalidArguments;
}
fn runCommand(alloc: std.mem.Allocator, command: RunCommandArgs) !void {
    var lua = try Lua.init(alloc);
    defer lua.deinit();

    lua.openBase();
    lua.openString();

    try checkedDoString(lua, command.spell.lua);

    try lua.pushAny("cast");
    var valType = lua.getTable(-2);
    if (valType != LuaType.function) {
        std.debug.print("Expected to find function on stack (-3) before submitting a protected call, however, it was a {s} instead\n", .{@tagName(valType)});
        return error.UncastableSpell;
    }

    try checkedDoString(lua, command.event_seed_lua);

    var i: usize = 0;
    while (!shouldStop(lua, i)) : (i += 1) {
        try checkedCall(lua, command);

        // The return value from casting the spell is on top of the stack.
        // We will push the cast function to the top of the stack on top of the return value, then insert it before the return value
        // so that it is ready to be called again.
        try lua.pushAny("cast");
        valType = lua.getTable(-3);
        if (valType != LuaType.function) {
            std.debug.print("Expected to find function on stack (-3) before submitting a protected call, however, it was a {s} instead\n", .{@tagName(valType)});
            return error.UncastableSpell;
        }
        lua.insert(-2);
    }
}

fn shouldStop(lua: *Lua, i: usize) bool {
    // For now, it is an explicit stop condition when the spell returns `nil` instead of producing a new event.
    // Additionally, we will forcefully bound execution to 1000 iterations for now, to prevent runaway execution.
    return lua.isNil(-1) or i > 1_000;
}

fn checkedDoString(lua: *Lua, source: [:0]const u8) !void {
    lua.doString(source) catch |e| {
        return try explainError(e, lua, source);
    };
}

fn checkedCall(lua: *Lua, command: RunCommandArgs) !void {
    lua.protectedCall(.{ .args = 1, .results = 1 }) catch |err| {
        return try explainError(err, lua, command.spell.lua);
    };
}

fn explainError(e: anytype, lua: *Lua, source: [:0]const u8) !void {
    if (e == error.LuaSyntax) {
        try explainSyntaxError(lua, source);
        return error.ExplainedExiting;
    } else if (e == error.LuaRuntime) {
        try explainRuntimeError(lua, source);
        return error.ExplainedExiting;
    } else {
        const err_text = try lua.toString(-1);
        std.debug.print("Lua Error Text: '{s}'\n", .{err_text});
    }

    return e;
}

fn explainRuntimeError(lua: *Lua, source: [:0]const u8) !void {
    const err_text = try lua.toString(-1);
    var line: ?usize = null;
    if (std.mem.indexOf(u8, err_text, ":")) |first_colon| {
        if (std.mem.indexOf(u8, err_text[first_colon + 1 ..], ":")) |second_colon| {
            const line_number_text = err_text[first_colon + 1 .. first_colon + 1 + second_colon];
            const error_message_text = err_text[first_colon + 1 + second_colon ..];

            line = try std.fmt.parseInt(usize, line_number_text, 10);
            std.debug.print("Runtime error in spell on line {s}: {s}\n", .{ line_number_text, error_message_text });
        }
    } else {
        std.debug.print("{s}\n", .{err_text});
    }
    printSourceCodeContext(source, line, 1);
}

fn explainSyntaxError(lua: *Lua, source: [:0]const u8) !void {
    var line: ?usize = null;
    std.debug.print("Spell contains Lua syntax error", .{});
    const err_text = try lua.toString(-1);
    var parsed = false;
    if (std.mem.indexOf(u8, err_text, ":")) |first_colon| {
        if (std.mem.indexOf(u8, err_text[first_colon + 1 ..], ":")) |second_colon| {
            const line_number_text = err_text[first_colon + 1 .. first_colon + 1 + second_colon];
            const error_message_text = err_text[first_colon + 1 + second_colon ..];
            std.debug.print(" on line {s}{s}\n", .{ line_number_text, error_message_text });
            line = try std.fmt.parseInt(usize, line_number_text, 10);
            parsed = true;
        }
    } else {
        std.debug.print("{s}\n", .{err_text});
    }
    printSourceCodeContext(source, line, 1);
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
