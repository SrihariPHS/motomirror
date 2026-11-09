import Foundation

public enum BinaryLocator {
    public static func searchDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var directories: [String] = []
        if let path = environment["PATH"] {
            directories.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        directories.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools"
        ])
        if let resourcePath = Bundle.main.resourceURL?.appendingPathComponent("bin").path {
            directories.append(resourcePath)
        }

        var seen = Set<String>()
        return directories.filter { seen.insert($0).inserted }
    }

    public static func locate(
        _ name: String,
        override: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let fileManager = FileManager.default
        if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        for directory in searchDirectories(environment: environment) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    public static func toolchain(
        adbOverride: String? = nil,
        scrcpyOverride: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Toolchain? {
        guard
            let adb = locate("adb", override: adbOverride, environment: environment),
            let scrcpy = locate("scrcpy", override: scrcpyOverride, environment: environment)
        else {
            return nil
        }
        let ffmpeg = locate("ffmpeg", environment: environment)
        return Toolchain(adb: adb, scrcpy: scrcpy, ffmpeg: ffmpeg)
    }
}
