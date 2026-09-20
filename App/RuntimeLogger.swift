import Foundation
import os

final class RuntimeLogger {
    static let shared = RuntimeLogger()
    private let logger = Logger(subsystem: "com.r347h4ck3r.bo2ioscs", category: "runtime")
    private let queue = DispatchQueue(label: "bo2ioscs.logger")
    private var logURL: URL?

    private init() {
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let dir = docs.appendingPathComponent("Logs", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            logURL = dir.appendingPathComponent("runtime.log")
        }
    }

    func stage(_ name: String, detail: String = "") {
        let line = detail.isEmpty ? name : name + " " + detail
        logger.notice("\(line, privacy: .public)")
        NSLog("%@", line)
        queue.async { [logURL] in
            guard let url = logURL, let data = (line + "\n").data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
