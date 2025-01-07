const std = @import("std");
const ArrayList = std.ArrayList;

const ziglua = @import("ziglua");

const Lua = ziglua.Lua;
const LuaType = ziglua.LuaType;
const LuaInteger = ziglua.Integer;
const LuaNumber = ziglua.Number;

const Protocol = struct {
    const Tags = enum(u8) {
        // Positive fixint range (0 to 127)
        PositiveFixintMin = 0x00,
        PositiveFixintMax = 0x7f,

        // Fixmap range (0 to 15 elements)
        FixmapMin = 0x80,
        FixmapMax = 0x8f,

        // Fixarray range (0 to 15 elements)
        FixarrayMin = 0x90,
        FixarrayMax = 0x9f,

        // Fixstr range (0 to 31 bytes)
        FixstrMin = 0xa0,
        FixstrMax = 0xbf,

        // Specific values
        Nil = 0xc0,
        NeverUsed = 0xc1,
        False = 0xc2,
        True = 0xc3,
        Bin8 = 0xc4,
        Bin16 = 0xc5,
        Bin32 = 0xc6,
        Ext8 = 0xc7,
        Ext16 = 0xc8,
        Ext32 = 0xc9,
        Float32 = 0xca,
        Float64 = 0xcb,
        Uint8 = 0xcc,
        Uint16 = 0xcd,
        Uint32 = 0xce,
        Uint64 = 0xcf,
        Int8 = 0xd0,
        Int16 = 0xd1,
        Int32 = 0xd2,
        Int64 = 0xd3,
        Fixext1 = 0xd4,
        Fixext2 = 0xd5,
        Fixext4 = 0xd6,
        Fixext8 = 0xd7,
        Fixext16 = 0xd8,
        Str8 = 0xd9,
        Str16 = 0xda,
        Str32 = 0xdb,
        Array16 = 0xdc,
        Array32 = 0xdd,
        Map16 = 0xde,
        Map32 = 0xdf,

        // Negative fixint range (-32 to -1)
        NegativeFixintMin = 0xe0,
        NegativeFixintMax = 0xff,
    };
};

pub const MessagePackBuffer = struct {
    message: []const u8,
};

pub fn pushMessagePack(lua: *Lua, event: MessagePackBuffer) !void {
    _ = lua;
    _ = event;
}

/// Controls how zlmp allocates memory when serializing lua values.
pub const AllocationStrategy = enum(u8) {
    /// zlmp will pre-traverse the value to calculate the required space before
    /// beginning serialization. Optimal when objects to be serialized are known
    /// ahead of time to be relatively small.
    exact,
    /// zlmp will allocate an average sized buffer and grow the buffer with calls
    /// to realloc as necessary. Optimal when objects to be serialied are known
    /// ahead of time to be relatively large.
    realloc,
};
pub const ToMessagePackOptions = struct {
    /// When using the 'realloc' allocation strategy, the initial_capacity
    /// determines the size of the first buffer allocated during serialization.
    initial_capacity: u16 = 1024,

    /// Controls how zlmp allocates memory when serializing lua values.
    allocation_strategy: AllocationStrategy = .exact,
};

pub fn toMessagePack(
    lua: *Lua,
    index: i32,
    alloc: std.mem.Allocator,
) !MessagePackBuffer {
    return toMessagePackOptions(lua, index, alloc, .{});
}

/// Serializes the value on the stack at the specified index to a MessagePack message.
/// For now, only lua tables may be serialized. An error will be returned if the stack
/// does not contain a table at the specified index.
///
/// * Pops: `0`
/// * Pushes: `0`
/// * Errors: error.GuardFail - when the value at the specified index is not a table.
pub fn toMessagePackOptions(
    lua: *Lua,
    index: i32,
    alloc: std.mem.Allocator,
    options: ToMessagePackOptions,
) !MessagePackBuffer {
    var al = try switch (options.allocation_strategy) {
        .exact => blk: {
            const size: usize = try sizeOf(lua, index);
            break :blk ArrayList(u8).initCapacity(alloc, size);
        },
        .realloc => ArrayList(u8).initCapacity(alloc, options.initial_capacity),
    };
    defer al.deinit();

    _ = try packInto(lua, &al, index);

    // TODO: toOwnedSlice reallocates again. It might make more sense to either
    // embed the array list inside the returned struct, providing a method for getting
    // the data slice, and doing cleanup on deinit; or to pull the slice from the array
    // list without using `toOwnedSlice`. I don't know if I can just return `allocatedSlice`
    // and have the caller correctly deallocate it?
    return .{ .message = try al.toOwnedSlice() };
}

fn packInto(lua: *Lua, al: *ArrayList(u8), index: i32) !void {
    var writer = al.writer();
    switch (lua.typeOf(index)) {
        .nil => {
            try writer.writeByte(@intFromEnum(Protocol.Tags.Nil));
        },
        .boolean => {
            try writer.writeByte(@intFromEnum(Protocol.Tags.False) + @intFromBool(lua.toBoolean(index)));
        },
        .number => if (lua.isInteger(index)) {
            // TODO: I'm assuming LuaInteger is i64, but I believe Lua can be compiled to
            // target i32 and f32 number types. Not sure if I will ever use that (or a user
            // would ever require it) but this may fail to compile if that ever happens.
            const v: LuaInteger = try lua.toInteger(index);

            // Encode the runtime value with the smallest capable MessagePack type to save on space.
            switch (v) {
                std.math.minInt(i64)...(std.math.minInt(i32) - 1) => {
                    _ = Protocol.Tags.Int64;
                },
                std.math.minInt(i32)...(std.math.minInt(i16) - 1) => {
                    _ = Protocol.Tags.Int32;
                },
                std.math.minInt(i16)...(std.math.minInt(i8) - 1) => {
                    _ = Protocol.Tags.Int16;
                },
                std.math.minInt(i8)...(std.math.minInt(i6) - 1) => {
                    _ = Protocol.Tags.Int8;
                },
                std.math.minInt(i6)...-1 => {
                    const negativeFixedIntSlot: u8 = 0b11100000;
                    const byte = negativeFixedIntSlot | @as(u5, @bitCast(@as(i5, @truncate(v))));
                    try writer.writeByte(byte);
                },
                0...std.math.maxInt(i8) => {
                    const positiveFixedIntMask: u8 = 0b01111111;
                    const byte = positiveFixedIntMask & @as(u8, @bitCast(@as(i8, @truncate(v))));
                    try writer.writeByte(byte);
                },
                (std.math.maxInt(i8) + 1)...std.math.maxInt(i16) => {
                    _ = Protocol.Tags.Int16;
                },
                (std.math.maxInt(i16) + 1)...std.math.maxInt(i32) => {
                    _ = Protocol.Tags.Int32;
                },
                (std.math.maxInt(i32) + 1)...std.math.maxInt(i64) => {
                    _ = Protocol.Tags.Int64;
                },
            }
        } else {},
        .string => {},
        .table => {
            // Refer to https://www.lua.org/manual/5.4/manual.html#lua_next for table iteration pattern.
            lua.pushNil();
            while (lua.next(index - 1)) {
                lua.pop(1);
            }
        },

        // All non-data types will be ignored by design. These types cannot be serialized to the
        // message pack format and will be lost during a round trip through serialization.
        .none, .function, .thread => {},

        // We may end up implementing various functionalities via these types, but they will always
        // be platform-provided and not meaningful to any user-controlled data object.
        .userdata, .light_userdata => {},
    }
}

fn sizeOf(lua: *Lua, index: i32) !usize {
    // Message pack supports maps with varying sizes and varying overhead. For now, to keep it simple we will support
    // the largest map capacity with the largest overhead instead of trying to calculate the optimal value (which depends
    // on the number of key value pairs in the map).
    // Refer to https://github.com/msgpack/msgpack/blob/master/spec.md#map-format-family
    const messagePackMapOverheadBytes = 5;

    return switch (lua.typeOf(index)) {
        .nil => 1,
        .boolean => 1,
        .number => if (lua.isInteger(index)) @sizeOf(LuaInteger) else @sizeOf(LuaNumber),
        .string => lua.rawLen(index),
        .table => blk: {
            var sz: usize = 0;
            sz += messagePackMapOverheadBytes;

            // Refer to https://www.lua.org/manual/5.4/manual.html#lua_next for table iteration pattern.
            lua.pushNil();
            while (lua.next(index - 1)) {
                sz += try sizeOf(lua, -1);
                lua.pop(1);

                sz += try sizeOf(lua, -1);
            }

            break :blk sz;
        },

        // All non-data types will be ignored by design. These types cannot be serialized to the
        // message pack format and will be lost during a round trip through serialization.
        .none, .function, .thread => 0,

        // We may end up implementing various functionalities via these types, but they will always
        // be platform-provided and not meaningful to any user-controlled data object.
        .userdata, .light_userdata => 0,
    };
}
