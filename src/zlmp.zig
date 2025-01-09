const std = @import("std");
const ArrayList = std.ArrayList;

const native_endianness = @import("builtin").cpu.arch.endian();

const ziglua = @import("ziglua");
const Lua = ziglua.Lua;
const LuaInteger = ziglua.Integer;
const LuaNumber = ziglua.Number;

/// Returned by one of the `toMessagePack()` functions, contains a serialized version of a Lua VM value
/// on the stack. Used to save a value to storage or transmit the value over the network, as necessary.
/// The value can be placed back on a Lua VM stack with one of the `pushMessagePack()` functions.
pub const MessagePackBuffer = struct {
    /// A Message Pack formatted value that was serialized from a value on the Lua VM stack.
    message: []const u8,
};

/// Serializes the value on the stack at the specified index to a binary representation
/// using the Message Pack protocol. Uses the default options for serialization. The caller
/// is responsible to free the memory allocated and returned.
///
/// For information about the Message Pack project, refer to https://msgpack.org/
///
/// For information about the Message Pack Specification, refer to https://github.com/msgpack/msgpack/blob/master/spec.md
///
/// * Pops: `0`
/// * Pushes: `0`
pub fn toMessagePack(lua: *Lua, index: i32, alloc: std.mem.Allocator) !MessagePackBuffer {
    return toMessagePackOptions(lua, index, alloc, .{});
}

/// Serializes the value on the stack at the specified index to a binary representation
/// using the Message Pack protocol. Uses the given options for serialization. The caller
/// is responsible to free the memory allocated and returned.
///
/// For information about the Message Pack project, refer to https://msgpack.org/
///
/// For information about the Message Pack Specification, refer to https://github.com/msgpack/msgpack/blob/master/spec.md
///
/// * Pops: `0`
/// * Pushes: `0`
pub fn toMessagePackOptions(lua: *Lua, index: i32, alloc: std.mem.Allocator, options: ToMessagePackOptions) !MessagePackBuffer {
    return toMessagePackOptionsInternal(lua, index, alloc, options);
}

/// Deserializes the given binary content and restores the lua value represented to
/// the top of the stack. This function will internally allocate copies of memory in
/// the given buffer and the caller may free the memory used by the given buffer.
///
/// * Pops: `0`
/// * Pushes: `1`
pub fn pushMessagePack(lua: *Lua, buffer: MessagePackBuffer) !void {
    var i: usize = 0;
    return pushMessagePackInternal(lua, &i, buffer);
}

/// Controls how the serialization fucttions allocate memory when serializing lua values.
pub const AllocationStrategy = enum(u8) {
    /// When used, the value to be serialized will be traversed before serialization to determine
    /// the space required for the serialied result. This option is best used when objects to be
    /// serialized are known to be relatively small. This option prevents buffer resizing operations
    /// at the cost of some pre-traversal compute time.
    exact,

    /// When used, the buffer containing the serialized output will be dynamically resized as
    /// necessary while the serialization process fills the buffer with Message Pack formatted data.
    /// This option is best used when when objects to be serialied are known to be relatively large.
    /// This option should have the best performance for large objects where the buffer resizing
    /// operations are ammortized and a majority of time is spent following the serialiation protocol.
    realloc,
};

/// Used to control memory usage behavior of the serializer.
pub const ToMessagePackOptions = struct {
    /// When using the 'realloc' allocation strategy, the initial_capacity
    /// determines the size of the first buffer allocated during serialization.
    initial_capacity: u16 = 128,

    /// Controls how zlmp allocates memory when serializing lua values.
    allocation_strategy: AllocationStrategy = .exact,
};

const Protocol = struct {
    /// Some tags in the Message Pack protocol encode both the tag and a length value.
    /// These compound tags use the high order bits to uniquely identify the tag value,
    /// and the least significant bits to encode a short length value. Such tags can
    /// efficiently encode smaller instances of that data type. For example an integer
    /// near zero can be encoded in one byte, or short strings without an additional
    /// length field. Those tags appear here as having a `Min` and `Max` variant.
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

inline fn toMessagePackOptionsInternal(
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
        .number => {
            if (lua.isInteger(index)) {
                // LuaInteger is usually an i64, but Lua can be compiled with flags to target i32.
                // That case is *not* handled and I do not have any plans to handle it in the future.
                try packIntegerInto(&writer, try lua.toInteger(index));
            } else {
                // LuaNumber is usually a f64, but Lua can be compiled with flags to target f32.
                // That cast is *not* handled and I do not have any plans to handle it in the future.
                try packNumberInto(&writer, try lua.toNumber(index));
            }
        },
        .string => {
            try packStringInto(&writer, try lua.toString(index));
        },
        .table => {
            try packMapInto(al, &writer, lua, index);
        },

        // All non-data types will be ignored by design. These types cannot be serialized to the
        // message pack format and will be lost during a round trip through serialization.
        .none, .function, .thread => {},

        // We may end up implementing various functionalities via these types, but they will always
        // be platform-provided and not meaningful to any user-controlled data object.
        .userdata, .light_userdata => {},
    }
}

/// Used to encode the table at the given index on the stack into a MessagePack map object
/// in the message pack buffer.
///
/// NOTE: Only currently supports the map32 format because I want to avoid figuring out
/// how to efficiently count the number of elements in the map while serializing. This ought
/// to be updated to support the fixmap and map16 formats, since tables will usually be in
/// those size constraints.
///
/// For more information, refer to the Message Pack Specification for the int format family:
/// https://github.com/msgpack/msgpack/blob/master/spec.md#map-format-family
fn packMapInto(al: *ArrayList(u8), writer: *ArrayList(u8).Writer, lua: *Lua, index: i32) anyerror!void {
    try writer.writeByte(@intFromEnum(Protocol.Tags.Map32));

    // Index of the first byte of the placeholder value for `N`.
    // We cannot grab the pointer to this location here, since the array list may resize
    // and reallocate the buffer while we write the key value pairs into it. Instead,
    // the offset of this u32 in the buffer can be saved, and we can update the memory
    // with that stable offset later.
    const placeholder_location = al.items.len;

    // We are going to "come back" to setting `N` in the serialized output after
    // writing the `N*2` objects. At that point we will know the value of `N`.
    // For now, we will write a placeholder value and keep track of the location
    // where this information will need to be set later.
    // +-----+--------+--------+--------+--------+--------+~~~~~~~~~~~~~~~~~+
    // | ... |  0xdf  |11111111|11111111|11111111|11111111|   N*2 objects   |
    // +-----+--------+--------+--------+--------+--------+~~~~~~~~~~~~~~~~~+
    //                 ^
    //                 | placeholder_location
    const placeholder = 0xFFFFFFFF;
    try writer.writeInt(u32, placeholder, .big);

    // Message Pack protocol's `N` - representing the number of key value pairs in the map.
    var n: u32 = 0;

    // Refer to https://www.lua.org/manual/5.4/manual.html#lua_next for table iteration pattern.
    lua.pushNil();
    while (lua.next(index - 1)) : (n += 1) {
        // Push the key to the top of the stack with the value below it, since we need to serialize keys
        // before values.
        lua.insert(-2);
        try packInto(lua, al, -1);

        // Push the value to the top of the sack with the key below it so that we can seralize the value.
        // The table iteration pattern requires the key to remain on the stack for the next iteration,
        // so we do not want to pop it when we finish serializing it.
        lua.insert(-2);
        try packInto(lua, al, -1);

        // Both key and value have now been serialized, we can pop the value from the stack and go to the
        // next iteration. The key remains on top of the stack -- required for the iteration pattern
        lua.pop(1);
    }

    const n_slot: *[4]u8 = @ptrCast(&al.items[placeholder_location]);
    std.mem.writeInt(u32, n_slot, n, .big);
}

/// Used to encode the given integer value into the smallest capable MessagePack integer type
/// and writes it into the message pack buffer. Integers near zero are more frequent on average
/// than integers near the max and min value. We opt to use the full variable length encoding
/// functionalities of Message Pack to achieve space savings with negligible overhead.
///
/// For more information, refer to the Message Pack Specification for the int format family:
/// https://github.com/msgpack/msgpack/blob/master/spec.md#int-format-family
fn packIntegerInto(writer: *ArrayList(u8).Writer, v: i64) !void {
    switch (v) {
        std.math.minInt(i64)...(std.math.minInt(i32) - 1) => {
            try writeTaggedInt(writer, Protocol.Tags.Int64, i64, v);
        },
        std.math.minInt(i32)...(std.math.minInt(i16) - 1) => {
            try writeTaggedInt(writer, Protocol.Tags.Int32, i32, v);
        },
        std.math.minInt(i16)...(std.math.minInt(i8) - 1) => {
            try writeTaggedInt(writer, Protocol.Tags.Int16, i16, v);
        },
        std.math.minInt(i8)...(std.math.minInt(i6) - 1) => {
            try writeTaggedInt(writer, Protocol.Tags.Int8, i8, v);
        },
        std.math.minInt(i6)...-1 => {
            const negativeFixedIntSlot: u8 = 0b11100000;
            const tag = negativeFixedIntSlot | @as(u5, @bitCast(@as(i5, @truncate(v))));
            try writer.writeByte(tag);
        },
        0...std.math.maxInt(i8) => {
            const positiveFixedIntMask: u8 = 0b01111111;
            const tag = positiveFixedIntMask & @as(u8, @bitCast(@as(i8, @truncate(v))));
            try writer.writeByte(tag);
        },
        (std.math.maxInt(i8) + 1)...std.math.maxInt(i16) => {
            try writeTaggedInt(writer, Protocol.Tags.Int16, i16, v);
        },
        (std.math.maxInt(i16) + 1)...std.math.maxInt(i32) => {
            try writeTaggedInt(writer, Protocol.Tags.Int32, i32, v);
        },
        (std.math.maxInt(i32) + 1)...std.math.maxInt(i64) => {
            try writeTaggedInt(writer, Protocol.Tags.Int64, i64, v);
        },
    }
}

/// Used to write the given value to the message pack buffer with the specified format tag.
fn writeTaggedInt(
    writer: *ArrayList(u8).Writer,
    tag: Protocol.Tags,
    comptime T: type,
    int: LuaInteger,
) !void {
    try writer.writeByte(@intFromEnum(tag));
    try writer.writeInt(T, @as(T, @truncate(int)), .big);
}

/// Used to encode the given floating point value into the smallest capable MessagePack float type
/// (without loss of precision) and writes it into the message pack buffer.
///
/// For more information, refer to the Message Pack Specification for the float format family:
/// https://github.com/msgpack/msgpack/blob/master/spec.md#float-format-family
fn packNumberInto(writer: *ArrayList(u8).Writer, v: f64) !void {
    if (canBeFloat32WithoutLossOfPrecision(v)) {
        const sz = @sizeOf(f32);
        var float: [sz]u8 = undefined;
        std.mem.writeInt(u32, &float, @as(u32, @bitCast(@as(f32, @floatCast(v)))), .big);

        try writer.writeByte(@intFromEnum(Protocol.Tags.Float32));
        const actual = try writer.write(float[0..]);
        std.debug.assert(sz == actual);
    } else {
        const sz = @sizeOf(f64);
        var float: [sz]u8 = undefined;
        std.mem.writeInt(u64, &float, @as(u64, @bitCast(v)), .big);

        try writer.writeByte(@intFromEnum(Protocol.Tags.Float64));
        const actual = try writer.write(float[0..]);
        std.debug.assert(sz == actual);
    }
}

fn canBeFloat32WithoutLossOfPrecision(v64: f64) bool {
    return //
    std.math.isNan(v64) //
    or std.math.isInf(v64) //
    or std.math.isPositiveZero(v64) //
    or std.math.isNegativeZero(v64) //
    or v64 == @as(f64, @floatCast(@as(f32, @floatCast(v64))));
}

/// Used to encode the given string value into the smallest capable MessagePack string type
/// and writes it into the message pack buffer. Short strings with length near zero are more
/// frequent on average extremely long strings. We opt to use the full variable length encoding
/// functionalities of Message Pack to achieve space savings with negligible overhead.
///
/// For more information, refer to the Message Pack Specification for the int format family:
/// https://github.com/msgpack/msgpack/blob/master/spec.md#str-format-family
fn packStringInto(writer: *ArrayList(u8).Writer, str: [:0]const u8) !void {
    const length: u32 = @intCast(str.len);
    switch (length) {
        0...std.math.maxInt(u5) => {
            try writeFixedString(writer, str);
        },
        (std.math.maxInt(u5) + 1)...std.math.maxInt(u8) => {
            try writeTaggedLengthPrefixedString(writer, Protocol.Tags.Str8, str);
        },
        (std.math.maxInt(u8) + 1)...std.math.maxInt(u16) => {
            try writeTaggedLengthPrefixedString(writer, Protocol.Tags.Str16, str);
        },
        (std.math.maxInt(u16) + 1)...std.math.maxInt(u32) => {
            try writeTaggedLengthPrefixedString(writer, Protocol.Tags.Str32, str);
        },
    }
}

/// Used to write the given short string to the message pack buffer using the fixstr format.
fn writeFixedString(writer: *ArrayList(u8).Writer, str: [:0]const u8) !void {
    const length: u32 = @as(u32, @intCast(str.len));
    const fixedStringSlot: u8 = @intFromEnum(Protocol.Tags.FixstrMin);
    const tag = fixedStringSlot | @as(u5, @truncate(length));

    try writer.writeByte(tag);
    const actual = try writer.write(str);
    std.debug.assert(length == actual);
}

/// Used to write the given string to the message pack buffer using the specified string family format.
/// Only the str8, str16 and str32 (tag + length prefix) formats are supported. Callers should handle
/// fixstr format separately.
fn writeTaggedLengthPrefixedString(
    writer: *ArrayList(u8).Writer,
    comptime tag: Protocol.Tags,
    str: [:0]const u8,
) !void {
    const length: u32 = @as(u32, @intCast(str.len));
    const T: type = switch (tag) {
        Protocol.Tags.Str8 => u8,
        Protocol.Tags.Str16 => u16,
        Protocol.Tags.Str32 => u32,
        else => return error.InvalidTagForString,
    };

    // Message Pack procol value `N` -- an unsigned int representing the length of the string that follows.
    var n: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &n, @as(T, @truncate(length)), .big);

    try writer.writeByte(@intFromEnum(tag));
    const actual_len = try writer.write(n[0..]);
    const actual_str = try writer.write(str);

    std.debug.assert(@sizeOf(T) == actual_len);
    std.debug.assert(str.len == actual_str);
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

const Iter = struct {
    fn next(index: *usize) void {
        advance(index, 1);
    }
    fn advance(index: *usize, amt: usize) void {
        index.* += @intCast(amt);
    }
    fn advanceByType(index: *usize, comptime T: type) void {
        index.* += @sizeOf(T);
    }
};
pub fn pushMessagePackInternal(lua: *Lua, i: *usize, buffer: MessagePackBuffer) !void {
    while (i.* < buffer.message.len) {
        const tag_value = buffer.message[i.*];
        const tag: Protocol.Tags = @enumFromInt(tag_value);
        Iter.next(i);

        switch (tag_value) {
            @intFromEnum(Protocol.Tags.Nil) => {
                lua.pushNil();
            },

            @intFromEnum(Protocol.Tags.False), @intFromEnum(Protocol.Tags.True) => {
                const value = (tag == Protocol.Tags.True);
                lua.pushBoolean(value);
            },

            @intFromEnum(Protocol.Tags.PositiveFixintMin)...@intFromEnum(Protocol.Tags.PositiveFixintMax) => {
                const value = @as(u7, @truncate(tag_value));
                lua.pushInteger(value);
            },

            @intFromEnum(Protocol.Tags.NegativeFixintMin)...@intFromEnum(Protocol.Tags.NegativeFixintMax) => {
                const value = @as(i5, @bitCast(@as(u5, @truncate(tag_value))));
                lua.pushInteger(value);
            },

            @intFromEnum(Protocol.Tags.FixstrMin)...@intFromEnum(Protocol.Tags.FixstrMax) => {
                const len = @as(u5, @truncate(tag_value));

                std.debug.assert(buffer.message[i.* + len - 1] == 0);
                const str = buffer.message[i.* .. i.* + len];
                Iter.advance(i, len);

                _ = lua.pushString(str);
            },

            // At the time of writing, only map32 format is supported by the serializer; however,
            // we will implement support for all of the map types, since the deserialization work
            // is not blocked by the same issue.
            //
            // The serializer does not support all types because we need to know ahead of time,
            // before iterating the table, how many bytes to skip for the number of pairs in
            // the map. I was being lazy and didn't want to figure that out yet, so we just always
            // use the map32 format.
            @intFromEnum(Protocol.Tags.FixmapMin)...@intFromEnum(Protocol.Tags.FixmapMax) => {
                const kvp_count: u32 = @intCast(@as(u4, @truncate(tag_value)));
                try pushTable(lua, i, buffer, kvp_count);
            },

            @intFromEnum(Protocol.Tags.Int8) => {
                const t_int = i8;
                pushInteger(lua, t_int, i.*, buffer.message);
                Iter.advanceByType(i, t_int);
            },
            @intFromEnum(Protocol.Tags.Int16) => {
                const t_int = i16;
                pushInteger(lua, t_int, i.*, buffer.message);
                Iter.advanceByType(i, t_int);
            },
            @intFromEnum(Protocol.Tags.Int32) => {
                const t_int = i32;
                pushInteger(lua, t_int, i.*, buffer.message);
                Iter.advanceByType(i, t_int);
            },
            @intFromEnum(Protocol.Tags.Int64) => {
                const t_int = i64;
                pushInteger(lua, t_int, i.*, buffer.message);
                Iter.advanceByType(i, t_int);
            },

            @intFromEnum(Protocol.Tags.Str8) => {
                const t_len_int = u8;
                const len = peekInteger(t_len_int, i.*, buffer.message);
                Iter.advanceByType(i, t_len_int);

                pushString(lua, i.*, buffer.message, @intCast(len));
                Iter.advance(i, len);
            },
            @intFromEnum(Protocol.Tags.Str16) => {
                const t_len_int = u16;
                const len = peekInteger(t_len_int, i.*, buffer.message);
                Iter.advanceByType(i, t_len_int);

                pushString(lua, i.*, buffer.message, @intCast(len));
                Iter.advance(i, len);
            },
            @intFromEnum(Protocol.Tags.Str32) => {
                const t_len_int = u32;
                const len = peekInteger(t_len_int, i.*, buffer.message);
                Iter.advanceByType(i, t_len_int);

                pushString(lua, i.*, buffer.message, @intCast(len));
                Iter.advance(i, len);
            },

            @intFromEnum(Protocol.Tags.Float32) => {
                const t_float = f32;
                const value = peekFloat(t_float, i.*, buffer.message);
                Iter.advanceByType(i, t_float);

                lua.pushNumber(@as(LuaNumber, @floatCast(value)));
            },
            @intFromEnum(Protocol.Tags.Float64) => {
                const t_float = f64;
                const value = peekFloat(t_float, i.*, buffer.message);
                Iter.advanceByType(i, t_float);

                lua.pushNumber(@as(LuaNumber, @floatCast(value)));
            },

            // At the time of writing, only map32 format is supported by the serializer; however,
            // we will implement support for all of the map types, since the deserialization work
            // is not blocked by the same issue.
            //
            // The serializer does not support all types because we need to know ahead of time,
            // before iterating the table, how many bytes to skip for the number of pairs in
            // the map. I was being lazy and didn't want to figure that out yet, so we just always
            // use the map32 format.
            @intFromEnum(Protocol.Tags.Map16) => {
                const t_int = u16;
                const kvp_count: u32 = @intCast(peekInteger(t_int, i.*, buffer.message));
                Iter.advanceByType(i, t_int);

                try pushTable(lua, i, buffer, kvp_count);
            },
            @intFromEnum(Protocol.Tags.Map32) => {
                const t_int = u32;
                const kvp_count: u32 = peekInteger(t_int, i.*, buffer.message);
                Iter.advanceByType(i, t_int);

                try pushTable(lua, i, buffer, kvp_count);
            },

            else => {
                std.debug.print("Found unrecognized message pack tag 0x{x} at index {d}\n", .{ @intFromEnum(tag), i });
                return error.UnrecognizedMessagePackTag;
            },
        }
    }

    std.debug.assert(i.* == buffer.message.len);
}

fn pushInteger(lua: *Lua, comptime T: type, i: usize, message: []const u8) void {
    const value = peekInteger(T, i, message);
    lua.pushInteger(@as(LuaInteger, @intCast(value)));
}

fn pushString(lua: *Lua, i: usize, message: []const u8, len: usize) void {
    const str = message[i..(i + len)];
    _ = lua.pushString(str);
}

fn pushTable(lua: *Lua, i: *usize, buffer: MessagePackBuffer, kvp_count: u32) anyerror!void {
    lua.newTable();

    for (0..kvp_count) |_| {
        try pushMessagePackInternal(lua, i, buffer); // key
        try pushMessagePackInternal(lua, i, buffer); // value

        lua.setTable(-3); // table[key] = value
    }
}

/// Reads the integer of size `T` from the given Message Pack message at index `i`.
///
/// Multi-byte numbers in the Message Pack specification are always in big-endian format.
/// This function handles conversion to the native endianess.
fn peekInteger(comptime T: type, i: usize, message: []const u8) T {
    const number: *const [@sizeOf(T)]u8 = @ptrCast(message[i..(i + @sizeOf(T))]);
    return std.mem.readInt(T, number, .big);
}

/// Reads a floating point number of size `T` from the given Message Pack message at
/// index `i`.
///
/// Floating point numbers in the Message Pack specification are always in big-endian format.
/// This function handles conversion to the native endianess.
fn peekFloat(comptime T: type, i: usize, message: []const u8) T {
    const TSizedUint = switch (T) {
        f16 => u16,
        f32 => u32,
        f64 => u64,
        f80 => u80,
        f128 => u128,
        else => {
            @compileError("Unsupported float type '" ++ @typeName(T) ++ "': peekFloat(T, ...) only supports one of (f16, f32, f64, f80, f128)");
        },
    };

    var buffer: TSizedUint = undefined;
    @memcpy(@as(*[@sizeOf(TSizedUint)]u8, @ptrCast(&buffer)), message[i .. i + @sizeOf(T)]);

    if (native_endianness == .little) {
        buffer = @byteSwap(buffer);
    }

    return @as(*T, @ptrCast(&buffer)).*;
}
