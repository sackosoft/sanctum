const std = @import("std");
const ziglua = @import("ziglua");
const sanctum = @import("libsanctum");

const Lua = ziglua.Lua;
const LuaType = ziglua.LuaType;
const LuaInteger = ziglua.Integer;
const LuaNumber = ziglua.Number;

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

    // Allows for `print()`, among other things
    lua.openBase();

    // Allows for `string.format()`, among other things.
    lua.openString();

    // The spell is a table that sits on the bottom of the stack. At present, it should never
    // be mutated and it should never move on the stack. Calls to functions inside this table
    // are made in order to "prepare" and "cast" the spell.
    try checkedDoString(lua, command.spell.lua);
    try validateCallable(lua, "cast", command.spell.lua);

    // The seed event is placed on top of the stack to prepare for execution. I believe this is
    // temporary, for the POC-phase of the project, and will eventually be replaced by an event
    // [de]serialization layer with an event queues to pull events from.
    try checkedDoString(lua, command.event_seed_lua);
    try prepareSpellCall(lua, "cast", 1);

    // Temporary: Do a round trip serialization.
    const event: MessagePackBuffer = try toMessagePack(lua, alloc);
    defer alloc.free(event.data);
    lua.pop(1);
    try pushMessagePack(lua, event);

    var i: usize = 0;
    while (!shouldStop(lua, i)) : (i += 1) {
        try checkedCall(lua, command);
        try prepareSpellCall(lua, "cast", 1);
    }
}

const MessagePackBuffer = struct {
    data: []const u8,
};

fn toMessagePack(lua: *Lua, alloc: std.mem.Allocator) !MessagePackBuffer {
    try guardTypeAt(lua, LuaType.table, -1);

    const size: usize = try messagePackSizeOfTable(lua, -1);
    const buffer: []u8 = try alloc.alloc(u8, size);
    _ = try messagePack(lua, buffer, -1);
    return .{ .data = buffer };
}

fn messagePackSizeOfTable(lua: *Lua, table_offset: i32) !usize {
    try guardTypeAt(lua, LuaType.table, table_offset);

    // Message pack supports maps with varying sizes and varying overhead. For now, to keep it simple we will support
    // the largest map capacity with the largest overhead instead of trying to calculate the optimal value (which depends
    // on the number of key value pairs in the map).
    // Refer to https://github.com/msgpack/msgpack/blob/master/spec.md#map-format-family
    const messagePackMapOverheadBytes = 5;

    var sz: usize = 0;
    sz += messagePackMapOverheadBytes;

    // Refer to https://www.lua.org/manual/5.4/manual.html#lua_next for table iteration pattern.
    lua.pushNil();
    while (lua.next(table_offset - 1)) {
        sz += if (lua.typeOf(-1) == LuaType.table) try messagePackSizeOfTable(lua, -1) else try messagePackSizeOf(lua, -1);
        lua.pop(1);

        sz += if (lua.typeOf(-1) == LuaType.table) try messagePackSizeOfTable(lua, -1) else try messagePackSizeOf(lua, -1);
    }

    std.debug.print("Table will fit in {d} bytes using MessagePack.\n", .{sz});
    return sz;
}

fn messagePackSizeOf(lua: *Lua, offset: i32) !usize {
    return switch (lua.typeOf(offset)) {
        .nil => 1,
        .boolean => 1,
        .number => if (lua.isInteger(offset)) @sizeOf(LuaInteger) else @sizeOf(LuaNumber),
        .string => lua.rawLen(offset),

        // The caller must enumerate the contents of the table and ask for the the size of each of the objects within the table.
        // It is not valid to ask for the size of the table itself.
        .table => error.SizeOfTableNotSupported,

        // Events are data-only tables, we will ignore all non-data types.
        .none, .function, .userdata, .light_userdata, .thread => 0,
    };
}

fn guardTypeAt(lua: *Lua, expected_type: LuaType, offset: i32) !void {
    const actual_type = lua.typeOf(offset);
    if (expected_type != actual_type) {
        std.debug.print("[Guard] Expected to find a '{s}' on the stack at ({d}) but found a '{s}' instead.\n", .{ @tagName(expected_type), offset, @tagName(actual_type) });
    }
}

fn messagePack(lua: *Lua, buffer: []u8, table_offset: i32) !usize {
    try guardTypeAt(lua, LuaType.table, table_offset);

    var i: usize = 0;
    var number_of_key_value_pairs: u32 = 0;

    // map32 byte
    buffer[i] = 0xdf;
    i += 1;

    // Skip the 32-bit count of key value pairs.
    i += 4;

    lua.pushNil();
    while (lua.next(table_offset - 1)) {
        number_of_key_value_pairs += 1;

        // Message pack expects keys to be followed by values, so reorder them on the stack before writing to the buffer.
        lua.insert(-2);
        i += if (lua.typeOf(-1) == LuaType.table) try messagePack(lua, buffer[i..], -1) else try packValue(lua, buffer[i..], -1);

        // Need to reorder again to make sure the key stays on the stack for next iteration.
        lua.insert(-2);
        lua.pop(1);
    }

    // TODO: Write the number of key value pairs to buffer[start + 1 .. start + 5]
    return i;
}

fn packValue(lua: *Lua, buffer: []u8, offset: i32) !usize {
    _ = buffer;
    return switch (lua.typeOf(offset)) {
        .nil => blk: {
            break :blk 1;
        },
        .boolean => 1,
        .number => if (lua.isInteger(offset)) @sizeOf(LuaInteger) else @sizeOf(LuaNumber),
        .string => lua.rawLen(offset),

        // The caller must enumerate the contents of the table and ask for the the size of each of the objects within the table.
        // It is not valid to ask for the size of the table itself.
        .table => error.SizeOfTableNotSupported,

        // Events are data-only tables, we will ignore all non-data types.
        .none, .function, .userdata, .light_userdata, .thread => 0,
    };
}

fn pushMessagePack(lua: *Lua, event: MessagePackBuffer) !void {
    _ = lua;
    _ = event;
}

fn validateCallable(lua: *Lua, function_name: [:0]const u8, lua_source: [:0]const u8) !void {
    const spellReturnType = lua.typeOf(-1);
    if (spellReturnType != LuaType.table) {
        std.debug.print("Unable magic detected. The spell must return a lua table, but found a {s} instead.\n", .{@tagName(spellReturnType)});
        printSourceCodeContext(lua_source, null, 0);
        return error.ExplainedExiting;
    }

    try lua.pushAny(function_name);
    const castType = lua.getTable(-2);
    if (castType == LuaType.nil) {
        std.debug.print("Unstable magic detected. The spell is missing the required function named '{s}'.\n", .{function_name});
        printSourceCodeContext(lua_source, null, 0);
        return error.ExplainedExiting;
    }

    if (castType != LuaType.function) {
        std.debug.print(
            "Unstable magic detected. The spell is missing required function '{s}'. Found a '{s}' called '{s}' instead.\n",
            .{ function_name, @tagName(castType), function_name },
        );
        printSourceCodeContext(lua_source, null, 0);
        return error.ExplainedExiting;
    }

    lua.pop(1);
}

/// Used to setup the contents and order of elements on the stack before the cast function of a spell
/// is invoked. If the argument(s) for the function call are already on the top of the stack, `stack_argc`
/// should be set to the number of arguments on top. This allows for the stack to be reordered appropriately,
/// and the protected call can be issued after `prepareSpellCall` returns. If no arguments for the function call
/// are already on the stack, `stack_argc` should be set to `0`. In this case, it is the responsibility of the
/// caller to push the arguments to the function onto the stack after `prepareSpellCall` returns.
fn prepareSpellCall(lua: *Lua, function_name: []const u8, stack_argc: u8) !void {
    try lua.pushAny(function_name);

    // TODO: I believe the spell is always at the bottom of the stack. Is it possible and/or is it more
    // simple to always index from the bottom rather than a relative offset from the top?
    const table_index = @as(i32, -2) - @as(i32, @intCast(stack_argc));

    const valType = lua.getTable(table_index);
    if (valType != LuaType.function) {
        std.debug.print(
            "Error: Preparing to call '{s}()'; expected to find the spell containing that function on the stack at ({d}); however, a {s} was found instead.\n",
            .{ function_name, table_index, @tagName(valType) },
        );
        return error.UncastableSpell;
    }

    if (stack_argc != 0) {
        // We need to move the `function` element on the stack below all the arguments in order to be ready to
        // call the function immediately upon return. If no args are on the stack, no problem, just return.
        const insert_index = @as(i32, -1) - @as(i32, @intCast(stack_argc));
        lua.insert(insert_index);
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
