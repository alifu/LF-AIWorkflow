//
//  BoundedFile.swift
//  LF-AIWorkflow
//

import Foundation

nonisolated enum BoundedFile {
    struct Text: Sendable, Equatable {
        let text: String
        let isTruncated: Bool
    }

    struct NotRegularFile: Error, Sendable, Equatable { let path: String }

    /// Reads at most `maxBytes` of a regular file as UTF-8 (invalid bytes become U+FFFD). Runs off the main actor.
    /// Opens with `O_NONBLOCK` (a FIFO cannot block the open), then `fstat`s the descriptor
    /// and throws `NotRegularFile` for FIFOs, devices, sockets and directories.
    /// Complexity: O(maxBytes) time, O(maxBytes) space
    @concurrent static func readText(_ url: URL, maxBytes: Int) async throws -> Text {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            close(descriptor)
            throw NotRegularFile(path: url.path)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        let truncated = data.count > maxBytes
        return Text(text: String(decoding: data.prefix(maxBytes), as: UTF8.self), isTruncated: truncated)
    }
}
