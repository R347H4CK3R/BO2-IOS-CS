import Foundation

struct RuntimePlayerPlacement {
    let team: Team
    let x: Double
    let y: Double
    let z: Double

    static func spawn(for team: Team, from spawnPoints: [RuntimeSpawnPoint]) -> RuntimePlayerPlacement? {
        guard let spawn = spawnPoints.first(where: { $0.team == team }) else { return nil }
        return RuntimePlayerPlacement(team: team, x: spawn.x, y: spawn.y, z: spawn.z)
    }

    func isWithinObjective(_ objective: RuntimeObjective) -> Bool {
        let dx = x - objective.x
        let dy = y - objective.y
        let dz = z - objective.z
        return dx * dx + dy * dy + dz * dz <= objective.radius * objective.radius
    }
}
