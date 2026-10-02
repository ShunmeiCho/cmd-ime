import Foundation

/// What runs in the foreground of a terminal device, asked of the kernel: no child process, no
/// terminal app involved. Measured 2026-10-03: 0.07-0.6 ms per device.
public enum TerminalDevice {
    /// The name a Program Rule matches for the foreground program of `device` (`ttys009` or
    /// `/dev/ttys009`): the foreground process group leader's argv0, without its directory and
    /// without the dash a login shell carries. Nil when the device does not exist, has no
    /// foreground group or its leader cannot be read (another user's process, or one that ended).
    public static func foregroundProgram(ofDevice device: String) -> String? {
        #if canImport(Darwin)
        let path = device.hasPrefix("/dev/") ? device : "/dev/" + device
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        guard let leader = foregroundLeader(device: info.st_rdev) else { return nil }
        return argv0(of: leader).flatMap(programName(fromArgv0:))
        #else
        return nil
        #endif
    }

    /// The name a Program Rule matches for process `pid` (Ghostty reports its foreground process
    /// by pid). Only argv0 is kept from the argument buffer the kernel returns.
    public static func program(ofPID pid: Int32) -> String? {
        #if canImport(Darwin)
        guard pid > 0 else { return nil }
        return argv0(of: pid).flatMap(programName(fromArgv0:))
        #else
        return nil
        #endif
    }

    /// `/usr/local/bin/claude` -> `claude`, `-zsh` -> `zsh`; nil for an empty name.
    public static func programName(fromArgv0 argv0: String) -> String? {
        var name = argv0.split(separator: "/").last.map(String.init) ?? argv0
        if name.hasPrefix("-") { name.removeFirst() }
        return name.isEmpty ? nil : name
    }

    #if canImport(Darwin)
    private static func foregroundLeader(device: dev_t) -> pid_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, Int32(bitPattern: UInt32(truncatingIfNeeded: device))]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        // Room for processes started between the two calls.
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 8
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        size = capacity * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &processes, &size, nil, 0) == 0 else { return nil }
        let found = processes.prefix(size / MemoryLayout<kinfo_proc>.stride)
        guard let group = found.first?.kp_eproc.e_tpgid, group > 0,
              found.contains(where: { $0.kp_proc.p_pid == group }) else { return nil }
        return group
    }

    private static func argv0(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return argv0(fromProcArgs: buffer.prefix(size))
    }
    #endif

    /// The executable path's slot is padded with NULs to a multiple of this (measured on macOS 27.2 with paths
    /// of 8, 10, 12, 13 and 19 bytes).
    static let procArgsPathAlignment = 8

    /// argv[0] from a `KERN_PROCARGS2` buffer: an Int32 argument count, the executable path padded with NULs
    /// to `procArgsPathAlignment`, then argv. argv[0] is read at the computed start, never found by skipping
    /// NULs: an empty argv[0] would otherwise hand over the next argument, or the environment, as the name
    /// (review I1). Nil when the count is zero, the layout is not the expected one, or argv[0] is empty.
    /// Nothing after argv[0] is looked at.
    static func argv0<Bytes: Collection>(fromProcArgs bytes: Bytes) -> String? where Bytes.Element == UInt8, Bytes.Index == Int {
        let countSize = MemoryLayout<Int32>.size
        guard bytes.count > countSize else { return nil }
        let base = bytes.startIndex
        let argc = (0..<countSize).reduce(Int32(0)) { $0 | Int32(bytes[base + $1]) << (8 * $1) }
        guard argc >= 1 else { return nil }
        let pathStart = base + countSize
        guard let pathEnd = bytes[pathStart...].firstIndex(of: 0) else { return nil }
        let pathSlot = (pathEnd - pathStart + 1 + procArgsPathAlignment - 1) / procArgsPathAlignment * procArgsPathAlignment
        let argvStart = pathStart + pathSlot
        guard argvStart < bytes.endIndex, bytes[pathEnd..<argvStart].allSatisfy({ $0 == 0 }),
              let argvEnd = bytes[argvStart...].firstIndex(of: 0), argvEnd > argvStart else { return nil }
        return String(decoding: bytes[argvStart..<argvEnd], as: UTF8.self)
    }
}
