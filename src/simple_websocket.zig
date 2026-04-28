const std = @import("std");
const net = std.Io.net;

// Minimal WebSocket client for Zig 0.16.0 compatibility
pub const SimpleWebSocketClient = struct {
    allocator: std.mem.Allocator,
    io_threaded: std.Io.Threaded,
    tcp_client: ?net.Stream = null,
    connected: bool = false,
    url: []const u8,

    pub fn init(allocator: std.mem.Allocator, url: []const u8, ca_bundle: ?std.crypto.Certificate.Bundle) SimpleWebSocketClient {
        _ = ca_bundle; // CA bundle parameter kept for API compatibility
        return .{
            .allocator = allocator,
            .io_threaded = .init(allocator, .{}),
            .url = url,
        };
    }

    fn io(self: *SimpleWebSocketClient) std.Io {
        return self.io_threaded.io();
    }

    fn writeAll(self: *SimpleWebSocketClient, bytes: []const u8) !void {
        var write_buffer: [4096]u8 = undefined;
        var writer = self.tcp_client.?.writer(self.io(), &write_buffer);
        writer.interface.writeAll(bytes) catch |err| return writer.err orelse err;
        writer.interface.flush() catch |err| return writer.err orelse err;
    }

    fn read(self: *SimpleWebSocketClient, buffer: []u8) !usize {
        var read_buffer: [4096]u8 = undefined;
        var reader = self.tcp_client.?.reader(self.io(), &read_buffer);
        return reader.interface.readSliceShort(buffer) catch |err| return reader.err orelse err;
    }

    pub fn connect(self: *SimpleWebSocketClient) !void {
        const uri = try std.Uri.parse(self.url);

        // Only support ws:// for now
        if (!std.mem.eql(u8, uri.scheme, "ws")) {
            return error.UnsupportedScheme;
        }

        var host_buffer: [net.HostName.max_len]u8 = undefined;
        const host = uri.getHost(&host_buffer) catch return error.InvalidUrl;
        const port: u16 = if (uri.port) |p| p else 80;

        self.tcp_client = try host.connect(self.io(), port, .{ .mode = .stream });

        // Simple WebSocket handshake
        var req_buf: [1024]u8 = undefined;
        const path_str = if (uri.path.isEmpty()) "/" else switch (uri.path) {
            .raw => |p| p,
            .percent_encoded => |p| p,
        };
        const request = try std.fmt.bufPrint(&req_buf, "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
            "\r\n", .{ path_str, host.bytes });

        try self.writeAll(request);

        // Read response (simplified)
        var resp_buffer: [1024]u8 = undefined;
        const bytes_read = self.read(&resp_buffer) catch |err| {
            std.debug.print("WebSocket handshake failed: {}\n", .{err});
            return err;
        };

        // Check for successful upgrade response
        if (bytes_read > 0 and std.mem.indexOf(u8, resp_buffer[0..bytes_read], "101") != null) {
            self.connected = true;
            std.debug.print("WebSocket connected successfully!\n", .{});
        } else {
            return error.HandshakeFailed;
        }
    }

    pub fn sendText(self: *SimpleWebSocketClient, text: []const u8) !void {
        if (!self.connected or self.tcp_client == null) {
            return error.NotConnected;
        }

        // For now, just log the message
        std.debug.print("[WS] Would send: {s}\n", .{text});

        // TODO: Implement proper WebSocket frame encoding
        try self.writeAll(text);
    }

    pub fn receive(self: *SimpleWebSocketClient) !?[]const u8 {
        if (!self.connected or self.tcp_client == null) {
            return error.NotConnected;
        }

        var buffer: [4096]u8 = undefined;

        const bytes_read = try self.read(&buffer);
        if (bytes_read == 0) {
            self.connected = false;
            return null;
        }

        // Return the raw data for compatibility
        const text_copy = try self.allocator.dupe(u8, buffer[0..bytes_read]);
        return text_copy;
    }

    pub fn close(self: *SimpleWebSocketClient) void {
        if (self.tcp_client) |tcp| {
            tcp.close(self.io());
            self.tcp_client = null;
        }
        self.connected = false;
    }

    pub fn deinit(self: *SimpleWebSocketClient) void {
        self.close();
        self.io_threaded.deinit();
    }
};

// Error types
pub const WebSocketError = error{
    UnsupportedScheme,
    InvalidUrl,
    NotConnected,
    HandshakeFailed,
};

const SimpleWebSocketClientType = @This();

// Make it compatible with the expected interface
pub const WebSocketClient = SimpleWebSocketClient;
