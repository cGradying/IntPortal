import Darwin
import Foundation

/// Whether loading a model risks overloading the machine. On Apple Silicon
/// there's no discrete GPU/VRAM — the GPU addresses the same unified system
/// memory the CPU does — so "GPU overload" is really system memory pressure,
/// and that's what this checks.
enum SystemMemory {
    static var physicalMemoryBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }

    /// A macOS-appropriate "available" estimate. There's no kernel-blessed
    /// single number the way Linux's `MemAvailable` gives one — free pages
    /// alone badly understate what's really available, since macOS caches
    /// aggressively. This adds back inactive/purgeable/external pages the
    /// kernel can reclaim under pressure, the same reasoning Activity
    /// Monitor's "Memory Used" implies by subtraction. `nil` on the (rare)
    /// Mach call failure — callers treat that as "can't tell, don't warn".
    static func availableBytes() -> UInt64? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let reclaimable = UInt64(stats.free_count) + UInt64(stats.inactive_count)
            + UInt64(stats.purgeable_count) + UInt64(stats.external_page_count)
        return reclaimable * pageSize
    }

    /// Ollama reports a model's on-disk weight size, which is a floor — KV
    /// cache and compute buffers add more once actually loaded. Warning well
    /// before the model's own footprint alone would consume most of what's
    /// free is deliberately conservative rather than exact.
    static func shouldWarn(modelBytes: Int64, availableBytes: UInt64, threshold: Double = 0.6) -> Bool {
        guard modelBytes > 0, availableBytes > 0 else { return false }
        return Double(modelBytes) > Double(availableBytes) * threshold
    }
}
