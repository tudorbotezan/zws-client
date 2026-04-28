const std = @import("std");
const mem = std.mem;

pub fn GenericReader(
    comptime Context: type,
    comptime ReadError: type,
    comptime readFn: fn (context: Context, buffer: []u8) ReadError!usize,
) type {
    return struct {
        context: Context,

        const Self = @This();
        pub const Error = ReadError;

        pub fn read(self: Self, buffer: []u8) Error!usize {
            return readFn(self.context, buffer);
        }

        pub fn readByte(self: Self) (Error || error{EndOfStream})!u8 {
            var byte: [1]u8 = undefined;
            const n = try self.read(&byte);
            if (n == 0) return error.EndOfStream;
            return byte[0];
        }

        pub fn readUntilDelimiterAlloc(
            self: Self,
            allocator: mem.Allocator,
            delimiter: u8,
            max_size: usize,
        ) (Error || error{ EndOfStream, StreamTooLong, OutOfMemory })![]u8 {
            var list: std.ArrayList(u8) = .empty;
            defer list.deinit(allocator);

            while (list.items.len < max_size) {
                const byte = try self.readByte();
                if (byte == delimiter) return try list.toOwnedSlice(allocator);
                try list.append(allocator, byte);
            }

            return error.StreamTooLong;
        }
    };
}

pub fn GenericWriter(
    comptime Context: type,
    comptime WriteError: type,
    comptime writeFn: fn (context: Context, bytes: []const u8) WriteError!usize,
) type {
    return struct {
        context: Context,

        const Self = @This();
        pub const Error = WriteError;

        pub fn write(self: Self, bytes: []const u8) Error!usize {
            return writeFn(self.context, bytes);
        }

        pub fn writeAll(self: Self, bytes: []const u8) (Error || error{NoSpaceLeft})!void {
            var index: usize = 0;
            while (index < bytes.len) {
                const n = try self.write(bytes[index..]);
                if (n == 0) return error.NoSpaceLeft;
                index += n;
            }
        }
    };
}

pub fn fixedBufferStream(buffer: anytype) FixedBufferStream(Slice(@TypeOf(buffer))) {
    return .{ .buffer = asSlice(buffer) };
}

fn FixedBufferStream(comptime Buffer: type) type {
    return struct {
        buffer: Buffer,
        pos: usize = 0,

        const Self = @This();
        pub const ReadError = error{};
        pub const WriteError = error{NoSpaceLeft};
        pub const Reader = GenericReader(*Self, ReadError, read);
        pub const Writer = GenericWriter(*Self, WriteError, write);

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn read(self: *Self, dest: []u8) ReadError!usize {
            const size = @min(dest.len, self.buffer.len - self.pos);
            const end = self.pos + size;
            mem.copyForwards(u8, dest[0..size], self.buffer[self.pos..end]);
            self.pos = end;
            return size;
        }

        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            comptime {
                if (@typeInfo(Buffer).pointer.is_const) {
                    @compileError("cannot write to a const fixed buffer stream");
                }
            }

            if (bytes.len == 0) return 0;
            if (self.pos >= self.buffer.len) return error.NoSpaceLeft;

            const n = @min(bytes.len, self.buffer.len - self.pos);
            mem.copyForwards(u8, self.buffer[self.pos .. self.pos + n], bytes[0..n]);
            self.pos += n;
            return n;
        }
    };
}

fn Slice(comptime Buffer: type) type {
    const info = @typeInfo(Buffer);
    if (info != .pointer) @compileError("fixedBufferStream expects a pointer or slice");

    const ptr = info.pointer;
    return switch (ptr.size) {
        .slice => Buffer,
        .one => switch (@typeInfo(ptr.child)) {
            .array => |array| if (ptr.is_const) []const array.child else []array.child,
            else => @compileError("fixedBufferStream expects a pointer to an array or a slice"),
        },
        else => @compileError("fixedBufferStream expects a pointer to an array or a slice"),
    };
}

fn asSlice(buffer: anytype) Slice(@TypeOf(buffer)) {
    const Buffer = @TypeOf(buffer);
    const ptr = @typeInfo(Buffer).pointer;
    return switch (ptr.size) {
        .slice => buffer,
        .one => buffer[0..],
        else => unreachable,
    };
}
