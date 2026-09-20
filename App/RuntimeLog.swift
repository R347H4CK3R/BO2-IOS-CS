import Foundation

enum RuntimeLog {
    static func stage(_ value: String) {
        NSLog("[BO2IOSCS] %@", value)
        append(value)
    }

    static func append(_ value: String) {
        do {
            let fm = FileManager.default
            let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = docs.appendingPathComponent("Logs", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("runtime.log")
            let line = ISO8601DateFormatter().string(from: Date()) + " " + value + "\n"
            if fm.fileExists(atPath: file.path), let h = try? FileHandle(forWritingTo: file) {
                try h.seekToEnd()
                try h.write(contentsOf: Data(line.utf8))
                try h.close()
            } else {
                try Data(line.utf8).write(to: file)
            }
        } catch {
            NSLog("[BO2IOSCS] logging error: %@", String(describing: error))
        }
    }

    static func writeJSON(_ object: [String: Any], name: String) {
        do {
            let fm = FileManager.default
            let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = docs.appendingPathComponent("Logs", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: dir.appendingPathComponent(name))
        } catch {
            NSLog("[BO2IOSCS] json write error: %@", String(describing: error))
        }
    }
}
