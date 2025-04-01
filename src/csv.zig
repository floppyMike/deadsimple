const std = @import("std");

/// Build up headers out of a given arguments
///
/// Returns:
/// - Header in CSV format
pub fn buildHeader(
    /// CSV Entry
    EntryType: type,
    /// Seperator to use
    comptime sep: u8,
) []const u8 {
    const entry = @typeInfo(EntryType).@"struct";

    if (entry.fields.len == 0) {
        @compileError("Must have at least one column.");
    }

    comptime var res = entry.fields[0].name;

    inline for (entry.fields[1..]) |cat| {
        res = res ++ .{sep} ++ cat.name;
    }

    return res;
}

test "buildHeader multi item" {
    const Entry = struct {
        a: []const u8,
        b: []const u8,
        c: []const u8,
        d: []const u8,
    };

    const header = buildHeader(Entry, ';');
    try std.testing.expectEqualStrings("a;b;c;d", header);
}

test "buildHeader one item" {
    const Entry = struct {
        asdfghj: []const u8,
    };

    const header = buildHeader(Entry, ';');
    try std.testing.expectEqualStrings("asdfghj", header);
}

// Should not compile
// test "buildHeader empty" {
//     const Entry = struct {};
//
//     const header = buildHeader(Entry, ';');
//     _ = header;
// }

//
//
//

/// Create a CSVReader struct that specializes in parsing a CSV string.
pub fn CSVReader(
    /// Seperator to use
    comptime sep: u8,
    /// Entry type. All fields must have type `[]const u8`
    EntryType: type,
) type {
    return struct {
        // Header that should be there
        pub const header = buildHeader(EntryType, sep);

        /// Internal buffer for storing []u8 which are sliced into the entry
        parseBuf: std.ArrayList(u8),
        /// Current line the reader is on
        line: u64,

        /// Initializes a CSVReader with a header
        pub fn initHeader(
            /// Allocator to use for line buffer
            alloc: std.mem.Allocator,
            /// Reader instance for checking the header of the csv file
            reader: anytype,
        ) (error{
            /// CSV header doesn't match expected
            CSVHeaderMismatch,
        } || std.mem.Allocator.Error)!@This() {
            var csvreader = try init(alloc);
            errdefer csvreader.deinit();

            reader.streamUntilDelimiter(csvreader.parseBuf.writer(), '\n', null) catch |e| switch (e) {
                error.StreamTooLong => unreachable, // No limit definied
                error.EndOfStream => {}, // At Eof we use what is written
                else => |err| return err,
            };

            if (!std.mem.eql(u8, csvreader.parseBuf.items, header)) return error.CSVHeaderMismatch;

            csvreader.line += 1;

            return csvreader;
        }

        /// Initializes a CSVReader without a header
        pub fn init(
            /// Allocator to use for line buffer
            alloc: std.mem.Allocator,
        ) std.mem.Allocator.Error!@This() {
            var parseBuf = std.ArrayList(u8).init(alloc);
            errdefer parseBuf.deinit();

            try parseBuf.ensureTotalCapacity(128);

            return .{ .parseBuf = parseBuf, .line = 1 };
        }

        /// Deallocates the internal buffer
        pub fn deinit(s: @This()) void {
            s.parseBuf.deinit();
        }

        /// Reads a CSV entry
        ///
        /// Returns:
        /// - A filled out entry of given EntryType or null if at end
        pub fn readEntry(
            self: *@This(),
            /// Reader instance for reading a entry of the csv file
            reader: anytype,
        ) (error{
            // Number of delimiters on a line don't match number of entries in struct
            MismatchNumberOfEntries,
        } || std.mem.Allocator.Error)!?EntryType {
            self.parseBuf.clearRetainingCapacity();
            self.line += 1;

            // Read till line end or eof
            reader.streamUntilDelimiter(self.parseBuf.writer(), '\n', null) catch |err| switch (err) {
                error.EndOfStream, error.StreamTooLong => {},
                else => |e| return e,
            };

            if (self.parseBuf.items.len == 0) return null;

            const entryInfo = @typeInfo(EntryType).@"struct";
            const categories = entryInfo.fields;

            var offsets: [categories.len]usize = undefined;
            offsets[offsets.len - 1] = self.parseBuf.items.len;

            // Iterate through buffer and find all delimiters
            var offsetIter: usize = 0;
            var bufferIter: usize = 0;
            while (bufferIter < self.parseBuf.items.len and offsetIter < offsets.len) : (bufferIter += 1) {
                const c = self.parseBuf.items[bufferIter];
                if (c == sep) {
                    offsets[offsetIter] = bufferIter;
                    offsetIter += 1;
                }
            }

            // If too many delimiters (bufferIter too small) or too little delimiters (offsetIter too small)
            if (bufferIter != self.parseBuf.items.len or offsetIter != offsets.len - 1) {
                return error.MismatchNumberOfEntries;
            }

            var e: EntryType = undefined;

            var prevOffset: usize = 0;
            inline for (offsets, categories) |offset, f| {
                @field(e, f.name) = self.parseBuf.items[prevOffset..offset];
                prevOffset = offset + 1; // Skip delimiter
            }

            return e;
        }
    };
}

test "CSVReader multi line no newline" {
    var buffer = std.io.fixedBufferStream("a,b\n123456789,987654321\nabc,cde");
    const bufferReader = buffer.reader();

    const Entry = struct {
        a: []const u8,
        b: []const u8,
    };

    var csvReader = try CSVReader(',', Entry).initHeader(std.testing.allocator, bufferReader);
    defer csvReader.deinit();

    try std.testing.expectEqualDeep(Entry{ .a = "123456789", .b = "987654321" }, try csvReader.readEntry(bufferReader));
    try std.testing.expectEqualDeep(Entry{ .a = "abc", .b = "cde" }, try csvReader.readEntry(bufferReader));
    try std.testing.expectEqualDeep(null, try csvReader.readEntry(bufferReader));
}

test "CSVReader multi line with newline" {
    var buffer = std.io.fixedBufferStream("a,b,c\n12,34,56\n");
    const bufferReader = buffer.reader();

    const Entry = struct {
        a: []const u8,
        b: []const u8,
        c: []const u8,
    };

    var csvReader = try CSVReader(',', Entry).initHeader(std.testing.allocator, bufferReader);
    defer csvReader.deinit();

    try std.testing.expectEqualDeep(Entry{ .a = "12", .b = "34", .c = "56" }, try csvReader.readEntry(bufferReader));
    try std.testing.expectEqualDeep(null, try csvReader.readEntry(bufferReader));
}

test "CSVReader one line" {
    var buffer = std.io.fixedBufferStream("123456789");
    const bufferReader = buffer.reader();

    const Entry = struct {
        a: []const u8,
    };

    var csvReader = try CSVReader(',', Entry).init(std.testing.allocator);
    defer csvReader.deinit();

    try std.testing.expectEqualDeep(Entry{ .a = "123456789" }, try csvReader.readEntry(bufferReader));
    try std.testing.expectEqualDeep(null, try csvReader.readEntry(bufferReader));
}

test "CSVReader empty line" {
    var buffer = std.io.fixedBufferStream(",");
    const bufferReader = buffer.reader();

    const Entry = struct {
        a: []const u8,
        b: []const u8,
    };

    var csvReader = try CSVReader(',', Entry).init(std.testing.allocator);
    defer csvReader.deinit();

    try std.testing.expectEqualDeep(Entry{ .a = "", .b = "" }, try csvReader.readEntry(bufferReader));
    try std.testing.expectEqualDeep(null, try csvReader.readEntry(bufferReader));
}

test "CSVReader nothing" {
    var buffer = std.io.fixedBufferStream("");
    const bufferReader = buffer.reader();

    const Entry = struct {
        a: []const u8,
    };

    var csvReader = try CSVReader(',', Entry).init(std.testing.allocator);
    defer csvReader.deinit();

    try std.testing.expectEqualDeep(null, try csvReader.readEntry(bufferReader));
}

test "CSVReader no header => Get mismatch error" {
    var buffer = std.io.fixedBufferStream("");
    const bufferReader = buffer.reader();

    const Entry = struct {
        a: []const u8,
    };

    try std.testing.expectError(error.CSVHeaderMismatch, CSVReader(',', Entry).initHeader(std.testing.allocator, bufferReader));
}

test "CSVReader wrong header => Get mismatch error" {
    var buffer = std.io.fixedBufferStream("wrong");
    const bufferReader = buffer.reader();

    const Entry = struct {
        a: []const u8,
    };

    try std.testing.expectError(error.CSVHeaderMismatch, CSVReader(',', Entry).initHeader(std.testing.allocator, bufferReader));
}

test "CSVReader wrong content => Get mismatch error" {
    var buffer = std.io.fixedBufferStream("hey\na,b");
    const bufferReader = buffer.reader();

    const Entry = struct {
        hey: []const u8,
    };

    var csvReader = try CSVReader(',', Entry).initHeader(std.testing.allocator, bufferReader);
    defer csvReader.deinit();

    try std.testing.expectError(error.MismatchNumberOfEntries, csvReader.readEntry(bufferReader));
}

//
//
//

/// Create a CSVWriter struct that specializes in writing a CSV string.
pub fn CSVWriter(
    /// Seperator to use
    comptime sep: u8,
    /// Entry type. All fields must have type `[]const u8`
    EntryType: type,
) type {
    return struct {
        pub const header = buildHeader(EntryType, sep);

        line: u64,

        /// Initializes a CSVWriter with a header
        pub fn initHeader(
            /// Writer instance for writing the header
            writer: anytype,
        ) error{NoSpaceLeft}!@This() {
            var csvwriter = init();

            try writer.writeAll(header);
            try writer.writeByte('\n');
            csvwriter.line += 1;

            return csvwriter;
        }

        /// Initializes a CSVWriter without a header
        pub fn init() @This() {
            return .{ .line = 1 };
        }

        /// Writes a CSV entry
        pub fn writeEntry(
            self: *@This(),
            /// Entry to write
            row: EntryType,
            /// Writer instance for writing the entry
            writer: anytype,
        ) error{NoSpaceLeft}!void {
            const rowInfo = @typeInfo(EntryType).@"struct";
            const rowFields = rowInfo.fields;

            inline for (rowFields[0..(rowFields.len - 1)]) |field| {
                try writer.writeAll(@field(row, field.name));
                try writer.writeByte(sep);
            }

            try writer.writeAll(@field(row, rowFields[rowFields.len - 1].name));
            try writer.writeByte('\n');

            self.line += 1;
        }
    };
}

test "CSVWriter normal run with no space left at end" {
    var buffer: [10]u8 = undefined;
    var bufferStream = std.io.fixedBufferStream(&buffer);
    const bufferWriter = bufferStream.writer();

    const Entry = struct {
        a: []const u8,
        b: []const u8,
    };

    var csvWriter = try CSVWriter(',', Entry).initHeader(bufferWriter);
    try csvWriter.writeEntry(.{ .a = "1", .b = "2" }, bufferWriter);
    try csvWriter.writeEntry(.{ .a = "", .b = "" }, bufferWriter);

    try std.testing.expectEqualDeep("a,b\n1,2\n,\n", bufferStream.getWritten());
    try std.testing.expectError(error.NoSpaceLeft, csvWriter.writeEntry(.{ .a = "bbb", .b = "ccc" }, bufferWriter));
}
