const std = @import("std");
const ziglua = @import("ziglua");
const sanctum = @import("libsanctum");

const Lua = ziglua.Lua;

pub fn main() !void {
    // Create an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize the Lua vm
    var lua = try Lua.init(allocator);
    defer lua.deinit();

    // Add an integer to the Lua stack and retrieve it
    lua.pushInteger(42);
    std.debug.print("{}\n", .{try lua.toInteger(1)});
}
