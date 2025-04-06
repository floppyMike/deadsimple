const std = @import("std");

/// Computes the string matching problem using the brute force method.
///
/// Returns:
/// Index of the match, or null if no match occured.
pub fn bruteForce(
    /// String to search in.
    haystack: []const u8,
    /// String to seach with.
    needle: []const u8,
) ?usize {
    if (needle.len > haystack.len) return null;

    var haystacki: usize = 0;
    while (haystacki <= haystack.len - needle.len) : (haystacki += 1) {
        var needlei: usize = 0;
        while (needlei < needle.len) : (needlei += 1) {
            if (haystack[haystacki + needlei] != needle[needlei]) break;
        }

        if (needlei == needle.len) return haystacki;
    }

    return null;
}

/// Computes the string matching problem using the Knuth Morris Pratt method
/// using a self allocated prefix table.
///
/// Returns:
/// Index of the match, or null if no match occured, else an alloc error.
pub fn knuthMorrisPrattAlloc(
    /// Allocator to allocate the prefix table array of size `needle.len`.
    alloc: std.mem.Allocator,
    /// String to search in.
    haystack: []const u8,
    /// String to seach with.
    needle: []const u8,
) !?usize {
    const pt = try alloc.alloc(usize, needle.len);
    defer alloc.free(pt);
    return knuthMorrisPratt(haystack, .{
        .len = needle.len,
        .needle = needle.ptr,
        .prefix_table = pt.ptr,
    });
}

/// Computes the string matching problem using the Knuth Morris Pratt method
/// using user provided prefix table memory.
///
/// Returns:
/// Index of the match, or null if no match occured.
pub fn knuthMorrisPratt(
    /// String to search in.
    haystack: []const u8,
    needle_data: struct {
        /// Length of the needle.
        len: usize,
        /// String to search with (size: len)
        needle: [*]const u8,
        /// Memory for the algorithm to use for the prefix table (size: len)
        prefix_table: [*]usize,
    },
) ?usize {
    const needle = needle_data.needle;
    const pt = needle_data.prefix_table;
    const needle_len = needle_data.len;

    if (needle_len > haystack.len) return null;

    const big: usize = @bitCast(@as(isize, -1));

    // Calculate prefix table
    {
        pt[0] = big;
        var prefixi: usize = 0;

        for (1..needle_len) |i| {
            pt[i] = prefixi;
            while (prefixi != big and needle[i] != needle[prefixi]) prefixi = pt[prefixi];
            prefixi = @addWithOverflow(prefixi, 1)[0];
        }
    }

    // Evalutate haystack
    {
        var needlei: usize = 0;
        for (0..haystack.len) |i| {
            while (needlei != big and haystack[i] != needle[needlei]) needlei = pt[needlei];
            needlei = @addWithOverflow(needlei, 1)[0];
            if (needlei == needle_len) return i + 1 - needle_len;
        }
    }

    return null;
}

pub fn boyerMooreAlloc(alloc: std.mem.Allocator, haystack: []const u8, needle: []const u8) !?usize {
    const pt = try alloc.alloc(isize, (needle.len + 1) * 2);
    defer alloc.free(pt);
    return boyerMoore(haystack, .{
        .len = needle.len,
        .needle = needle.ptr,
        .suffix_table = pt[0..(needle.len + 1)].ptr,
        .shift_table = pt[(needle.len + 1)..].ptr,
    });
}

pub fn boyerMoore(
    haystack: []const u8,
    needle_data: struct {
        /// Length of the needle.
        len: usize,
        /// String to search with (size: len)
        needle: [*]const u8,
        /// Memory for the algorithm to use for the suffix table (size: len + 1)
        suffix_table: [*]isize,
        /// Memory for the algorithm to use for the shift table (size: len + 1)
        shift_table: [*]isize,
    },
) ?usize {
    const needle = needle_data.needle;
    const suffix = needle_data.suffix_table;
    const shift = needle_data.shift_table;

    const needle_len: isize = @intCast(needle_data.len);
    const haystack_len: isize = @intCast(haystack.len);

    if (needle_len > haystack.len) return null;

    // Calculate bad table
    const bad_table = blk: {
        var bad_table: [1 << (@sizeOf(u8) * 8)]isize = undefined;
        @memset(&bad_table, -1);

        for (0..@intCast(needle_len)) |i| {
            const ch = needle[i];
            bad_table[ch] = @intCast(i);
        }

        break :blk bad_table;
    };

    // Calculate suffix/shift table step 1
    {
        @memset(shift[0..@intCast(needle_len + 1)], 0);

        var i = needle_len;
        var j = needle_len + 1;
        suffix[@intCast(i)] = j;

        while (i > 0) {
            while (j <= needle_len and needle[@intCast(i - 1)] != needle[@intCast(j - 1)]) {
                if (shift[@intCast(j)] == 0) shift[@intCast(j)] = j - i;
                j = suffix[@intCast(j)];
            }

            i -= 1;
            j -= 1;

            suffix[@intCast(i)] = j;
        }
    }

    // Calculate suffix/shift table step 2
    {
        var j = suffix[0];
        for (0..@intCast(needle_len + 1)) |i| {
            if (shift[@intCast(i)] == 0) shift[@intCast(i)] = j;
            if (i == j) j = suffix[@intCast(j)];
        }
    }

    // Evalutate haystack
    {
        var i: isize = 0;
        var j: isize = undefined;
        while (i <= haystack_len - needle_len) {
            j = needle_len - 1;
            while (j >= 0 and needle[@intCast(j)] == haystack[@intCast(i + j)]) j -= 1;
            if (j < 0) return @intCast(i) else i += @max(shift[@intCast(j + 1)], j - bad_table[haystack[@intCast(i + j)]]);
        }
    }

    return null;
}

test "Fuzz string matching" {
    std.testing.log_level = .info;

    var random = std.Random.DefaultPrng.init(std.testing.random_seed);
    const rand = random.random();

    var haystack: [256]u8 = undefined;
    rand.bytes(&haystack);

    var iteration: usize = 0;
    const max_iterations = 10000;
    while (iteration < max_iterations) : (iteration += 1) {
        const needle = if (rand.boolean()) blk: {
            const p1 = rand.uintLessThan(usize, haystack.len);
            const p2 = p1 + rand.uintLessThan(usize, haystack.len - p1) + 1;
            break :blk haystack[p1..p2];
        } else "zambubu";

        const expect = std.mem.indexOf(u8, &haystack, needle);

        try std.testing.expectEqual(expect, bruteForce(&haystack, needle));
        try std.testing.expectEqual(expect, try knuthMorrisPrattAlloc(std.testing.allocator, &haystack, needle));
        try std.testing.expectEqual(expect, try boyerMooreAlloc(std.testing.allocator, &haystack, needle));
    }
}
