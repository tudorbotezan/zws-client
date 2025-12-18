# zws-client

A high-performance, standalone WebSocket client library for Zig.

**Target Zig Version:** 0.15.2 (Compatible with the latest I/O and `std.ArrayList` changes)

## Key Features

- **`WebSocketClient`**: Lightweight, non-blocking client for `ws://` connections.
- **`TlsWebSocketClient`**: Secure `wss://` client with **full CA certificate verification** via `std.crypto.tls`.
- **Zero External Dependencies**: Core WebSocket logic is fully vendored and patched for the latest Zig toolchain.
- **Non-blocking I/O**: Designed for integration into event loops or simple polling structures.
- **Memory Efficient**: Uses the latest Zig 0.15.2 patterns for explicit memory management.

## Installation

Add `zws-client` to your `build.zig.zon`:

```sh
zig fetch --save https://github.com/tudorbotezan/zws-client/archive/v0.0.1.tar.gz
```

Then in your `build.zig`:

```zig
const zws = b.dependency("zws-client", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zws-client", zws.module("zws-client"));
```

## Usage Example

The following example demonstrates a basic connection and message loop using the non-blocking API:

```zig
const std = @import("std");
const zws = @import("zws-client");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize the client (non-TLS)
    var client = zws.WebSocketClient.init(allocator, "ws://echo.websocket.org");
    defer client.deinit();

    // OR initialize with TLS (Secure)
    // var client = zws.TlsWebSocketClient.init(allocator, "wss://echo.websocket.org", null);
    // Note: Passing null for the CA bundle will cause it to load system roots automatically.

    // Connect (blocking handshake)
    try client.connect();
    
    // Send a message
    try client.sendText("Hello from Zig!");

    // Polling Receive Loop
    while (true) {
        if (try client.receive()) |payload| {
            std.debug.print("Received: {s}\n", .{payload});
            allocator.free(payload);
            break;
        }
        // Small sleep to avoid pegged CPU in a simple example
        std.time.sleep(10 * std.time.ns_per_ms);
    }
}
```

## Building

```bash
# Build the static library
zig build

# Run internal and integration tests
zig build test --summary all
```

The static library artifact will be generated in `zig-out/lib/`.

## Changelog

### v0.0.1

- **Initial Release for Zig 0.15.2**: Full migration to the new standard library I/O and `ArrayList` unmanaged APIs.
- **Vendored Core**: Integrated and patched the dependency logic into `src/vendor/ws/`.
- **BitReader Polyfill**: Custom implementation added to replace the removed `std.io.BitReader`.
- **Compression**: `per_message_deflate` is currently stubbed for stability due to `std.compress.flate` overhauls.

## License

MIT License – see the `LICENSE` file for details.
