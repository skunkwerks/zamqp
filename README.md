zamqp is a Zig wrapper around [rabbitmq-c](https://github.com/alanxz/rabbitmq-c).

## Setup
1. Install `librabbitmq`.
2. Add the following to your `build.zig` (you may need to adjust the path):
    ```zig
    step.linkLibC();
    step.linkSystemLibrary("rabbitmq");
    step.addPackagePath("zamqp", "../zamqp/src/zamqp.zig");
    ```
3. Import with `@import("zamqp")`.
