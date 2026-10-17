#if E2E_HOOKS
    import Darwin
    import Foundation

    /// Unix-socket server for `kactl` (PRD §6, test hooks). Accepts on a private queue; requests run on the main actor.
    final class ControlServer: @unchecked Sendable {
        typealias Handler = @MainActor (ControlRequest) -> Data

        private let url: URL
        private let handler: Handler
        private let queue = DispatchQueue(label: "io.github.ovixdev.purrlo.e2e.control")
        private var listener: Int32 = -1
        private var source: DispatchSourceRead?

        init(url: URL, handler: @escaping Handler) {
            self.url = url
            self.handler = handler
        }

        func start() throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            unlink(url.path)
            listener = socket(AF_UNIX, SOCK_STREAM, 0)
            guard listener >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let path = Array(url.path.utf8CString)
            guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
            withUnsafeMutableBytes(of: &address.sun_path) { raw in
                path.withUnsafeBytes { raw.copyMemory(from: $0) }
            }
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, listen(listener, 16) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

            let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptOne() }
            source.resume()
            self.source = source
        }

        func stop() {
            source?.cancel()
            if listener >= 0 {
                close(listener)
            }
            unlink(url.path)
        }

        private func acceptOne() {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            guard let request = readRequest(client) else {
                close(client)
                return
            }
            let handler = handler
            let queue = queue
            DispatchQueue.main.async {
                let response = MainActor.assumeIsolated { handler(request) }
                queue.async {
                    var line = response
                    line.append(0x0A)
                    line.withUnsafeBytes { _ = write(client, $0.baseAddress, $0.count) }
                    close(client)
                }
            }
        }

        private func readRequest(_ client: Int32) -> ControlRequest? {
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while !data.contains(0x0A) {
                let count = read(client, &buffer, buffer.count)
                if count <= 0 {
                    break
                }
                data.append(buffer, count: count)
            }
            let line = data.split(separator: 0x0A).first ?? data[...]
            return try? JSONDecoder().decode(ControlRequest.self, from: Data(line))
        }
    }
#endif
