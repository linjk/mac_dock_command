import Darwin

enum ProcessTree {
    static func pids(inGroup pgid: Int32) -> [Int32] {
        bsdInfos().compactMap { info in
            Int32(bitPattern: info.pbi_pgid) == pgid ? Int32(bitPattern: info.pbi_pid) : nil
        }
    }

    static func descendantPIDs(of pid: Int32) -> [Int32] {
        let infos = bsdInfos()
        var byParent: [Int32: [Int32]] = [:]
        for info in infos {
            let child = Int32(bitPattern: info.pbi_pid)
            let parent = Int32(bitPattern: info.pbi_ppid)
            byParent[parent, default: []].append(child)
        }

        var ordered: [Int32] = []
        var seen = Set<Int32>()
        var queue = [pid]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            guard seen.insert(current).inserted else { continue }
            ordered.append(current)
            if let children = byParent[current] {
                queue.append(contentsOf: children)
            }
        }
        return ordered
    }

    static func send(_ signal: Int32, toGroup pgid: Int32) -> Bool {
        killpg(pgid, signal) == 0
    }

    static func send(_ signal: Int32, toPIDs pids: [Int32]) {
        for pid in pids {
            _ = kill(pid, signal)
        }
    }

    private static func bsdInfos() -> [proc_bsdinfo] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.stride)
        let filled = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.stride)
        )
        guard filled > 0 else { return [] }

        let count = Int(filled) / MemoryLayout<pid_t>.stride
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        var result: [proc_bsdinfo] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var info = proc_bsdinfo()
            let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize)
            if written == infoSize {
                result.append(info)
            }
        }
        return result
    }
}
