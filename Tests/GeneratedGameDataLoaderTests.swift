import XCTest
@testable import BO2IOSCS

final class GeneratedGameDataLoaderTests: XCTestCase {
    func testManifestDecoding() throws {
        let data = #"{"schema":1,"source_root":"x","generated_root":"y","runtime_ready":[],"runtime_ready_count":153,"deferred":{"encrypted_fastfile":288}}"#.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(GeneratedGameDataBuildManifest.self, from: data)
        XCTAssertEqual(manifest.schema, 1)
        XCTAssertEqual(manifest.runtime_ready_count, 153)
        XCTAssertEqual(manifest.deferred["encrypted_fastfile"], 288)
    }
}
