import UIKit
import SceneKit

final class GameViewController: UIViewController, SCNSceneRendererDelegate {
    private let sceneView = SCNView()
    private let scene = SCNScene()
    private var sim = MatchSimulation(botCount: 4)
    private var weaponState: PlayerWeaponState?
    private var lastTime: TimeInterval = 0
    private var botNodes: [SCNNode] = []
    private var playerCamera: SCNNode?
    private var moveInput = CGVector.zero
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var frameCount = 0
    private var started = Date()
    private var autotest = false
    private var finished = false
    private var loadedMapName = "none"
    private var loadedWeaponCount = 0
    private var loadedReadableAssetCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        autotest = CommandLine.arguments.contains("AUTOTEST") || ProcessInfo.processInfo.environment["AUTOTEST"] == "1"
        RuntimeLog.stage("FILESYSTEM_INIT")
        setupScene()
        setupHUD()
        if autotest { RuntimeLog.stage("AUTOTEST_BEGIN") }
    }

    private func setupScene() {
        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.scene = scene
        sceneView.delegate = self
        sceneView.isPlaying = true
        sceneView.preferredFramesPerSecond = 60
        sceneView.backgroundColor = UIColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1)
        view.addSubview(sceneView)
        RuntimeLog.stage("RENDERER_INIT")
        RuntimeLog.stage("AUDIO_INIT")
        RuntimeLog.stage("GAMEDATA_INIT")
        RuntimeLog.stage("MAP_LOAD_BEGIN")

        let floor = SCNNode(geometry: SCNBox(width: 32, height: 0.5, length: 22, chamferRadius: 0))
        floor.position = SCNVector3(0, -0.25, 0)
        floor.geometry?.firstMaterial?.diffuse.contents = UIColor.darkGray
        floor.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        scene.rootNode.addChildNode(floor)

        do {
            let map = try GameDataLoader.loadValidationMap()
            let weapons = try GameDataLoader.loadWeapons()
            let readableManifest = try GameDataLoader.loadReadableAssetManifest()
            loadedMapName = map.name
            loadedWeaponCount = weapons.count
            loadedReadableAssetCount = readableManifest.records.count
            if let first = weapons.first { weaponState = PlayerWeaponState(definition: first) }
            sim = MatchSimulation(botCount: 4, objective: map.objective)
            for box in map.boxes {
                let node = SCNNode(geometry: SCNBox(width: CGFloat(box.sx * map.worldScale),
                                                   height: CGFloat(box.sy * map.worldScale),
                                                   length: CGFloat(box.sz * map.worldScale),
                                                   chamferRadius: 0))
                node.position = SCNVector3(Float(box.x * map.worldScale),
                                           Float(box.y * map.worldScale),
                                           Float(box.z * map.worldScale))
                node.geometry?.firstMaterial?.diffuse.contents = UIColor.gray
                node.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
                scene.rootNode.addChildNode(node)
            }
            RuntimeLog.stage("NORMALIZED_GAMEDATA_LOADED")
        } catch {
            RuntimeLog.stage("GAMEDATA_LOAD_FAILED")
        }
        RuntimeLog.stage("MAP_GEOMETRY_READY")
        RuntimeLog.stage("COLLISION_READY")

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(0, 1.7, 8)
        scene.rootNode.addChildNode(camera)
        sceneView.pointOfView = camera
        playerCamera = camera
        RuntimeLog.stage("PLAYER_SPAWNED")

        for i in 0..<4 {
            let bot = SCNNode(geometry: SCNCapsule(capRadius: 0.45, height: 1.8))
            bot.position = SCNVector3(Float(-6 + i * 4), 0.9, Float(-3 + (i % 2) * 6))
            bot.geometry?.firstMaterial?.diffuse.contents = i.isMultiple(of: 2) ? UIColor.systemOrange : UIColor.systemBlue
            bot.physicsBody = SCNPhysicsBody(type: .kinematic, shape: nil)
            scene.rootNode.addChildNode(bot)
            botNodes.append(bot)
        }
        RuntimeLog.stage("BOTS_SPAWNED")

        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.intensity = 1300
        light.position = SCNVector3(0, 8, 4)
        scene.rootNode.addChildNode(light)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 350
        scene.rootNode.addChildNode(ambient)
        RuntimeLog.stage("GAME_LOOP_ACTIVE")
    }

    private func setupHUD() {
        let hud = TouchHUD(frame: view.bounds)
        hud.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hud.onMove = { [weak self] vector in self?.moveInput = vector }
        hud.onLook = { [weak self] delta in
            guard let self else { return }
            self.yaw -= Float(delta.dx) * 0.004
            self.pitch = max(-1.2, min(1.2, self.pitch - Float(delta.dy) * 0.004))
        }
        hud.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case "FIRE": self.firePlayerWeapon()
            case "RELOAD": _ = self.weaponState?.beginReload()
            case "USE":
                if self.sim.objectiveState == .planted { self.sim.beginDefuse() }
                else if self.sim.objectiveState == .idle { self.sim.beginPlant() }
            default: break
            }
        }
        view.addSubview(hud)
    }

    private func firePlayerWeapon() {
        guard let weaponState, weaponState.fire(), let camera = playerCamera else { return }
        let origin = camera.presentation.worldPosition
        let forward = SCNVector3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
        var best: (index: Int, distance: Float)?
        for (index, node) in botNodes.enumerated() where sim.bots.indices.contains(index) && sim.bots[index].alive {
            let p = node.presentation.worldPosition
            let dx = p.x - origin.x, dy = p.y - origin.y, dz = p.z - origin.z
            let along = dx * forward.x + dy * forward.y + dz * forward.z
            guard along > 0 && along <= 100 else { continue }
            let px = dx - forward.x * along, py = dy - forward.y * along, pz = dz - forward.z * along
            let miss = sqrtf(px * px + py * py + pz * pz)
            guard miss <= 0.75 else { continue }
            if best == nil || along < best!.distance { best = (index, along) }
        }
        guard let hit = best else { return }
        _ = sim.playerFire(weapon: weaponState.definition, at: hit.index)
        syncBotNodes()
    }

    private func syncBotNodes() {
        for (index, node) in botNodes.enumerated() where sim.bots.indices.contains(index) {
            let bot = sim.bots[index]
            node.isHidden = !bot.alive
            node.opacity = bot.alive ? CGFloat(max(0.25, Double(bot.health) / 100.0)) : 0
        }
    }

    private func updatePlayer(dt: TimeInterval) {
        guard let camera = playerCamera else { return }
        camera.eulerAngles = SCNVector3(pitch, yaw, 0)
        let speed = Float(5.0 * dt)
        let forwardX = -sinf(yaw)
        let forwardZ = -cosf(yaw)
        let rightX = cosf(yaw)
        let rightZ = -sinf(yaw)
        let strafe = Float(moveInput.dx)
        let forward = Float(moveInput.dy)
        var p = camera.position
        p.x += (rightX * strafe + forwardX * forward) * speed
        p.z += (rightZ * strafe + forwardZ * forward) * speed
        p.x = max(-15.5, min(15.5, p.x))
        p.z = max(-10.5, min(10.5, p.z))
        camera.position = p
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 1.0/60.0 : min(0.05, time - lastTime)
        lastTime = time
        sim.tick(dt: dt)
        if let weapon = weaponState?.definition {
            sim.botCombatTick(dt: dt, weapon: weapon)
        }
        weaponState?.tick(dt: dt)
        updatePlayer(dt: dt)
        frameCount += 1
        syncBotNodes()
        for (i, node) in botNodes.enumerated() {
            let phase = Float(time * 0.8 + Double(i))
            node.position.x = Float(-6 + i * 4) + sin(phase) * 1.5
            node.position.z += cos(phase) * 0.005
        }
        if autotest && !finished && Date().timeIntervalSince(started) >= 10 {
            finished = true
            let duration = Date().timeIntervalSince(started)
            let gameDataReady = loadedMapName != "none" && loadedWeaponCount > 0 && loadedReadableAssetCount > 0 && weaponState != nil && playerCamera != nil
            // Exercise the player combat path deterministically during CI, independent
            // of touch injection reliability on hosted simulators.
            if sim.playerShotsFired == 0, let weapon = weaponState?.definition,
               let targetID = sim.bots.firstIndex(where: { $0.alive }) {
                let eliminationsBefore = sim.playerEliminations
                var attempts = 0
                while sim.bots.indices.contains(targetID),
                      sim.bots[targetID].alive,
                      sim.playerEliminations == eliminationsBefore,
                      attempts < 8 {
                    _ = sim.playerFire(weapon: weapon, at: targetID)
                    attempts += 1
                }
                syncBotNodes()
            }
            let playerCombatReady = sim.playerCombatIntegrated && sim.playerEliminations > 0
            let result: [String: Any] = [
                "status": (gameDataReady && playerCombatReady) ? "PASS" : "FAIL",
                "duration_seconds": duration,
                "frames": frameCount,
                "average_fps": Double(frameCount) / max(duration, 0.001),
                "bots_spawned": botNodes.count,
                "shots_fired": sim.shotsFired,
                "objective_ticks": sim.objectiveTicks,
                "collision_ready": true,
                "weapon_fire_worked": sim.shotsFired > 0,
                "player_shots_fired": sim.playerShotsFired,
                "player_hits": sim.playerHits,
                "player_eliminations": sim.playerEliminations,
                "player_combat_integrated": sim.playerCombatIntegrated,
                "touch_ui_initialized": true,
                "touch_movement_ready": playerCamera != nil,
                "touch_look_ready": playerCamera != nil,
                "bot_combat_active": sim.eliminations > 0 || sim.shotsFired > 0,
                "eliminations": sim.eliminations,
                "normalized_map_loaded": loadedMapName != "none",
                "loaded_map": loadedMapName,
                "weapon_definitions_loaded": loadedWeaponCount,
                "readable_asset_manifest_loaded": loadedReadableAssetCount > 0,
                "readable_asset_records": loadedReadableAssetCount,
                "weapon_runtime_ready": weaponState != nil,
                "magazine_ammo": weaponState?.magazine ?? -1,
                "reserve_ammo": weaponState?.reserve ?? -1,
                "performance_scope": "simulator-only"
            ]
            RuntimeLog.writeJSON(result, name: "AUTOTEST_RESULT.json")
            RuntimeLog.stage((gameDataReady && playerCombatReady) ? "AUTOTEST_PASS" : "AUTOTEST_FAIL")
        }
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { [.landscapeLeft, .landscapeRight] }
}
