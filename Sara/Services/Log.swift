import Foundation

/// Debug builds only: a log file in the app container, for problems that happen away from Xcode.
/// Fetch it over the network:
/// `xcrun devicectl device copy from --device <id> --domain-type appDataContainer
/// --domain-identifier org.sara-home.Sara --source Library/Logs/sara.log --destination sara.log`
enum Log {
    private static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appending(path: "Logs/sara.log")
    private static let queue = DispatchQueue(label: "sara.log")

    static func write(_ message: String) {
        #if DEBUG
        let line = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current)) + " " + message + "\n"
        print(line, terminator: "")
        let url = url
        queue.async {
            let files = FileManager.default
            try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Past 1 MB, only the newer half stays.
            if let size = try? files.attributesOfItem(atPath: url.path)[.size] as? Int, size > 1_000_000,
               let data = try? Data(contentsOf: url) {
                try? data.suffix(500_000).write(to: url)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else {
                try? Data(line.utf8).write(to: url)
                return
            }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
        #endif
    }
}
