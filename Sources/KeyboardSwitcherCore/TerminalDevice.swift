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

    /// argv[0] from `KERN_PROCARGS2`: an argument count, the executable path, padding, then argv.
    /// The rest of the buffer (other arguments, the environment) is not looked at.
    private static func argv0(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        let start = index
        while index < size, buffer[index] != 0 { index += 1 }
        guard index > start else { return nil }
        return String(decoding: buffer[start..<index], as: UTF8.self)
    }
    #endif
}
