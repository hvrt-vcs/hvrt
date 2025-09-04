pub const test_data = .{
    .test_file1 = @as([:0]const u8, @embedFile("embedded/test/lorem_ipsum1.md")),
    .test_name1 = @as([:0]const u8, "lorem_ipsum1.md"),
};
