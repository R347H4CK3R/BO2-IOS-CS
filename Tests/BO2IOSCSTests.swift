import XCTest
@testable import BO2IOSCS

final class BO2IOSCSTests: XCTestCase {
    func testSimulationAdvances() {
        let sim = MatchSimulation(botCount: 4)
        for _ in 0..<120 { sim.tick(dt: 1.0 / 60.0) }
        XCTAssertEqual(sim.bots.count, 4)
        XCTAssertGreaterThan(sim.shotsFired, 0)
        XCTAssertGreaterThan(sim.objectiveTicks, 0)
    }

    func testWeaponDefinitionDecodes() throws {
        let json = #"{"id":"rifle","damage":30,"fireRate":9,"magazineCapacity":30,"reserveAmmo":90,"reloadDuration":2.3,"recoil":0.9,"spread":0.02}"#
        let weapon = try JSONDecoder().decode(WeaponDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(weapon.id, "rifle")
        XCTAssertEqual(weapon.magazineCapacity, 30)
    }
}
