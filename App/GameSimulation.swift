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

struct RuntimeSpawnPoint: Codable {
    let team: Team
    let x: Double
    let y: Double
    let z: Double
}

struct RuntimeBox: Codable {
    let x: Double
    let y: Double
    let z: Double
    let sx: Double
    let sy: Double
    let sz: Double
}

struct RuntimeMapDefinition: Codable {
    let name: String
    let format: String
    let worldScale: Double
    let spawnPoints: [RuntimeSpawnPoint]
    let boxes: [RuntimeBox]
}

enum GameDataLoader {
    static func loadValidationMap(bundle: Bundle = .main) throws -> RuntimeMapDefinition {
        guard let url = bundle.url(forResource: "validation_map", withExtension: "json") else {
            throw NSError(domain: "BO2IOSCS.GameData", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "validation_map.json missing from app bundle"])
        }
        let map = try JSONDecoder().decode(RuntimeMapDefinition.self, from: Data(contentsOf: url))
        guard map.format == "bo2ioscs-normalized-map-v1", !map.spawnPoints.isEmpty else {
            throw NSError(domain: "BO2IOSCS.GameData", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "unsupported or incomplete normalized map"])
        }
        return map
    }

    static func loadWeapons(bundle: Bundle = .main) throws -> [WeaponDefinition] {
        guard let url = bundle.url(forResource: "weapons", withExtension: "json") else {
            throw NSError(domain: "BO2IOSCS.GameData", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "weapons.json missing from app bundle"])
        }
        return try JSONDecoder().decode([WeaponDefinition].self, from: Data(contentsOf: url))
    }
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
