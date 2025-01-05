const std = @import("std");

// Constants for special node IDs
pub const NodeGND = 558; // vss
pub const NodePWR = 657; // vcc
pub const NodeCLK0 = 1171; // clock 0
pub const NodeRDY = 89; // ready
pub const NodeSO = 1672; // stack overflow
pub const NodeNMI = 1297; // non maskable interrupt
pub const NodeIRQ = 103; // interrupt
pub const NodeRES = 159; // reset
pub const NodeRW = 1156; // read/write

pub const NodeDefCount = 1725;

// Callback function types for bus operations
pub const ReadFromBus = *const fn (address: usize) u8;
pub const WriteToBus = *const fn (address: usize, data: u8) void;

// Transistor represents a transistor in the CPU
pub const Transistor = struct {
    id: usize,
    gate_node_id: usize,
    c1_node_id: usize,
    c2_node_id: usize,
    on: bool,
};

// Node represents a node in the CPU
pub const Node = struct {
    id: usize,
    state: bool,
    pull_up: bool,
    pull_down: i32,
    gate_transistors: std.ArrayList(*Transistor),
    c1c2_transistors: std.ArrayList(*Transistor),
    in_node_group: bool,
};

// Data line node IDs (D0-D7)
pub const data_line_vals = [_]struct { bit: u3, node: usize }{
    .{ .bit = 0, .node = 1005 }, // D0
    .{ .bit = 1, .node = 82 }, // D1
    .{ .bit = 2, .node = 945 }, // D2
    .{ .bit = 3, .node = 650 }, // D3
    .{ .bit = 4, .node = 1393 }, // D4
    .{ .bit = 5, .node = 175 }, // D5
    .{ .bit = 6, .node = 1591 }, // D6
    .{ .bit = 7, .node = 1349 }, // D7
};

// Address line node IDs (A0-A15)
pub const address_line_vals = [_]struct { bit: u4, node: usize }{
    .{ .bit = 0, .node = 268 }, // A0
    .{ .bit = 1, .node = 451 }, // A1
    .{ .bit = 2, .node = 1340 }, // A2
    .{ .bit = 3, .node = 211 }, // A3
    .{ .bit = 4, .node = 435 }, // A4
    .{ .bit = 5, .node = 736 }, // A5
    .{ .bit = 6, .node = 887 }, // A6
    .{ .bit = 7, .node = 1493 }, // A7
    .{ .bit = 8, .node = 230 }, // A8
    .{ .bit = 9, .node = 148 }, // A9
    .{ .bit = 10, .node = 1443 }, // A10
    .{ .bit = 11, .node = 399 }, // A11
    .{ .bit = 12, .node = 1237 }, // A12
    .{ .bit = 13, .node = 349 }, // A13
    .{ .bit = 14, .node = 672 }, // A14
    .{ .bit = 15, .node = 195 }, // A15
};

pub const CPU = struct {
    allocator: std.mem.Allocator,
    transistors: std.AutoHashMap(usize, *Transistor),
    nodes: [NodeDefCount]?*Node,
    gnd_node: ?*Node,
    pwr_node: ?*Node,
    recalc_node_group: std.ArrayList(*Node),
    read_from_bus: ReadFromBus,
    write_to_bus: WriteToBus,
    address_bits: u16,
    data_bits: u8,

    pub fn init(allocator: std.mem.Allocator, read_from_bus: ReadFromBus, write_to_bus: WriteToBus) !*CPU {
        const self = try allocator.create(CPU);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .transistors = std.AutoHashMap(usize, *Transistor).init(allocator),
            .nodes = [_]?*Node{null} ** NodeDefCount,
            .gnd_node = null,
            .pwr_node = null,
            .recalc_node_group = std.ArrayList(*Node).init(allocator),
            .read_from_bus = read_from_bus,
            .write_to_bus = write_to_bus,
            .address_bits = 0,
            .data_bits = 0,
        };

        return self;
    }

    pub fn setupTransistors(self: *CPU, trans_defs_path: []const u8) !void {
        std.debug.print("Opening transistor definitions from: {s}\n", .{trans_defs_path});

        const file = try std.fs.cwd().openFile(trans_defs_path, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();

        var buf: [4096]u8 = undefined;
        while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            // Skip empty lines and comments
            if (line.len == 0 or line[0] == '#') continue;

            var it = std.mem.tokenizeAny(u8, line, ", \t\r\n");
            const id_str = it.next() orelse continue;
            const gate_str = it.next() orelse continue;
            const c1_str = it.next() orelse continue;
            const c2_str = it.next() orelse continue;

            const id = try std.fmt.parseInt(usize, id_str, 10);
            const gate = try std.fmt.parseInt(usize, gate_str, 10);
            var c1 = try std.fmt.parseInt(usize, c1_str, 10);
            var c2 = try std.fmt.parseInt(usize, c2_str, 10);

            // Handle special cases for GND and PWR connections
            if (c1 == NodeGND) {
                const temp = c1;
                c1 = c2;
                c2 = temp;
            }
            if (c1 == NodePWR) {
                const temp = c1;
                c1 = c2;
                c2 = temp;
            }

            const trans = try self.allocator.create(Transistor);
            errdefer self.allocator.destroy(trans);

            trans.* = .{
                .id = id,
                .gate_node_id = gate,
                .c1_node_id = c1,
                .c2_node_id = c2,
                .on = false,
            };

            try self.transistors.put(trans.id, trans);
        }

        std.debug.print("Loaded {} transistors\n", .{self.transistors.count()});
    }

    pub fn setupNodes(self: *CPU, seg_defs_path: []const u8) !void {
        std.debug.print("Opening segment definitions from: {s}\n", .{seg_defs_path});

        const file = try std.fs.cwd().openFile(seg_defs_path, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();

        var buf: [4096]u8 = undefined;
        while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            // Skip empty lines and comments
            if (line.len == 0 or line[0] == '#') continue;

            var it = std.mem.tokenizeAny(u8, line, ", \t\r\n");
            const id_str = it.next() orelse continue;
            const pullup_str = it.next() orelse continue;

            const id = try std.fmt.parseInt(usize, id_str, 10);
            const pullup = try std.fmt.parseInt(i32, pullup_str, 10);

            if (self.nodes[id] == null) {
                const node = try self.allocator.create(Node);
                errdefer self.allocator.destroy(node);

                node.* = .{
                    .id = id,
                    .state = false,
                    .pull_up = pullup == 1,
                    .pull_down = -1,
                    .gate_transistors = std.ArrayList(*Transistor).init(self.allocator),
                    .c1c2_transistors = std.ArrayList(*Transistor).init(self.allocator),
                    .in_node_group = false,
                };

                self.nodes[id] = node;
            }
        }

        var node_count: usize = 0;
        for (self.nodes) |maybe_node| {
            if (maybe_node != null) {
                node_count += 1;
            }
        }
        std.debug.print("Loaded {} nodes\n", .{node_count});
    }

    pub fn connectTransistors(self: *CPU) !void {
        // std.debug.print("Connecting transistors to nodes...\n", .{});

        var trans_it = self.transistors.iterator();
        while (trans_it.next()) |entry| {
            const trans = entry.value_ptr;
            // Create nodes if they don't exist
            inline for (.{ trans.*.gate_node_id, trans.*.c1_node_id, trans.*.c2_node_id }) |node_id| {
                if (self.nodes[node_id] == null) {
                    const node = try self.allocator.create(Node);
                    node.* = .{
                        .id = node_id,
                        .state = false,
                        .pull_up = false,
                        .pull_down = -1,
                        .gate_transistors = std.ArrayList(*Transistor).init(self.allocator),
                        .c1c2_transistors = std.ArrayList(*Transistor).init(self.allocator),
                        .in_node_group = false,
                    };
                    self.nodes[node_id] = node;
                }
            }

            // Connect transistors to nodes
            try self.nodes[trans.*.gate_node_id].?.gate_transistors.append(trans.*);
            try self.nodes[trans.*.c1_node_id].?.c1c2_transistors.append(trans.*);
            try self.nodes[trans.*.c2_node_id].?.c1c2_transistors.append(trans.*);
        }
    }

    pub fn deinit(self: *CPU) void {
        // std.debug.print("Starting CPU cleanup...\n", .{});

        // First clear the recalc group since it references nodes
        // std.debug.print("Clearing recalc_node_group...\n", .{});
        self.recalc_node_group.clearRetainingCapacity();
        self.recalc_node_group.deinit();

        // Clear node references in transistors to avoid potential use-after-free
        // std.debug.print("Cleaning up {} transistors...\n", .{self.transistors.count()});
        var trans_it = self.transistors.iterator();
        while (trans_it.next()) |entry| {
            const trans = entry.value_ptr.*;
            // std.debug.print("Freeing transistor {}...\n", .{trans.id});
            self.allocator.destroy(trans);
        }
        self.transistors.deinit();

        // Now clean up nodes
        // std.debug.print("Cleaning up nodes...\n", .{});
        for (self.nodes) |maybe_node| {
            if (maybe_node) |node| {
                // std.debug.print("Freeing node {}...\n", .{node.id});
                // Clear the ArrayLists first
                node.gate_transistors.clearRetainingCapacity();
                node.c1c2_transistors.clearRetainingCapacity();
                // Then deinit them
                node.gate_transistors.deinit();
                node.c1c2_transistors.deinit();
                // Finally free the node
                self.allocator.destroy(node);
            }
        }

        // std.debug.print("Freeing CPU struct...\n", .{});
        self.allocator.destroy(self);
        // std.debug.print("CPU cleanup complete\n", .{});
    }

    pub fn getNodeValue(self: *CPU) bool {
        if (self.gnd_node.?.in_node_group) {
            return false;
        }
        if (self.pwr_node.?.in_node_group) {
            return true;
        }

        for (self.recalc_node_group.items) |node| {
            if (node.pull_up) {
                return true;
            }
            if (node.pull_down == 1) {
                return false;
            }
            if (node.state) {
                return true;
            }
        }
        return false;
    }

    pub fn addSubNodesToGroup(self: *CPU, node: *Node) void {
        if (node.in_node_group) {
            // std.debug.print("Node {} already in group\n", .{node.id});
            return;
        }

        // std.debug.print("Adding node {} to group\n", .{node.id});
        self.recalc_node_group.append(node) catch |err| {
            std.debug.print("Failed to append node to group: {}\n", .{err});
            return;
        };
        node.in_node_group = true;

        if (node.id == NodeGND or node.id == NodePWR) {
            // std.debug.print("Skipping GND/PWR node {}\n", .{node.id});
            return;
        }

        // std.debug.print("Node {} has {} c1c2 transistors\n", .{ node.id, node.c1c2_transistors.items.len });
        for (node.c1c2_transistors.items) |trans| {
            if (!trans.on) {
                continue;
            }
            const target_node_id = if (trans.c1_node_id == node.id) trans.c2_node_id else trans.c1_node_id;
            // std.debug.print("Following connection from node {} to node {}\n", .{ node.id, target_node_id });

            if (target_node_id >= NodeDefCount) {
                std.debug.print("Warning: Target node ID {} exceeds NodeDefCount {}\n", .{ target_node_id, NodeDefCount });
                continue;
            }

            if (self.nodes[target_node_id]) |target_node| {
                self.addSubNodesToGroup(target_node);
            } else {
                std.debug.print("Warning: Target node {} is null\n", .{target_node_id});
            }
        }
    }

    pub fn recalcNode(self: *CPU, node: *Node, recalc_list: *std.AutoHashMap(usize, *Node)) void {
        if (node.id == NodeGND or node.id == NodePWR) {
            return;
        }

        self.recalc_node_group.clearRetainingCapacity();
        self.addSubNodesToGroup(node);

        const new_state = self.getNodeValue();
        for (self.recalc_node_group.items) |n| {
            n.in_node_group = false;
            if (n.state == new_state) {
                continue;
            }
            n.state = new_state;
            for (n.gate_transistors.items) |trans| {
                if (new_state) {
                    self.turnTransistorOn(trans, recalc_list);
                } else {
                    self.turnTransistorOff(trans, recalc_list);
                }
            }
        }
    }

    pub fn turnTransistorOn(self: *CPU, trans: *Transistor, recalc_list: *std.AutoHashMap(usize, *Node)) void {
        if (trans.on) {
            return;
        }
        trans.on = true;
        if (trans.c1_node_id != NodeGND and trans.c1_node_id != NodePWR) {
            if (self.nodes[trans.c1_node_id]) |node| {
                recalc_list.put(trans.c1_node_id, node) catch return;
            }
        }
    }

    pub fn turnTransistorOff(self: *CPU, trans: *Transistor, recalc_list: *std.AutoHashMap(usize, *Node)) void {
        if (!trans.on) {
            return;
        }
        trans.on = false;
        if (trans.c1_node_id != NodeGND and trans.c1_node_id != NodePWR) {
            if (self.nodes[trans.c1_node_id]) |node| {
                recalc_list.put(trans.c1_node_id, node) catch return;
            }
        }
        if (trans.c2_node_id != NodeGND and trans.c2_node_id != NodePWR) {
            if (self.nodes[trans.c2_node_id]) |node| {
                recalc_list.put(trans.c2_node_id, node) catch return;
            }
        }
    }

    pub fn recalcNodeList(self: *CPU, list: *std.AutoHashMap(usize, *Node)) void {
        // std.debug.print("Starting recalcNodeList with {} nodes\n", .{list.count()});

        var current_list = std.AutoHashMap(usize, *Node).init(self.allocator);
        defer current_list.deinit();
        var next_list = std.AutoHashMap(usize, *Node).init(self.allocator);
        defer next_list.deinit();

        // Copy initial list to current_list
        var it = list.iterator();
        while (it.next()) |entry| {
            current_list.put(entry.key_ptr.*, entry.value_ptr.*) catch |err| {
                std.debug.print("Failed to put node in current_list: {}\n", .{err});
                continue;
            };
        }

        // std.debug.print("Copied {} nodes to current_list\n", .{current_list.count()});

        while (current_list.count() > 0) {
            next_list.clearRetainingCapacity();
            // std.debug.print("Processing {} nodes in current iteration\n", .{current_list.count()});

            var current_it = current_list.iterator();
            while (current_it.next()) |entry| {
                // std.debug.print("Recalculating node {}\n", .{entry.value_ptr.*.id});
                self.recalcNode(entry.value_ptr.*, &next_list);
            }

            // std.debug.print("Generated {} nodes for next iteration\n", .{next_list.count()});

            // Swap lists
            const temp = current_list;
            current_list = next_list;
            next_list = temp;
        }
    }

    pub fn setLow(self: *CPU, node: *Node) void {
        node.pull_up = false;
        node.pull_down = 1;
        var list = std.AutoHashMap(usize, *Node).init(self.allocator);
        defer list.deinit();
        list.put(node.id, node) catch return;
        self.recalcNodeList(&list);
    }

    pub fn setHigh(self: *CPU, node: *Node) void {
        node.pull_up = true;
        node.pull_down = 0;
        var list = std.AutoHashMap(usize, *Node).init(self.allocator);
        defer list.deinit();
        list.put(node.id, node) catch return;
        self.recalcNodeList(&list);
    }

    pub fn reset(self: *CPU) !void {
        std.debug.print("Starting CPU reset...\n", .{});

        // Reset all nodes
        for (self.nodes) |maybe_node| {
            if (maybe_node) |node| {
                node.state = false;
                node.in_node_group = false;
            }
        }

        self.gnd_node = self.nodes[NodeGND];
        if (self.gnd_node == null) {
            std.debug.print("Warning: GND node (ID: {}) not found\n", .{NodeGND});
        }
        self.gnd_node.?.state = false;

        self.pwr_node = self.nodes[NodePWR];
        if (self.pwr_node == null) {
            std.debug.print("Warning: PWR node (ID: {}) not found\n", .{NodePWR});
        }
        self.pwr_node.?.state = true;

        // Reset all transistors
        var trans_it = self.transistors.iterator();
        while (trans_it.next()) |entry| {
            entry.value_ptr.*.on = false;
        }

        const clk0 = self.nodes[NodeCLK0] orelse {
            std.debug.print("Warning: CLK0 node (ID: {}) not found\n", .{NodeCLK0});
            return error.NodeNotFound;
        };

        self.setLow(self.nodes[NodeRES].?);
        self.setLow(clk0);
        self.setHigh(self.nodes[NodeRDY].?);
        self.setLow(self.nodes[NodeSO].?);
        self.setHigh(self.nodes[NodeIRQ].?);
        self.setHigh(self.nodes[NodeNMI].?);

        // Initial recalc of all nodes
        var all_nodes = std.AutoHashMap(usize, *Node).init(self.allocator);
        defer all_nodes.deinit();
        for (self.nodes, 0..) |maybe_node, idx| {
            if (maybe_node) |node| {
                all_nodes.put(idx, node) catch continue;
            }
        }
        self.recalcNodeList(&all_nodes);

        // Initial clock cycles
        var i: usize = 0;
        while (i < 8) : (i += 1) {
            self.setHigh(clk0);
            self.setLow(clk0);
        }

        self.setHigh(self.nodes[NodeRES].?);

        i = 0;
        while (i < 6) : (i += 1) {
            self.setHigh(clk0);
            self.setLow(clk0);
        }
    }

    pub fn readAddressBus(self: *CPU) u16 {
        var address: u16 = 0;
        for (address_line_vals) |line| {
            if (self.nodes[line.node]) |node| {
                if (node.state) {
                    address |= @as(u16, 1) << line.bit;
                }
            }
        }
        self.address_bits = address;
        return address;
    }

    pub fn readDataBus(self: *CPU) u8 {
        var data: u8 = 0;
        for (data_line_vals) |line| {
            if (self.nodes[line.node]) |node| {
                if (node.state) {
                    data |= @as(u8, 1) << line.bit;
                }
            }
        }
        self.data_bits = data;
        return data;
    }

    pub fn handleBusRead(self: *CPU) void {
        if (self.nodes[NodeRW].?.state) {
            const address = self.readAddressBus();
            const data = self.read_from_bus(address);

            // Update data bus nodes
            var list = std.AutoHashMap(usize, *Node).init(self.allocator);
            defer list.deinit();

            for (data_line_vals) |line| {
                if (self.nodes[line.node]) |node| {
                    list.put(line.node, node) catch continue;
                    if ((data & (@as(u8, 1) << line.bit)) != 0) {
                        node.pull_down = 0;
                        node.pull_up = true;
                    } else {
                        node.pull_down = 1;
                        node.pull_up = false;
                    }
                }
            }
            self.recalcNodeList(&list);
        }
    }

    pub fn handleBusWrite(self: *CPU) void {
        if (!self.nodes[NodeRW].?.state) {
            const address = self.readAddressBus();
            const data = self.readDataBus();
            self.write_to_bus(address, data);
        }
    }

    pub fn halfStep(self: *CPU) void {
        const clk0 = self.nodes[NodeCLK0].?;
        if (clk0.state) {
            self.setLow(clk0);
            self.handleBusRead();
        } else {
            self.setHigh(clk0);
            self.handleBusWrite();
        }
    }
};
