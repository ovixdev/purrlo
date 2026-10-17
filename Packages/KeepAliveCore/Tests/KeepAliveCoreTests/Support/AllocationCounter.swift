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
/// Returns -1 when the hook is unavailable so callers fail rather than pass vacuously.
enum AllocationCounter {
    static func count(_ body: () -> Void) -> Int {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else { return -1 }
        let logger = symbol.assumingMemoryBound(to: MallocLogger?.self)
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
}
