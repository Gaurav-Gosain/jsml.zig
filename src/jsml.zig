//! A simple JSON parser written in Zig, for learning purposes.

const std = @import("std");
/// The allocator used to allocate memory for storing JSON nodes.
const Allocator = std.mem.Allocator;

/// The JSON enum used later as part of a tagged union to represent the type of a JSON value.
pub const JsonType = enum {
    Null,
    Object,
    Array,
    String,
    Integer,
    Double,
    Bool,
};

/// A simple JSON parser written in Zig, for learning purposes.
///
/// This is used to represent a JSON value when parsing.
///
/// For example, if you have a JSON string like this:
///
/// ```json
/// {
///     "name": "John",
///     "age": 30,
///     "address": {
///         "street": "123 Main St",
///         "city": "Anytown"
///     }
/// }
/// ```
///
/// You can create a `Json` node by calling `Json.parse(allocator, text)`.
///
/// This will parse the JSON string and create a `Json` node.
///
/// You can then access the values of the JSON node using the getter functions.
///
/// For example, to get the `name` value, you can call `json.get("name")`.
///
/// This will return a pointer to the `Json` node with the `name` value.
///
/// You can then access the value of the `name` node using the `value` field.
///
/// For example, to get the `name` value as a string, you can call `json.get("name").?.value.string`.
///
/// Remember to call `deinit` on the returned `Json` when you're done with it to free the memory.
///
/// ## Usage Example
///
/// ```zig
/// const std = @import("std");
/// const Json = @import("jsml.zig").Json;
///
/// pub fn main() !void {
///     var gpa = std.heap.GeneralPurposeAllocator(.{
///         .safety = true,
///         .verbose_log = false, // change to true for debugging
///     }){};
///
///     defer {
///         if (gpa.deinit() == .leak) {
///             std.io.getStdOut().writeAll("[CRITICAL] leaked memory\n") catch unreachable;
///         } else {
///             std.io.getStdOut().writeAll("[GG] all memory cleaned up! No Leaks\n") catch unreachable;
///         }
///     }
///
///     const allocator = gpa.allocator();
///
///     // Example 1: Parse from string
///     const json_str =
///         \\{
///         \\  "name": "John",
///         \\  "age": 30,
///         \\  "is_student": false,
///         \\  "grades": [85, 92, 78],
///         \\  "address": {
///         \\    "street": "123 Main St",
///         \\    "city": "Anytown"
///         \\  }
///         \\}
///     ;
///
///     std.debug.print("\n=== Parsing from string ===\n", .{});
///     var json = try Json.parse(allocator, json_str);
///     defer json.deinit();
///     json.print();
///     std.debug.print("json.city: {s}\n", .{json.getNested("address.city").?.value.string});
///     std.debug.print("json.grades[0]: {d}\n", .{json.getNested("grades.0").?.value.integer});
///
///     // Example 2: Parse from file
///     std.debug.print("\n=== Parsing from file ===\n", .{});
///
///     const file_path = try std.fs.path.join(allocator, &[_][]const u8{
///         std.fs.path.dirname(@src().file) orelse ".",
///         "example.json",
///     });
///     defer allocator.free(file_path);
///
///     var file_json = try Json.parseFile(allocator, file_path);
///     defer file_json.deinit();
///     file_json.print();
///     std.debug.print(
///         "file_json.nested[2].a[0]: {d}\n",
///         .{
///             file_json
///                 .getNested("nested.2.a.0").?
///                 .value.integer,
///         },
///     );
/// }
/// ```
pub const Json = struct {
    type: JsonType,
    key: ?[]const u8,
    value: Value,
    children: std.ArrayList(*Json),
    allocator: Allocator,

    /// The value of a JSON node.
    ///
    /// This is used to represent the value of a JSON value when parsing.
    pub const Value = union(enum) {
        none: void,
        string: []const u8,
        integer: i64,
        double: f64,
        boolean: bool,
    };

    /// Initializes a new JSON node.
    ///
    /// This is used to create a new JSON node when parsing.
    /// It takes an allocator as an argument, which is used to allocate memory for the node.
    /// Remember to call `deinit` on the node when you're done with it to free the memory.
    pub fn init(allocator: Allocator) !*Json {
        const json = try allocator.create(Json);
        json.* = .{
            .type = .Null,
            .key = null,
            .value = .{ .none = {} },
            .children = std.ArrayList(*Json).init(allocator),
            .allocator = allocator,
        };
        return json;
    }

    /// Deinitializes a JSON node.
    ///
    /// This is used to free the memory allocated for a JSON node when parsing.
    pub fn deinit(self: *Json) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit();
        if (self.key) |k| {
            self.allocator.free(k);
        }
        switch (self.value) {
            .string => |s| self.allocator.free(s),
            else => {},
        }
        self.allocator.destroy(self);
    }

    /// Parses a JSON string.
    ///
    /// This is used to parse a JSON string and create a JSON node.
    /// It takes an allocator and a text as arguments, and returns a pointer to the created JSON node.
    /// Remember to call `deinit` on the returned `Json` when you're done with it to free the memory.
    pub fn parse(allocator: Allocator, text: []const u8) !*Json {
        var parser = Parser.init(allocator);
        return parser.parse(text);
    }

    /// Parses a JSON file.
    ///
    /// This is used to parse a JSON file and create a JSON node.
    /// It takes an allocator and a path as arguments, and returns a pointer to the created JSON node.
    /// Remember to call `deinit` on the returned `Json` when you're done with it to free the memory.
    pub fn parseFile(allocator: Allocator, path: []const u8) !*Json {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(content);

        return parse(allocator, content);
    }

    /// Gets a JSON node by key.
    ///
    /// This is used to get a JSON node by key.
    /// It takes a pointer to a JSON node and a key as arguments,
    /// and returns a pointer to the JSON node with the given key.
    /// If the key is not found, it returns `null`.
    ///
    /// For example, if you have a JSON node with the following structure:
    /// ```json
    /// {
    ///     "name": "John",
    ///     "age": 30,
    ///     "address": {
    ///         "street": "123 Main St",
    ///         "city": "Anytown"
    ///     }
    /// }
    /// ```
    /// You can get the `age` node by calling `get("age")`.
    pub fn get(self: *const Json, key: []const u8) ?*Json {
        for (self.children.items) |child| {
            if (child.key) |k| {
                if (std.mem.eql(u8, k, key)) {
                    return child;
                }
            }
        }
        return null;
    }

    /// Gets a JSON node by path.
    ///
    /// Useful for getting nested JSON nodes.
    /// NOTE: This function assumes that the JSON keys are not integers or contain dots.
    ///
    /// For example, if you have a JSON node with the following structure:
    /// ```json
    /// {
    ///     "name": "John",
    ///     "age": 30,
    ///     "address": {
    ///         "street": "123 Main St",
    ///         "city": "Anytown",
    ///         "nested": [
    ///             {
    ///                 "a": "b"
    ///             },
    ///             {
    ///                 "a": 69
    ///             },
    ///             {
    ///                 "a": [4, 2, 0]
    ///             }
    ///         ]
    ///     }
    /// }
    /// ```
    /// You can get the `city` node by calling `getNested("address.city")`.
    /// A more complex example would be `getNested("address.nested.2.a.0")`.
    /// It takes a pointer to a JSON node and a path as arguments,
    /// and returns a pointer to the JSON node with the given path.
    /// If the path is not found, it returns `null`.
    pub fn getNested(self: *const Json, path: []const u8) ?*const Json {
        var current: ?*const Json = self;
        var it = std.mem.split(u8, path, ".");

        while (it.next()) |key| {
            if (current) |c| {
                if (std.fmt.parseInt(usize, key, 10) catch null) |num| {
                    if (c.children.items.len > num) {
                        current = c.children.items[num];
                    } else {
                        return null;
                    }
                } else {
                    current = c.get(key);
                }
            } else {
                return null;
            }
        }

        return if (current) |c| c else null;
    }

    /// Internal function to get a JSON node by index.
    pub fn getIndex(self: *const Json, index: usize) ?*Json {
        return if (index < self.children.items.len)
            self.children.items[index]
        else
            null;
    }

    /// Prints the JSON node recursively.
    pub fn print(self: *const Json) void {
        recursivePrint(self, 0);
    }

    /// Internal function to print the JSON node recursively.
    fn recursivePrint(self: *const Json, depth: usize) void {
        for (self.children.items) |child| {
            // Print the tree branches
            if (depth == 0) {
                std.debug.print("┼──", .{});
            } else {
                for (0..depth + 1) |_| {
                    std.debug.print("┼──", .{});
                }
            }

            // Print the key if it exists
            if (child.key) |key| {
                std.debug.print(" {s}: ", .{key});
            } else {
                std.debug.print(" ", .{});
            }

            // Print the value based on type
            switch (child.type) {
                .Null => std.debug.print("NULL\n", .{}),
                .Object => {
                    std.debug.print("OBJECT\n", .{});
                    child.recursivePrint(depth + 1);
                },
                .Array => {
                    std.debug.print("ARRAY\n", .{});
                    child.recursivePrint(depth + 1);
                },
                .String => std.debug.print("{s} (string)\n", .{child.value.string}),
                .Integer => std.debug.print("{d} (int)\n", .{child.value.integer}),
                .Double => std.debug.print("{d} (double)\n", .{child.value.double}),
                .Bool => std.debug.print("{s} (bool)\n", .{if (child.value.boolean) "true" else "false"}),
            }
        }
    }
};

/// The main parser struct, contains the logic for parsing JSON.
const Parser = struct {
    allocator: Allocator,
    pos: usize,
    text: []const u8,

    /// Initializes a new parser.
    pub fn init(allocator: Allocator) Parser {
        return .{
            .allocator = allocator,
            .pos = 0,
            .text = "",
        };
    }

    /// Internal function to skip whitespace.
    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.text.len and std.ascii.isWhitespace(self.text[self.pos])) {
            self.pos += 1;
        }
    }

    /// Internal function to parse a JSON string.
    fn parseString(self: *Parser) ![]const u8 {
        if (self.pos >= self.text.len or self.text[self.pos] != '"') {
            return error.InvalidJson;
        }
        self.pos += 1;

        const start = self.pos;
        var escaped = false;
        while (self.pos < self.text.len) {
            const c = self.text[self.pos];
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                const str = try self.allocator.dupe(u8, self.text[start..self.pos]);
                self.pos += 1;
                return str;
            }
            self.pos += 1;
        }
        return error.InvalidJson;
    }

    /// Internal function to parse a JSON number.
    fn parseNumber(self: *Parser) !Json.Value {
        const start = self.pos;
        var has_decimal = false;

        while (self.pos < self.text.len) {
            const c = self.text[self.pos];
            if ((c == '.') or (c == 'e') or (c == 'E')) {
                has_decimal = true;
            } else if (!std.ascii.isDigit(c) and c != '-' and c != 'e' and c != 'E' and c != '+') {
                break;
            }
            self.pos += 1;
        }

        const num_str = self.text[start..self.pos];
        if (has_decimal) {
            const value = try std.fmt.parseFloat(f64, num_str);
            return Json.Value{ .double = value };
        } else {
            const value = try std.fmt.parseInt(i64, num_str, 10);
            return Json.Value{ .integer = value };
        }
    }

    /// Parses a JSON string.
    pub fn parse(self: *Parser, text: []const u8) !*Json {
        self.text = text;
        self.pos = 0;
        return self.parseValue();
    }

    /// Internal function to parse a JSON value.
    fn parseValue(self: *Parser) !*Json {
        self.skipWhitespace();
        if (self.pos >= self.text.len) {
            return error.InvalidJson;
        }

        const json = try Json.init(self.allocator);
        const c = self.text[self.pos];

        switch (c) {
            '{' => {
                json.type = .Object;
                self.pos += 1;
                while (true) {
                    self.skipWhitespace();
                    if (self.pos >= self.text.len) {
                        return error.InvalidJson;
                    }
                    if (self.text[self.pos] == '}') {
                        self.pos += 1;
                        break;
                    }
                    if (json.children.items.len > 0) {
                        if (self.text[self.pos] != ',') {
                            return error.InvalidJson;
                        }
                        self.pos += 1;
                        self.skipWhitespace();
                    }

                    const key = try self.parseString();
                    self.skipWhitespace();
                    if (self.pos >= self.text.len or self.text[self.pos] != ':') {
                        return error.InvalidJson;
                    }
                    self.pos += 1;

                    var child = try self.parseValue();
                    child.key = key;
                    try json.children.append(child);
                }
            },
            '[' => {
                json.type = .Array;
                self.pos += 1;
                while (true) {
                    self.skipWhitespace();
                    if (self.pos >= self.text.len) {
                        return error.InvalidJson;
                    }
                    if (self.text[self.pos] == ']') {
                        self.pos += 1;
                        break;
                    }
                    if (json.children.items.len > 0) {
                        if (self.text[self.pos] != ',') {
                            return error.InvalidJson;
                        }
                        self.pos += 1;
                    }
                    const child = try self.parseValue();
                    try json.children.append(child);
                }
            },
            '"' => {
                json.type = .String;
                json.value = .{ .string = try self.parseString() };
            },
            't' => {
                if (self.pos + 3 >= self.text.len or !std.mem.eql(u8, "true", self.text[self.pos .. self.pos + 4])) {
                    return error.InvalidJson;
                }
                json.type = .Bool;
                json.value = .{ .boolean = true };
                self.pos += 4;
            },
            'f' => {
                if (self.pos + 4 >= self.text.len or !std.mem.eql(u8, "false", self.text[self.pos .. self.pos + 5])) {
                    return error.InvalidJson;
                }
                json.type = .Bool;
                json.value = .{ .boolean = false };
                self.pos += 5;
            },
            'n' => {
                if (self.pos + 3 >= self.text.len or !std.mem.eql(u8, "null", self.text[self.pos .. self.pos + 4])) {
                    return error.InvalidJson;
                }
                json.type = .Null;
                json.value = .{ .none = {} };
                self.pos += 4;
            },
            else => {
                if (std.ascii.isDigit(c) or c == '-') {
                    const value = try self.parseNumber();
                    // Now we can just check the value type directly
                    json.type = switch (value) {
                        .integer => .Integer,
                        .double => .Double,
                        else => unreachable,
                    };
                    json.value = value;
                } else {
                    return error.InvalidJson;
                }
            },
        }
        return json;
    }
};
