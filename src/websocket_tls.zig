const std = @import("std");
const ws = @import("ws");
const net = std.Io.net;
const tls = std.crypto.tls;

pub const TlsWebSocketClient = struct {
    allocator: std.mem.Allocator,
    io_threaded: std.Io.Threaded,
    tcp_stream: ?net.Stream = null,
    stream_reader: ?net.Stream.Reader = null,
    stream_writer: ?net.Stream.Writer = null,
    tls_client: ?*tls.Client = null,
    ws_stream: ?ws.stream.Stream(TlsReader, TlsWriter) = null,
    ca_bundle_lock: std.Io.RwLock = .init,
    ca_bundle: std.crypto.Certificate.Bundle = .empty,
    owns_bundle: bool = false,
    socket_read_buffer: ?[]u8 = null,
    socket_write_buffer: ?[]u8 = null,
    tls_read_buffer: ?[]u8 = null,
    tls_write_buffer: ?[]u8 = null,
    connected: bool = false,
    url: []const u8,

    const Self = @This();

    // Wrapper types for TLS reader/writer
    const TlsReader = struct {
        tls_client: *tls.Client,

        pub const Error = anyerror; // Use generic error for now

        pub fn read(self: TlsReader, buffer: []u8) Error!usize {
            return self.tls_client.reader.readSliceShort(buffer) catch |err| switch (err) {
                error.ReadFailed => self.tls_client.read_err orelse err,
            };
        }

        pub fn readByte(self: TlsReader) !u8 {
            var byte: [1]u8 = undefined;
            const n = try self.read(&byte);
            if (n == 0) return error.EndOfStream;
            return byte[0];
        }

        pub fn readUntilDelimiterAlloc(
            self: TlsReader,
            allocator: std.mem.Allocator,
            delimiter: u8,
            max_size: usize,
        ) ![]u8 {
            var array_list: std.ArrayList(u8) = .empty;
            defer array_list.deinit(allocator);

            while (array_list.items.len < max_size) {
                const byte = try self.readByte();

                if (byte == delimiter) {
                    break;
                }

                try array_list.append(allocator, byte);
            }

            return array_list.toOwnedSlice(allocator);
        }
    };

    const TlsWriter = struct {
        tls_client: *tls.Client,

        pub const Error = anyerror; // Use generic error for now

        pub fn write(self: TlsWriter, buffer: []const u8) Error!usize {
            return self.tls_client.writer.write(buffer);
        }

        pub fn writeAll(self: TlsWriter, buffer: []const u8) Error!void {
            try self.tls_client.writer.writeAll(buffer);
            try self.tls_client.writer.flush();
        }
    };

    pub fn init(allocator: std.mem.Allocator, url: []const u8, ca_bundle: ?std.crypto.Certificate.Bundle) Self {
        return .{
            .allocator = allocator,
            .io_threaded = .init(allocator, .{}),
            .url = url,
            .ca_bundle = ca_bundle orelse .empty,
            .owns_bundle = ca_bundle == null,
        };
    }

    fn io(self: *Self) std.Io {
        return self.io_threaded.io();
    }

    pub fn connect(self: *Self) !void {
        const uri = try std.Uri.parse(self.url);
        if (!std.mem.eql(u8, uri.scheme, "wss")) {
            return error.UnsupportedScheme;
        }

        var host_buffer: [net.HostName.max_len]u8 = undefined;
        const host = uri.getHost(&host_buffer) catch return error.InvalidUrl;
        const port: u16 = uri.port orelse 443;
        const io_handle = self.io();

        std.debug.print("Connecting to {s}:{d} with TLS...\n", .{ host.bytes, port });

        // Connect TCP
        self.tcp_stream = try host.connect(io_handle, port, .{ .mode = .stream });
        errdefer {
            if (self.tcp_stream) |tcp| {
                tcp.close(self.io());
                self.tcp_stream = null;
            }
        }

        // Create TLS client
        self.tls_client = try self.allocator.create(tls.Client);
        errdefer {
            if (self.tls_client) |client| {
                self.allocator.destroy(client);
                self.tls_client = null;
            }
        }

        self.socket_read_buffer = try self.allocator.alloc(u8, tls.Client.min_buffer_len);
        errdefer self.freeBuffer(&self.socket_read_buffer);
        self.socket_write_buffer = try self.allocator.alloc(u8, tls.Client.min_buffer_len);
        errdefer self.freeBuffer(&self.socket_write_buffer);
        self.tls_read_buffer = try self.allocator.alloc(u8, tls.Client.min_buffer_len);
        errdefer self.freeBuffer(&self.tls_read_buffer);
        self.tls_write_buffer = try self.allocator.alloc(u8, tls.Client.min_buffer_len);
        errdefer self.freeBuffer(&self.tls_write_buffer);

        self.stream_reader = self.tcp_stream.?.reader(io_handle, self.socket_read_buffer.?);
        self.stream_writer = self.tcp_stream.?.writer(io_handle, self.tls_write_buffer.?);

        const now = std.Io.Clock.real.now(io_handle);
        if (self.owns_bundle) {
            try self.ca_bundle.rescan(self.allocator, io_handle, now);
        }

        var entropy: [tls.Client.Options.entropy_len]u8 = undefined;
        io_handle.random(&entropy);

        // Initialize TLS client with proper options
        const tls_options = tls.Client.Options{
            .host = .{ .explicit = host.bytes },
            .ca = .{ .bundle = .{
                .gpa = self.allocator,
                .io = io_handle,
                .lock = &self.ca_bundle_lock,
                .bundle = &self.ca_bundle,
            } },
            .read_buffer = self.tls_read_buffer.?,
            .write_buffer = self.socket_write_buffer.?,
            .entropy = &entropy,
            .realtime_now = now,
            .allow_truncation_attacks = true,
        };

        self.tls_client.?.* = tls.Client.init(&self.stream_reader.?.interface, &self.stream_writer.?.interface, tls_options) catch |err| {
            std.debug.print("TLS init error: {}\n", .{err});
            return switch (err) {
                error.WriteFailed => self.stream_writer.?.err orelse err,
                error.ReadFailed => self.stream_reader.?.err orelse err,
                else => err,
            };
        };

        // Create readers/writers for WebSocket
        const tls_reader = TlsReader{
            .tls_client = self.tls_client.?,
        };
        const tls_writer = TlsWriter{
            .tls_client = self.tls_client.?,
        };

        // Perform WebSocket handshake
        self.ws_stream = try ws.client(
            self.allocator,
            tls_reader,
            tls_writer,
            self.url,
        );

        self.connected = true;
        std.debug.print("TLS WebSocket connected!\n", .{});

        // Now set socket to non-blocking mode after handshake is complete.
        try setNonBlocking(self.tcp_stream.?.socket.handle);
    }

    pub fn sendText(self: *Self, text: []const u8) !void {
        if (!self.connected or self.ws_stream == null) {
            return error.NotConnected;
        }

        const message = ws.Message{
            .encoding = .text,
            .payload = text,
        };

        try self.ws_stream.?.sendMessage(message);
        // Don't print sent messages - let higher level code handle that
    }

    pub fn receive(self: *Self) !?[]const u8 {
        if (!self.connected or self.ws_stream == null) {
            return error.NotConnected;
        }

        // nextMessage() returns ?Message, not an error union
        if (self.ws_stream.?.nextMessage()) |msg| {
            defer msg.deinit();

            if (msg.encoding == .text) {
                const text_copy = try self.allocator.dupe(u8, msg.payload);
                return text_copy;
            }
        }

        // Check for errors on the stream
        if (self.ws_stream.?.err) |err| {
            // Handle non-blocking socket errors
            if (err == error.WouldBlock or err == error.Again) {
                return null; // No data available right now
            }
            // Don't print expected errors:
            // - WouldBlock/Again: expected in non-blocking mode
            // - TlsConnectionTruncated: normal disconnection
            // - ReservedOpcode: protocol-level error that doesn't affect functionality
            if (err != error.WouldBlock and err != error.Again and err != error.TlsConnectionTruncated and err != error.ReservedOpcode) {
                std.debug.print("WebSocket error: {}\n", .{err});
            }
            return err;
        }

        return null;
    }

    pub fn close(self: *Self) void {
        if (self.ws_stream) |*stream| {
            stream.deinit();
            self.ws_stream = null;
        }

        if (self.tls_client) |client| {
            // TLS Client doesn't have explicit deinit, just destroy the allocation
            self.allocator.destroy(client);
            self.tls_client = null;
        }

        if (self.tcp_stream) |tcp| {
            tcp.close(self.io());
            self.tcp_stream = null;
        }

        self.stream_reader = null;
        self.stream_writer = null;

        self.freeBuffer(&self.socket_read_buffer);
        self.freeBuffer(&self.socket_write_buffer);
        self.freeBuffer(&self.tls_read_buffer);
        self.freeBuffer(&self.tls_write_buffer);

        if (self.owns_bundle) {
            self.ca_bundle.deinit(self.allocator);
            self.ca_bundle = .empty;
        }

        self.connected = false;
    }

    pub fn deinit(self: *Self) void {
        self.close();
        self.io_threaded.deinit();
    }

    fn freeBuffer(self: *Self, buffer: *?[]u8) void {
        if (buffer.*) |slice| {
            self.allocator.free(slice);
            buffer.* = null;
        }
    }

    fn setNonBlocking(fd: std.posix.fd_t) !void {
        const builtin = @import("builtin");
        switch (builtin.os.tag) {
            .linux => {
                const linux = std.os.linux;
                const get_rc = linux.fcntl(fd, linux.F.GETFL, 0);
                switch (std.posix.errno(get_rc)) {
                    .SUCCESS => {},
                    else => return error.Unexpected,
                }

                var flags: std.posix.O = @bitCast(@as(u32, @intCast(get_rc)));
                flags.NONBLOCK = true;
                const set_rc = linux.fcntl(fd, linux.F.SETFL, @as(u32, @bitCast(flags)));
                switch (std.posix.errno(set_rc)) {
                    .SUCCESS => {},
                    else => return error.Unexpected,
                }
            },
            else => {},
        }
    }
};
