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
    }
}
