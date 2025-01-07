const std = @import("std");

const ziglua = @import("ziglua");

const Lua = ziglua.Lua;
const LuaType = ziglua.LuaType;
const LuaInteger = ziglua.Integer;
const LuaNumber = ziglua.Number;

pub const MessagePackBuffer = struct {
    data: []const u8,
};

pub fn pushMessagePack(lua: *Lua, event: MessagePackBuffer) !void {
    _ = lua;
    _ = event;
}

pub fn toMessagePack(lua: *Lua, alloc: std.mem.Allocator) !MessagePackBuffer {
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
