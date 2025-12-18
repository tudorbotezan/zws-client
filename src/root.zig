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
