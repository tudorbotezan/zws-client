const std = @import("std");

// Re-export the simple implementation for compatibility
pub const WebSocketClient = @import("simple_websocket.zig").WebSocketClient;
pub const SimpleWebSocketClient = @import("simple_websocket.zig").SimpleWebSocketClient;