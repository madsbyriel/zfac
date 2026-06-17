const std = @import("std");

const zfac = @import("zfac");

pub fn main(_: std.process.Init) !void {
    const result = zfac.add(1, 2);
    std.log.debug("result: {d}", .{result});
    return;
}
