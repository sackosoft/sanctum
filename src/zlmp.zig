const std = @import("std");
const ArrayList = std.ArrayList;

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

pub fn pushMessagePack(lua: *Lua, event: MessagePackBuffer) !void {
    _ = lua;
    _ = event;
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
