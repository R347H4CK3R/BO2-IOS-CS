import Foundation

struct WeaponDefinition: Codable {
    let id: String
    let damage: Double
    let fireRate: Double
    let magazineCapacity: Int
    let reserveAmmo: Int
    let reloadDuration: Double
    let recoil: Double
    let spread: Double
}

enum Team: String, Codable { case attack, defense }

final class BotState {
    let id: Int
    let team: Team
    var health = 100
    var shots = 0
    init(id: Int, team: Team) { self.id = id; self.team = team }
}

final class MatchSimulation {
    private(set) var round = 1
    private(set) var scoreAttack = 0
    private(set) var scoreDefense = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var shotsFired = 0
    private(set) var objectiveTicks = 0
    let bots: [BotState]

    init(botCount: Int = 4) {
        bots = (0..<botCount).map { BotState(id: $0, team: $0.isMultiple(of: 2) ? .attack : .defense) }
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        objectiveTicks += 1
        if Int(elapsed * 4) > shotsFired {
            shotsFired += 1
            if !bots.isEmpty { bots[shotsFired % bots.count].shots += 1 }
        }
        if elapsed >= 120 {
            scoreAttack += 1
            round += 1
            elapsed = 0
        }
    }
}
