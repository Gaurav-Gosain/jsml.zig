const std = @import("std");
const Json = @import("jsml.zig").Json;

test "parse basic types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test string
    {
        const json_str = "\"hello world\"";
        const json = try Json.parse(allocator, json_str);
        try std.testing.expectEqual(json.type, .String);
        try std.testing.expectEqualStrings(json.value.string, "hello world");
    }

    // Test integer
    {
        const json_str = "42";
        const json = try Json.parse(allocator, json_str);
        try std.testing.expectEqual(json.type, .Integer);
        try std.testing.expectEqual(json.value.integer, 42);
    }

    // Test negative integer
    {
        const json_str = "-42";
        const json = try Json.parse(allocator, json_str);
        try std.testing.expectEqual(json.type, .Integer);
        try std.testing.expectEqual(json.value.integer, -42);
    }

    // Test double
    {
        const json_str = "42.5";
        const json = try Json.parse(allocator, json_str);
        try std.testing.expectEqual(json.type, .Double);
        try std.testing.expectEqual(json.value.double, 42.5);
    }

    // Test boolean true
    {
        const json_str = "true";
        const json = try Json.parse(allocator, json_str);
        try std.testing.expectEqual(json.type, .Bool);
        try std.testing.expectEqual(json.value.boolean, true);
    }

    // Test boolean false
    {
        const json_str = "false";
        const json = try Json.parse(allocator, json_str);
        try std.testing.expectEqual(json.type, .Bool);
        try std.testing.expectEqual(json.value.boolean, false);
    }

    // Test null
    {
        const json_str = "null";
        const json = try Json.parse(allocator, json_str);
        try std.testing.expectEqual(json.type, .Null);
    }
}

test "parse array" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json_str = "[1, \"test\", true, null, 3.14]";
    const json = try Json.parse(allocator, json_str);

    try std.testing.expectEqual(json.type, .Array);
    try std.testing.expectEqual(json.children.items.len, 5);

    const items = json.children.items;
    try std.testing.expectEqual(items[0].type, .Integer);
    try std.testing.expectEqual(items[0].value.integer, 1);

    try std.testing.expectEqual(items[1].type, .String);
    try std.testing.expectEqualStrings(items[1].value.string, "test");

    try std.testing.expectEqual(items[2].type, .Bool);
    try std.testing.expectEqual(items[2].value.boolean, true);

    try std.testing.expectEqual(items[3].type, .Null);

    try std.testing.expectEqual(items[4].type, .Double);
    try std.testing.expectEqual(items[4].value.double, 3.14);
}

test "parse object" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

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

    var json = try Json.parse(allocator, json_str);
    try std.testing.expectEqual(json.type, .Object);

    // Test name
    if (json.get("name")) |name| {
        try std.testing.expectEqual(name.type, .String);
        try std.testing.expectEqualStrings(name.value.string, "John");
    } else {
        return error.TestUnexpectedNull;
    }

    // Test age
    if (json.get("age")) |age| {
        try std.testing.expectEqual(age.type, .Integer);
        try std.testing.expectEqual(age.value.integer, 30);
    } else {
        return error.TestUnexpectedNull;
    }

    // Test nested array
    if (json.get("grades")) |grades| {
        try std.testing.expectEqual(grades.type, .Array);
        try std.testing.expectEqual(grades.children.items.len, 3);
        try std.testing.expectEqual(grades.children.items[0].value.integer, 85);
        try std.testing.expectEqual(grades.children.items[1].value.integer, 92);
        try std.testing.expectEqual(grades.children.items[2].value.integer, 78);
    } else {
        return error.TestUnexpectedNull;
    }

    // Test nested object
    if (json.get("address")) |address| {
        try std.testing.expectEqual(address.type, .Object);
        if (address.get("street")) |street| {
            try std.testing.expectEqual(street.type, .String);
            try std.testing.expectEqualStrings(street.value.string, "123 Main St");
        } else {
            return error.TestUnexpectedNull;
        }
    } else {
        return error.TestUnexpectedNull;
    }
}

test "parse nested path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json_str =
        \\{
        \\  "user": {
        \\    "profile": {
        \\      "name": {
        \\        "first": "John",
        \\        "last": "Doe"
        \\      }
        \\    }
        \\  }
        \\}
    ;

    var json = try Json.parse(allocator, json_str);

    // Test nested path access
    if (json.getNested("user.profile.name.first")) |first_name| {
        try std.testing.expectEqual(first_name.type, .String);
        try std.testing.expectEqualStrings(first_name.value.string, "John");
    } else {
        return error.TestUnexpectedNull;
    }

    // Test invalid path
    try std.testing.expectEqual(json.getNested("user.invalid.path"), null);
}
