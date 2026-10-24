// Reconstructed from 00:40-02:39; the main signature follows the installed Zig 0.16 API.
const std = @import("std");

fn arrSum(arr: []const i32) i32 {
    var acc: i32 = 0;
    for (arr) |value| acc += value;
    return acc;
}

fn workerFn(slice: []const i32, localSum: *i32) void {
    localSum.* = arrSum(slice);
}

fn parallelSum(arr: []const i32, threadCount: usize) !i32 {
    const chunk = (arr.len + threadCount - 1) / threadCount;
    const threads = try std.heap.c_allocator.alloc(std.Thread, threadCount);
    defer std.heap.c_allocator.free(threads);
    var storage: [64]i32 align(128) = undefined;
    const accs = storage[0..threadCount];
    @memset(accs, 0);
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();
    for (threads, 0..) |*thread, i| {
        const start = @min(arr.len, i * chunk);
        const end = @min(arr.len, start + chunk);
        thread.* = try std.Thread.spawn(.{}, workerFn, .{ arr[start..end], &accs[i] });
        spawned += 1;
    }
    for (threads) |thread| thread.join();
    var sum: i32 = 0;
    for (accs) |acc| sum += acc;
    return sum;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len > 4) return error.InvalidArguments;
    var settings = [_]usize{ 200_000_000, 500, 20 };
    for (args[1..], 0..) |argument, i| settings[i] = try std.fmt.parseInt(usize, argument, 10);
    const n = settings[0];
    const iterations = settings[1];
    const workers = settings[2];
    if (n > 200_000_000 or iterations == 0 or iterations > 100_000 or workers == 0 or workers > 64)
        return error.InvalidArguments;
    const allocator = std.heap.page_allocator;
    const arr = try allocator.alloc(i32, n);
    defer allocator.free(arr);
    @memset(arr, 2);
    const durations = try allocator.alloc(f64, iterations);
    defer allocator.free(durations);
    var result: i32 = 0;
    var total: f64 = 0;
    for (durations) |*duration| {
        var timer = try std.time.Timer.start();
        result = try parallelSum(arr, workers);
        duration.* = @as(f64, @floatFromInt(timer.read())) / 1_000_000;
        if (result != @as(i32, @intCast(n * 2))) return error.WrongSum;
        total += duration.*;
    }
    std.debug.print("Workers: {d}\nFirst time: {d:.3} ms\n", .{ workers, durations[0] });
    std.mem.sort(f64, durations, {}, comptime std.sort.asc(f64));
    std.debug.print("Average time: {d:.3} ms\nMedian time: {d:.3} ms\nSum: {d}\n", .{
        total / @as(f64, @floatFromInt(iterations)), durations[iterations / 2], result,
    });
}
