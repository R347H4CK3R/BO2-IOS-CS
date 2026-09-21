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


final class PlayerWeaponState {
    let definition: WeaponDefinition
    private(set) var magazine: Int
    private(set) var reserve: Int
    private(set) var isReloading = false
    private(set) var reloadRemaining: TimeInterval = 0

    init(definition: WeaponDefinition) {
        self.definition = definition
        magazine = definition.magazineCapacity
        reserve = definition.reserveAmmo
    }

    @discardableResult
    func fire() -> Bool {
        guard !isReloading, magazine > 0 else { return false }
        magazine -= 1
        return true
    }

    @discardableResult
    func beginReload() -> Bool {
        guard !isReloading, magazine < definition.magazineCapacity, reserve > 0 else { return false }
        isReloading = true
        reloadRemaining = definition.reloadDuration
        return true
    }

    func tick(dt: TimeInterval) {
        guard isReloading else { return }
        reloadRemaining = max(0, reloadRemaining - dt)
        guard reloadRemaining == 0 else { return }
        let needed = definition.magazineCapacity - magazine
        let transferred = min(needed, reserve)
        magazine += transferred
        reserve -= transferred
        isReloading = false
    }
}


struct ReadableAssetRecord: Codable {
    let originalPath: String
    let generatedOutputPath: String
    let detectedFormat: String
    let assetClass: String
    let size: Int
    let sha256: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case originalPath = "original_path"
        case generatedOutputPath = "generated_output_path"
        case detectedFormat = "detected_format"
        case assetClass = "asset_class"
        case size, sha256, status
    }
}

struct ReadableAssetManifest: Codable {
    let schema: String
    let policy: String
    let records: [ReadableAssetRecord]
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

struct RuntimeObjective: Codable {
    let type: String
    let x: Double
    let y: Double
    let z: Double
    let radius: Double
    let plantDuration: Double
    let fuseDuration: Double
    let defuseDuration: Double
}

struct RuntimeMapDefinition: Codable {
    let name: String
    let format: String
    let worldScale: Double
    let spawnPoints: [RuntimeSpawnPoint]
    let boxes: [RuntimeBox]
    let objective: RuntimeObjective?
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

    static func loadReadableAssetManifest(bundle: Bundle = .main) throws -> ReadableAssetManifest {
        guard let url = bundle.url(forResource: "readable_asset_manifest", withExtension: "json") else {
            throw NSError(domain: "BO2IOSCS.GameData", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "readable_asset_manifest.json missing from app bundle"])
        }
        let manifest = try JSONDecoder().decode(ReadableAssetManifest.self, from: Data(contentsOf: url))
        guard manifest.schema == "bo2ioscs-readable-asset-manifest-v1",
              !manifest.records.isEmpty,
              !manifest.records.contains(where: { $0.originalPath.lowercased().hasSuffix(".ff") }) else {
            throw NSError(domain: "BO2IOSCS.GameData", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "invalid or unsafe readable asset manifest"])
        }
        return manifest
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
enum ObjectiveState: String, Codable { case idle, planting, planted, defusing, detonated, defused }

final class BotState {
    let id: Int
    let team: Team
    var health = 100
    var shots = 0
    var deaths = 0
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var alive: Bool { health > 0 }
    init(id: Int, team: Team) { self.id = id; self.team = team }
}

final class MatchSimulation {
    private(set) var round = 1
    private(set) var scoreAttack = 0
    private(set) var scoreDefense = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var shotsFired = 0
    private(set) var objectiveTicks = 0
    private(set) var objectiveState: ObjectiveState = .idle
    private(set) var eliminations = 0
    private(set) var playerShotsFired = 0
    private(set) var playerHits = 0
    private(set) var playerEliminations = 0
    var playerCombatIntegrated: Bool { playerShotsFired > 0 && playerHits > 0 }
    private(set) var objectiveElapsed: TimeInterval = 0
    private var botCombatAccumulator: TimeInterval = 0
    let bots: [BotState]
    let objective: RuntimeObjective?
    private let spawnPoints: [RuntimeSpawnPoint]

    init(botCount: Int = 4, objective: RuntimeObjective? = nil, spawnPoints: [RuntimeSpawnPoint] = []) {
        self.objective = objective
        self.spawnPoints = spawnPoints
        bots = (0..<botCount).map { BotState(id: $0, team: $0.isMultiple(of: 2) ? .attack : .defense) }
        applySpawnPoints()
    }

    private func applySpawnPoints() {
        for bot in bots {
            let teamSpawns = spawnPoints.filter { $0.team == bot.team }
            guard !teamSpawns.isEmpty else { continue }
            let spawn = teamSpawns[(bot.id / 2) % teamSpawns.count]
            bot.x = spawn.x
            bot.y = spawn.y
            bot.z = spawn.z
        }
    }

    @discardableResult
    func fire(weapon: WeaponDefinition, from shooterID: Int, at targetID: Int) -> Bool {
        guard shooterID != targetID,
              bots.indices.contains(shooterID), bots.indices.contains(targetID),
              bots[shooterID].alive, bots[targetID].alive,
              bots[shooterID].team != bots[targetID].team else { return false }
        bots[shooterID].shots += 1
        shotsFired += 1
        bots[targetID].health = max(0, bots[targetID].health - Int(weapon.damage.rounded()))
        if bots[targetID].health == 0 {
            bots[targetID].deaths += 1
            eliminations += 1
            resolveEliminationRoundIfNeeded()
        }
        return true
    }

    @discardableResult
    func playerFire(weapon: WeaponDefinition, at targetID: Int) -> Bool {
        playerShotsFired += 1
        guard bots.indices.contains(targetID), bots[targetID].alive else { return false }
        let wasAlive = bots[targetID].alive
        bots[targetID].health = max(0, bots[targetID].health - Int(weapon.damage.rounded()))
        playerHits += 1
        shotsFired += 1
        if wasAlive && !bots[targetID].alive {
            bots[targetID].deaths += 1
            eliminations += 1
            playerEliminations += 1
            resolveEliminationRoundIfNeeded()
        }
        return true
    }

    private func resolveEliminationRoundIfNeeded() {
        let attackersAlive = bots.contains { $0.team == .attack && $0.alive }
        let defendersAlive = bots.contains { $0.team == .defense && $0.alive }
        if !defendersAlive && attackersAlive {
            scoreAttack += 1
            resetRound()
        } else if !attackersAlive && defendersAlive {
            scoreDefense += 1
            resetRound()
        }
    }

    private func resetRound() {
        round += 1
        elapsed = 0
        objectiveElapsed = 0
        objectiveState = .idle
        for bot in bots { bot.health = 100 }
        applySpawnPoints()
    }

    func botCombatTick(dt: TimeInterval, weapon: WeaponDefinition) {
        guard !bots.isEmpty else { return }
        botCombatAccumulator += dt
        let interval = max(0.1, 1.0 / max(weapon.fireRate, 0.1))
        while botCombatAccumulator >= interval {
            botCombatAccumulator -= interval
            let aliveShooters = bots.filter { $0.alive }
            for shooter in aliveShooters {
                guard let target = bots.first(where: { $0.alive && $0.team != shooter.team }) else { return }
                _ = fire(weapon: weapon, from: shooter.id, at: target.id)
            }
        }
    }

    func beginPlant() {
        guard objective != nil, objectiveState == .idle else { return }
        objectiveState = .planting
        objectiveElapsed = 0
    }

    func beginDefuse() {
        guard objective != nil, objectiveState == .planted else { return }
        objectiveState = .defusing
        objectiveElapsed = 0
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        objectiveTicks += 1
        if Int(elapsed * 4) > shotsFired {
            shotsFired += 1
            if !bots.isEmpty { bots[shotsFired % bots.count].shots += 1 }
        }
        if let objective {
            switch objectiveState {
            case .planting:
                objectiveElapsed += dt
                if objectiveElapsed >= objective.plantDuration {
                    objectiveState = .planted
                    objectiveElapsed = 0
                }
            case .planted:
                objectiveElapsed += dt
                if objectiveElapsed >= objective.fuseDuration {
                    objectiveState = .detonated
                    scoreAttack += 1
                }
            case .defusing:
                objectiveElapsed += dt
                if objectiveElapsed >= objective.defuseDuration {
                    objectiveState = .defused
                    scoreDefense += 1
                }
            case .idle, .detonated, .defused:
                break
            }
        }
        if elapsed >= 120 {
            if objectiveState == .idle { scoreDefense += 1 }
            resetRound()
        }
    }
}
