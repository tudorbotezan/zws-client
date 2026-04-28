# zws-client

A high-performance, standalone WebSocket client library for Zig.

**Target Zig Version:** 0.16.0

## Key Features

- **`WebSocketClient`**: Lightweight, non-blocking client for `ws://` connections.
- **`TlsWebSocketClient`**: Secure `wss://` client with **full CA certificate verification** via `std.crypto.tls`.
- **Zero External Dependencies**: Core WebSocket logic is fully vendored and patched for Zig 0.16.0.
- **Non-blocking I/O**: Designed for integration into event loops or simple polling structures.
- **Memory Efficient**: Uses Zig 0.16.0-compatible explicit memory management patterns.

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

For a side-by-side local Zig 0.16.0 toolchain without changing any global Zig install:

```bash
./.zig-toolchains/zig-x86_64-linux-0.16.0/zig build test --summary all
```

The static library artifact will be generated in `zig-out/lib/`.

## Changelog

### v0.0.1

- **Initial Release for Zig 0.16.0**: Full migration to the latest standard library I/O and `ArrayList` APIs.
- **Vendored Core**: Integrated and patched the dependency logic into `src/vendor/ws/`.
- **BitReader Polyfill**: Custom implementation added to replace the removed `std.io.BitReader`.
- **Compression**: `per_message_deflate` is currently stubbed for stability due to `std.compress.flate` overhauls.

## License

MIT License – see the `LICENSE` file for details.
