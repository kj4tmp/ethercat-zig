//! Deterministic Simulator for EtherCAT Networks

const std = @import("std");
const assert = std.debug.assert;

const ENI = @import("ENI.zig");
const nic = @import("nic.zig");
const telegram = @import("telegram.zig");

/// Provides a link layer that will simulate an ethercat network
/// specified using an ethercat network information struct.
///
/// Simulator advances one tick during recv() and returns frames
/// like a raw socket.
/// Simulator injests frames from application using send().
pub const Simulator = struct {
    eni: ENI,
    arena: *std.heap.ArenaAllocator,
    /// Frames waiting to be processed during tick().
    /// Appended by send().
    in_frames: *std.ArrayList(Frame),
    /// frames waiting to be returned by recv().
    /// Appended by tick().
    out_frames: *std.ArrayList(Frame),

    const Frame = std.BoundedArray(u8, telegram.max_frame_length);

    pub const Options = struct {
        max_simultaneous_frames_in_flight: usize = 256,
    };

    /// Allocates once. Never allocates again.
    /// Call deinit to free resources.
    pub fn init(eni: ENI, allocator: std.mem.Allocator, options: Options) !Simulator {
        const arena = try allocator.create(std.heap.ArenaAllocator);
        errdefer allocator.destroy(arena);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        const in_frames_slice = try arena.allocator().alloc(Frame, options.max_simultaneous_frames_in_flight);
        const in_frames = try arena.allocator().create(std.ArrayList(Frame));
        in_frames.* = std.ArrayList(Frame).fromOwnedSlice(std.testing.failing_allocator, in_frames_slice);
        in_frames.shrinkRetainingCapacity(0);

        const out_frames_slice = try arena.allocator().alloc(Frame, options.max_simultaneous_frames_in_flight);
        const out_frames = try arena.allocator().create(std.ArrayList(Frame));
        out_frames.* = std.ArrayList(Frame).fromOwnedSlice(std.testing.failing_allocator, out_frames_slice);
        out_frames.shrinkRetainingCapacity(0);

        return Simulator{
            .eni = eni,
            .arena = arena,
            .in_frames = in_frames,
            .out_frames = out_frames,
        };
    }
    pub fn deinit(self: *Simulator, allocator: std.mem.Allocator) void {
        self.arena.deinit();
        allocator.destroy(self.arena);
    }

    // add a frame to the processing queue
    pub fn send(ctx: *anyopaque, bytes: []const u8) std.posix.SendError!void {
        const self: *Simulator = @ptrCast(@alignCast(ctx));
        const frame = Frame.fromSlice(bytes) catch return error.MessageTooBig;
        self.in_frames.append(frame) catch return error.SystemResources;
    }

    // execute one tick in the simulator, return a frame if available
    pub fn recv(ctx: *anyopaque, out: []u8) std.posix.RecvFromError!usize {
        const self: *Simulator = @ptrCast(@alignCast(ctx));
        self.tick();
        var out_stream = std.io.fixedBufferStream(out);
        if (self.out_frames.popOrNull()) |frame| {
            return out_stream.write(frame.slice()) catch |err| switch (err) {
                error.NoSpaceLeft => return 0,
            };
        } else return 0;
        unreachable;
    }

    pub fn linkLayer(self: *Simulator) nic.LinkLayer {
        return nic.LinkLayer{
            .ptr = self,
            .vtable = &.{ .send = send, .recv = recv },
        };
    }

    pub fn tick(self: *Simulator) void {
        if (self.in_frames.popOrNull()) |frame| {
            self.out_frames.appendAssumeCapacity(frame);
        }
    }
};

test {
    std.testing.refAllDecls(@This());
}
