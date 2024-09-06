const std = @import("std");
const Allocator = std.mem.Allocator;

/// Using a list of structs merge the fields together into one default struct.
///
/// Returns:
/// - A normal struct containing fields of all structs.
///
/// Compile Errors:
/// - If at least 2 structs have the same field name.
pub fn MergeStruct(
    /// List of structs as types.
    comptime a: []const type,
) type {
    if (a.len == 1) {
        return a[0];
    }

    const prevMerge = @typeInfo(MergeStruct(a[1..])).Struct;
    const currMerge = @typeInfo(a[0]).Struct;

    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = currMerge.fields ++ prevMerge.fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

test "Merge 3 structs with MergeStruct" {
    const merge = MergeStruct(&.{
        struct {
            a: i32,
        },
        struct {
            b: u32,
            c: []const u8,
        },
        struct {
            d: bool,
        },
    });

    const expected = @typeInfo(struct {
        a: i32,
        b: u32,
        c: []const u8,
        d: bool,
    }).Struct;

    const actual = @typeInfo(merge).Struct;

    try comptime std.testing.expectEqualDeep(expected, actual);
}

/// Represents a argument
pub const Arg = struct {
    /// Argument name (used in the commandline)
    name: [:0]const u8,
    // Argument description
    desc: []const u8,
};

/// Convert arguments array into arguments struct.
///
/// Returns:
/// - A type representing the struct with arguments.
///
/// Compile Errors:
/// - If one of the arguments has an empty name.
fn BuildArgStruct(
    /// Type to use for argument.
    comptime T: type,
    /// Arguments array.
    comptime args: []const Arg,
) type {
    var fields: [args.len]std.builtin.Type.StructField = undefined;

    for (args, &fields) |arg, *field| {
        if (arg.name.len == 0) @compileError("Argument name can't be empty.");

        field.name = arg.name;
        field.alignment = 0;
        field.is_comptime = false;
        field.default_value = null;
        field.type = T;
    }

    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

test "BuildArgStruct does what is should do" {
    const Args = BuildArgStruct(u64, &.{
        Arg{ .name = "1", .desc = "a" },
        Arg{ .name = "y", .desc = "b" },
        Arg{ .name = "z", .desc = "c" },
    });

    const expected = @typeInfo(struct {
        @"1": u64,
        y: u64,
        z: u64,
    }).Struct;

    const actual = @typeInfo(Args).Struct;

    try comptime std.testing.expectEqualDeep(expected, actual);
}

// Error types created by the argument parser
pub const ParseError = error{
    UnknownValueOption,
    UnknownFlagOption,
    UnknownArgument,
    MissingPositionalOptions,
    MissingValueOptionAtEnd,
    InvalidOption,
    EmptyAfterDash,
};

/// Create a struct containing the wanted arguments with support methods.
///
/// Returns:
/// - A type with methods to aid in parsing the command line with the given arguments.
///
/// Compile Errors:
/// - If 2 or more arguments contain the same name
/// - If a argument has an empty name
/// - If a argument has a invalid name (struct field can't be named that way)
pub fn ArgStruct(
    /// Command for application
    comptime appName: []const u8,
    /// Description of the application
    comptime description: []const u8,
    /// Optional flag arguments that only have one character (ex. "-b") and use type `bool`
    comptime optFlagArgs: []const Arg,
    /// Optional value arguments that are a full name with trailing value (ex. "--test foo") and use type `[]const u8` containing the trailing value.
    comptime optValueArgs: []const Arg,
    /// Must have arguments that are positional (ex. <path>) and must contain a `[]const u8`.
    comptime posArgs: []const Arg,
    /// Accepts list of values after '-'.
    comptime vaArgs: ?Arg,
) type {
    return struct {
        const allArgs = optFlagArgs ++ optValueArgs ++ posArgs ++ (if (vaArgs) |va| .{va} else .{});

        const Args = MergeStruct(&.{
            BuildArgStruct(bool, optFlagArgs),
            BuildArgStruct(?[:0]const u8, optValueArgs),
            BuildArgStruct([:0]const u8, posArgs),
        });

        /// Filled out user struct with slices of the arguments
        args: Args,

        /// Remaining arguments as a slice
        remaining: []const [*:0]const u8,

        /// Displays a help message detailing the arguments and usage by writing the message into a writer
        ///
        /// Errors:
        /// - Returns errors from writer .writeAll
        pub fn displayHelp(
            /// Writer implementing .writeAll([]const u8) !void
            wrt: anytype,
        ) !void {
            const msg = comptime blk: {
                var msg: []const u8 = "";

                // Append description
                msg = msg ++ description;

                // Append usage
                msg = msg ++ "\n\nusage: " ++ appName;

                // Append options flag if available
                if (optFlagArgs.len != 0 or optValueArgs.len != 0) msg = msg ++ " [options]";

                // Append positionals
                for (posArgs) |arg| msg = msg ++ " <" ++ arg.name ++ ">";

                // Append va_args if availble
                if (vaArgs) |va| msg = msg ++ " - [" ++ va.name ++ "]";

                // Append options if available
                if (allArgs.len != 0) {
                    const nameMaxLen = bblk: {
                        var nameMaxLen = 0;
                        for (allArgs) |i| nameMaxLen = @max(nameMaxLen, i.name.len);
                        break :bblk nameMaxLen;
                    };

                    msg = msg ++ "\n  options:\n";

                    for (optFlagArgs) |i| msg = msg ++ std.fmt.comptimePrint("    [flg] {[name]s: <[nw]}: {[desc]s}\n", .{
                        .name = i.name,
                        .desc = i.desc,
                        .nw = nameMaxLen,
                    });
                    for (optValueArgs) |i| msg = msg ++ std.fmt.comptimePrint("    [val] {[name]s: <[nw]}: {[desc]s}\n", .{
                        .name = i.name,
                        .desc = i.desc,
                        .nw = nameMaxLen,
                    });
                    for (posArgs) |i| msg = msg ++ std.fmt.comptimePrint("    [pos] {[name]s: <[nw]}: {[desc]s}\n", .{
                        .name = i.name,
                        .desc = i.desc,
                        .nw = nameMaxLen,
                    });
                    if (vaArgs) |i| msg = msg ++ std.fmt.comptimePrint("    [var] {[name]s: <[nw]}: {[desc]s}\n", .{
                        .name = i.name,
                        .desc = i.desc,
                        .nw = nameMaxLen,
                    });
                } else {
                    msg = msg ++ "\n";
                }

                break :blk msg;
            };

            try wrt.writeAll(msg);
        }

        /// Parse the cli given arguments with the user given structure
        ///
        /// Returns:
        /// - Self containing all parsed arguments. `deinit` must be called at the end.
        pub fn parseArgs(
            /// Array with args (argv)
            args: []const [*:0]const u8,
        ) ParseError!@This() {
            // Initialize args with defaults
            var a: Args = undefined;
            inline for (optFlagArgs) |f| @field(a, f.name) = false;
            inline for (optValueArgs) |f| @field(a, f.name) = null;

            // Find all positional addresses in struct in order for quick access
            const posAdressOffsets = comptime brk: {
                var addrs: [posArgs.len]usize = .{0} ** posArgs.len;
                for (posArgs, 0..) |arg, i| addrs[i] = @offsetOf(Args, arg.name);
                break :brk addrs;
            };

            var argIter: usize = 0; // Used for iterating arguments
            var posIter: usize = 0; // Used for iterating positionals

            var optFieldPtr: ?*?[:0]const u8 = null; // State: if had a optional value => have its field

            while (argIter < args.len) : (argIter += 1) {
                const arg = std.mem.span(args[argIter]);

                if (optFieldPtr) |fieldPtr| { // Must be optional value
                    optFieldPtr = null;
                    fieldPtr.* = arg;
                } else {
                    if (arg[0] == '-') {
                        if (arg.len == 1) {
                            argIter += 1; // Skip '-'
                            break;
                        }

                        if (arg[1] == '-') { // Must be a value flag
                            inline for (optValueArgs) |field| {
                                if (std.mem.eql(u8, arg[2..], field.name)) {
                                    optFieldPtr = &@field(a, field.name);
                                    break;
                                }
                            } else {
                                return ParseError.UnknownValueOption;
                            }

                            continue;
                        }

                        // Must be a optional flag
                        inline for (optFlagArgs) |field| {
                            if (std.mem.eql(u8, arg[1..], field.name)) {
                                @field(a, field.name) = true;
                                break;
                            }
                        } else {
                            return ParseError.UnknownFlagOption;
                        }

                        continue;
                    }

                    if (posIter != posAdressOffsets.len) { // Must be a positional
                        const fieldAddr: *[:0]const u8 = @ptrFromInt(@intFromPtr(&a) + posAdressOffsets[posIter]);
                        fieldAddr.* = arg;
                        posIter += 1;
                        continue;
                    }

                    return ParseError.UnknownArgument;
                }
            }

            if (posIter != posAdressOffsets.len) {
                return ParseError.MissingPositionalOptions;
            }

            if (optFieldPtr != null) {
                return ParseError.MissingValueOptionAtEnd;
            }

            return .{ .args = a, .remaining = args[argIter..] };
        }
    };
}

test "ArgStruct.parseArgs Usage" {
    const Args = ArgStruct("test", "This is a test", &.{.{
        .name = "help",
        .desc = "Displays this help message.",
    }}, &.{.{
        .name = "A space!!!",
        .desc = "Test param for optional value argument",
    }}, &.{.{
        .name = "°*'\"Ä*\"§",
        .desc = "Magic characters",
    }}, null);

    { // Correct without rest
        const parsedArgs = try Args.parseArgs(&.{ "-help", "--A space!!!", "val", "test" });
        const args = parsedArgs.args;

        try std.testing.expectEqual(true, args.help);
        try std.testing.expectEqualStrings("val", args.@"A space!!!".?);
        try std.testing.expectEqualStrings("test", args.@"°*'\"Ä*\"§");
    }

    { // Correct with rest
        const parsedArgs = try Args.parseArgs(&.{ "-help", "--A space!!!", "val", "test", "-", "1", "2", "3" });
        const args = parsedArgs.args;

        try std.testing.expectEqual(true, args.help);
        try std.testing.expectEqualStrings("val", args.@"A space!!!".?);
        try std.testing.expectEqualStrings("test", args.@"°*'\"Ä*\"§");
        try std.testing.expectEqualDeep(&[_][*:0]const u8{ "1", "2", "3" }, parsedArgs.remaining);
    }
}
