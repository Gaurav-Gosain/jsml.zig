const std = @import("std");
const Json = @import("jsml.zig").Json;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
        .verbose_log = false, // change to true for debugging
    }){};

    defer {
        if (gpa.deinit() == .leak) {
            std.io.getStdOut().writeAll("[CRITICAL] leaked memory\n") catch unreachable;
        } else {
            std.io.getStdOut().writeAll("[GG] all memory cleaned up! No Leaks\n") catch unreachable;
        }
    }

    const allocator = gpa.allocator();

    // Example 1: Parse from string
    const json_str =
        \\{
        \\  "name": "John",
        \\  "age": 30,
        \\  "is_student": false,
        \\  "grades": [85, 92, 78],
        \\  "address": {
        \\    "street": "123 Main St",
        \\    "city": "Anytown"
        \\  }
        \\}
    ;

    std.debug.print("\n=== Parsing from string ===\n", .{});
    var json = try Json.parse(allocator, json_str);
    defer json.deinit();
    json.print();
    std.debug.print("json.city: {s}\n", .{json.getNested("address.city").?.value.string});
    std.debug.print("json.grades[0]: {d}\n", .{json.getNested("grades.0").?.value.integer});

    // Example 2: Parse from file
    std.debug.print("\n=== Parsing from file ===\n", .{});

    const file_path = try std.fs.path.join(allocator, &[_][]const u8{
        std.fs.path.dirname(@src().file) orelse ".",
        "example.json",
    });
    defer allocator.free(file_path);

    var file_json = try Json.parseFile(allocator, file_path);
    defer file_json.deinit();
    file_json.print();
    std.debug.print(
        "file_json.nested[2].a[0]: {d}\n",
        .{
            file_json
                .getNested("nested.2.a.0").?
                .value.integer,
        },
    );

    // Example 3: Parse from http response
    std.debug.print("\n=== Parsing from http response ===\n", .{});

    // Create a HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // example usage of get (on a nested object)
    const url = try std.fmt.allocPrint(
        allocator,
        "https://api.github.com/users?per_page={s}&since={d}",
        .{
            file_json.getNested("obj.per-page").?.value.string,
            file_json.getNested("obj.since").?.value.integer,
        },
    );
    defer allocator.free(url);

    const uri = try std.Uri.parse(url);

    // Refer to https://github.com/tigerbeetle/tigerbeetle/blob/b4f3d165657dce10715b1aa6e7718f45298a1465/src/shell.zig#L886
    var buf: [4 << 10]u8 = undefined;

    var req = try client.open(.GET, uri, .{
        .server_header_buffer = &buf,
    });
    defer req.deinit();

    // Send the request
    try req.send();
    try req.finish();
    try req.wait();

    if (req.response.status != .ok) {
        return error.HttpError;
    }

    const response_body_size_max = 512 << 10;
    const response = try req.reader().readAllAlloc(allocator, response_body_size_max);
    defer allocator.free(response);

    // Parse the response body
    var http_json = try Json.parse(allocator, response);
    defer http_json.deinit();
    http_json.print();
}
