const std = @import("std");

// Minimal WebSocket client for Zig 0.15.2 compatibility
pub const SimpleWebSocketClient = struct {
    allocator: std.mem.Allocator,
    tcp_client: ?std.net.Stream = null,
    connected: bool = false,
    url: []const u8,

    pub fn init(allocator: std.mem.Allocator, url: []const u8, ca_bundle: ?std.crypto.Certificate.Bundle) SimpleWebSocketClient {
        _ = ca_bundle; // CA bundle parameter kept for API compatibility
        return .{
            .allocator = allocator,
            .url = url,
        };
    }

    pub fn connect(self: *SimpleWebSocketClient) !void {
        const uri = try std.Uri.parse(self.url);
        
        // Only support ws:// for now
        if (!std.mem.eql(u8, uri.scheme, "ws")) {
            return error.UnsupportedScheme;
        }
        
        const host_component = uri.host orelse return error.InvalidUrl;
        const host = switch (host_component) {
            .raw => |h| h,
            .percent_encoded => |h| h,
        };
        const port: u16 = if (uri.port) |p| p else 80;

        self.tcp_client = try std.net.tcpConnectToHost(self.allocator, host, port);
        
        // Simple WebSocket handshake
        var req_buf: [1024]u8 = undefined;
        const path_str = if (uri.path.isEmpty()) "/" else switch (uri.path) {
            .raw => |p| p,
            .percent_encoded => |p| p,
        };
        const request = try std.fmt.bufPrint(&req_buf,
            "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
            "\r\n"
        , .{ path_str, host });
        
        _ = try self.tcp_client.?.write(request);
        
        // Read response (simplified)
        var resp_buffer: [1024]u8 = undefined;
        const bytes_read = self.tcp_client.?.read(&resp_buffer) catch |err| {
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
        _ = try self.tcp_client.?.write(text);
    }

    pub fn receive(self: *SimpleWebSocketClient) !?[]const u8 {
        if (!self.connected or self.tcp_client == null) {
            return error.NotConnected;
        }

        var buffer: [4096]u8 = undefined;
        
        const bytes_read = try self.tcp_client.?.read(&buffer);
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
            tcp.close();
            self.tcp_client = null;
        }
        self.connected = false;
    }

    pub fn deinit(self: *SimpleWebSocketClient) void {
        self.close();
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