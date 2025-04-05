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
    }
}
