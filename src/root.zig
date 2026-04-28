const std = @import("std");

pub const WebSocketClient = @import("websocket_client.zig").WebSocketClient;
pub const TlsWebSocketClient = @import("websocket_tls.zig").TlsWebSocketClient;

test {
    _ = WebSocketClient;
    _ = TlsWebSocketClient;

    // Include tests from submodules
    _ = @import("websocket_client.zig");
    _ = @import("websocket_tls.zig");
}

test "clients reject unsupported schemes" {
    var plain = WebSocketClient.init(std.testing.allocator, "http://example.com", null);
    defer plain.deinit();
    try std.testing.expectError(error.UnsupportedScheme, plain.connect());

    var secure = TlsWebSocketClient.init(std.testing.allocator, "https://example.com", null);
    defer secure.deinit();
    try std.testing.expectError(error.UnsupportedScheme, secure.connect());
}
