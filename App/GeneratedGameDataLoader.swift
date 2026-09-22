import Foundation

struct GeneratedGameDataBuildManifest: Decodable {
    let schema: Int
    let runtime_ready_count: Int
    let deferred: [String: Int]
}

enum GeneratedGameDataLoader {
    static func loadBuildManifest(bundle: Bundle = .main) -> GeneratedGameDataBuildManifest? {
        let candidates: [URL?] = [
            bundle.url(forResource: "BUILD_MANIFEST", withExtension: "json", subdirectory: "GeneratedGameData"),
            bundle.url(forResource: "BUILD_MANIFEST", withExtension: "json")
        ]
        for case let url? in candidates {
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(GeneratedGameDataBuildManifest.self, from: data)
            else { continue }
            return manifest
        }
        return nil
    }
}
