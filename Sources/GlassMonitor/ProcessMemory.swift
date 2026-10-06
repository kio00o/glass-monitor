import Darwin
import Foundation

enum ProcessMemory {
    /// Memory footprint per application bundle path, summing the app's helper processes
    /// (a browser is dozens of processes). Uses phys_footprint, the figure Activity Monitor shows as "Memory".
    static func byApp() -> [String: UInt64] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) * 2)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard n > 0 else { return [:] }

        var result: [String: UInt64] = [:]
        var pathBuf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(Int(n)) where pid > 0 {
            guard proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 else { continue }
            let path = String(cString: pathBuf)
            // the outermost .app: ".../Chrome.app/Contents/.../Helper.app/..." belongs to Chrome.app
            guard let r = path.range(of: ".app/") else { continue }
            let app = String(path[..<r.lowerBound]) + ".app"

            var info = rusage_info_current()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            if ok == 0 { result[app, default: 0] += info.ri_phys_footprint }
        }
        return result
    }
}
