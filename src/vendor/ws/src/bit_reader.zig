const std = @import("std");

pub fn BitReader(comptime endian: std.builtin.Endian, comptime ReaderType: type) type {
    return struct {
        reader: ReaderType,
        bit_buffer: u8 = 0,
        bit_count: u4 = 0,

        const Self = @This();

        pub fn init(reader: ReaderType) Self {
            return .{ .reader = reader };
        }

        pub fn readBitsNoEof(self: *Self, comptime T: type, bits: usize) !T {
            if (bits == 0) return 0;
            var result: T = 0;
            var bits_left = bits;

            while (bits_left > 0) {
                if (self.bit_count == 0) {
                    self.bit_buffer = try self.reader.readByte();
                    self.bit_count = 8;
                }

                const take = @min(bits_left, @as(usize, self.bit_count));
                const shift: u3 = @intCast(self.bit_count - @as(u4, @intCast(take)));
                const mask = @as(u8, @intCast((@as(u16, 1) << @as(u4, @intCast(take))) - 1));
                const val = (self.bit_buffer >> shift) & mask;

                if (endian == .big) {
                    if (@typeInfo(T).int.bits > 1) {
                        if (bits_left == bits) {
                            result = @as(T, @intCast(val));
                        } else {
                            result = (result << @as(std.math.Log2Int(T), @intCast(take))) | @as(T, @intCast(val));
                        }
                    } else {
                        result = @as(T, @intCast(val));
                    }
                } else {
                    @panic("Little endian not implemented in bit reader helper");
                }

                self.bit_count -= @as(u4, @intCast(take));
                bits_left -= take;
            }

            return result;
        }
    };
}

pub fn bitReader(comptime endian: std.builtin.Endian, reader: anytype) BitReader(endian, @TypeOf(reader)) {
    return BitReader(endian, @TypeOf(reader)).init(reader);
}
