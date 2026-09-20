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

    func testPlayerAmmoAndReloadCycle() {
        let weapon = WeaponDefinition(id: "test_rifle", damage: 30, fireRate: 9,
                                      magazineCapacity: 2, reserveAmmo: 3,
                                      reloadDuration: 1, recoil: 0.9, spread: 0.02)
        let state = PlayerWeaponState(definition: weapon)
        XCTAssertTrue(state.fire())
        XCTAssertTrue(state.fire())
        XCTAssertFalse(state.fire())
        XCTAssertEqual(state.magazine, 0)
        XCTAssertTrue(state.beginReload())
        state.tick(dt: 0.5)
        XCTAssertTrue(state.isReloading)
        state.tick(dt: 0.5)
        XCTAssertFalse(state.isReloading)
        XCTAssertEqual(state.magazine, 2)
        XCTAssertEqual(state.reserve, 1)
    }

    func testPlantAndDetonationScoresAttack() {
        let objective = RuntimeObjective(type: "plant_defuse", x: 0, y: 0, z: 0,
                                         radius: 2.5, plantDuration: 1, fuseDuration: 2,
                                         defuseDuration: 1)
        let sim = MatchSimulation(botCount: 4, objective: objective)
        sim.beginPlant()
        sim.tick(dt: 1)
        XCTAssertEqual(sim.objectiveState, .planted)
        sim.tick(dt: 2)
        XCTAssertEqual(sim.objectiveState, .detonated)
        XCTAssertEqual(sim.scoreAttack, 1)
    }

    func testPlantAndDefuseScoresDefense() {
        let objective = RuntimeObjective(type: "plant_defuse", x: 0, y: 0, z: 0,
                                         radius: 2.5, plantDuration: 1, fuseDuration: 10,
                                         defuseDuration: 1)
        let sim = MatchSimulation(botCount: 4, objective: objective)
        sim.beginPlant()
        sim.tick(dt: 1)
        sim.beginDefuse()
        sim.tick(dt: 1)
        XCTAssertEqual(sim.objectiveState, .defused)
        XCTAssertEqual(sim.scoreDefense, 1)
    }
}
