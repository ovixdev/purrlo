import Darwin
import Foundation

private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

private let mallocLogTypeAllocate: UInt32 = 2

// Written only under `lock`; the hook reads them on the watched thread, which is the thread holding the lock.
private nonisolated(unsafe) var allocationCount = 0
private nonisolated(unsafe) var watchedThread: pthread_t?
private let lock = NSLock()

private let hook: MallocLogger = { type, _, _, _, _, _ in
    guard type & mallocLogTypeAllocate != 0, let watched = watchedThread,
          pthread_equal(watched, pthread_self()) != 0 else { return }
    allocationCount += 1
}

/// Counts heap allocations made by the calling thread while `body` runs, via libmalloc's `malloc_logger` hook.
enum AllocationCounter {
    /// Why the hook cannot be installed on this macOS, or nil when it can.
    /// Some releases map `malloc_logger` read-only; writing it then would crash the test process (SIGBUS).
    static let unavailableReason: String? = prepareHook()

    static var isAvailable: Bool {
        unavailableReason == nil
    }

    /// Only written through under `lock`; the pointer itself never changes.
    private nonisolated(unsafe) static let logger: UnsafeMutablePointer<MallocLogger?>? =
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")
            .map { $0.assumingMemoryBound(to: MallocLogger?.self) }

    /// Returns -1 when the hook is unavailable so callers fail rather than pass vacuously.
    static func count(_ body: () -> Void) -> Int {
        guard isAvailable, let logger else { return -1 }
        return lock.withLock {
            let previous = logger.pointee
            allocationCount = 0
            watchedThread = pthread_self()
            logger.pointee = hook
            body()
            logger.pointee = previous
            watchedThread = nil
            return allocationCount
        }
    }

    /// Makes sure the page holding `malloc_logger` is writable, raising its protection if the maximum allows it.
    private static func prepareHook() -> String? {
        guard let logger else { return "libmalloc exports no malloc_logger" }
        var address = mach_vm_address_t(UInt(bitPattern: logger))
        var size: mach_vm_size_t = 0
        var info = vm_region_basic_info_data_64_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_region_basic_info_data_64_t>.size / MemoryLayout<Int32>.size
        )
        var object: mach_port_t = 0
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: Int32.self, capacity: Int(count)) {
                mach_vm_region(mach_task_self_, &address, &size, VM_REGION_BASIC_INFO_64, $0, &count, &object)
            }
        }
        guard result == KERN_SUCCESS else { return "mach_vm_region failed (\(result))" }
        if info.protection & VM_PROT_WRITE != 0 {
            return nil
        }
        guard info.max_protection & VM_PROT_WRITE != 0 else {
            return "malloc_logger is mapped read-only (protection \(info.protection), max \(info.max_protection))"
        }
        let pageSize = UInt(getpagesize())
        let page = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: logger) & ~(pageSize - 1))
        guard mprotect(page, Int(pageSize), PROT_READ | PROT_WRITE) == 0 else {
            return "mprotect on malloc_logger failed (errno \(errno))"
        }
        return nil
    }
}
