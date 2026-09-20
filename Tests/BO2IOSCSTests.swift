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

    func testWeaponDamageAndEliminationRound() {
        let weapon = WeaponDefinition(id: "test_rifle", damage: 100, fireRate: 9,
                                      magazineCapacity: 30, reserveAmmo: 90,
                                      reloadDuration: 2.3, recoil: 0.9, spread: 0.02)
        let sim = MatchSimulation(botCount: 4)
        XCTAssertTrue(sim.fire(weapon: weapon, from: 0, at: 1))
        XCTAssertTrue(sim.fire(weapon: weapon, from: 2, at: 3))
        XCTAssertEqual(sim.scoreAttack, 1)
        XCTAssertEqual(sim.round, 2)
        XCTAssertEqual(sim.bots[1].deaths, 1)
        XCTAssertEqual(sim.bots[3].deaths, 1)
        XCTAssertTrue(sim.bots.allSatisfy { $0.health == 100 })
    }

    func testFriendlyFireIsRejected() {
        let weapon = WeaponDefinition(id: "test_rifle", damage: 30, fireRate: 9,
                                      magazineCapacity: 30, reserveAmmo: 90,
                                      reloadDuration: 2.3, recoil: 0.9, spread: 0.02)
        let sim = MatchSimulation(botCount: 4)
        XCTAssertFalse(sim.fire(weapon: weapon, from: 0, at: 2))
        XCTAssertEqual(sim.bots[2].health, 100)
    }
}
