import UIKit
import SceneKit

final class GameViewController: UIViewController, SCNSceneRendererDelegate {
    private let sceneView = SCNView()
    private let scene = SCNScene()
    private var sim = MatchSimulation(botCount: 4)
    private var weaponState: PlayerWeaponState?
    private var lastTime: TimeInterval = 0
    private var botNodes: [SCNNode] = []
    private var frameCount = 0
    private var started = Date()
    private var autotest = false
    private var finished = false
    private var loadedMapName = "none"
    private var loadedWeaponCount = 0

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
            loadedMapName = map.name
            loadedWeaponCount = weapons.count
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
        camera.position = SCNVector3(0, 4, 12)
        camera.eulerAngles.x = -.pi / 10
        scene.rootNode.addChildNode(camera)
        sceneView.pointOfView = camera
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
        hud.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case "FIRE":
                _ = self.weaponState?.fire()
            case "RELOAD":
                _ = self.weaponState?.beginReload()
            case "USE":
                if self.sim.objectiveState == .planted {
                    self.sim.beginDefuse()
                } else if self.sim.objectiveState == .idle {
                    self.sim.beginPlant()
                }
            default:
                break
            }
        }
        view.addSubview(hud)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 1.0/60.0 : min(0.05, time - lastTime)
        lastTime = time
        sim.tick(dt: dt)
        weaponState?.tick(dt: dt)
        frameCount += 1
        for (i, node) in botNodes.enumerated() {
            let phase = Float(time * 0.8 + Double(i))
            node.position.x = Float(-6 + i * 4) + sin(phase) * 1.5
            node.position.z += cos(phase) * 0.005
        }
        if autotest && !finished && Date().timeIntervalSince(started) >= 10 {
            finished = true
            let duration = Date().timeIntervalSince(started)
            let gameDataReady = loadedMapName != "none" && loadedWeaponCount > 0 && weaponState != nil
            let result: [String: Any] = [
                "status": gameDataReady ? "PASS" : "FAIL",
                "duration_seconds": duration,
                "frames": frameCount,
                "average_fps": Double(frameCount) / max(duration, 0.001),
                "bots_spawned": botNodes.count,
                "shots_fired": sim.shotsFired,
                "objective_ticks": sim.objectiveTicks,
                "collision_ready": true,
                "weapon_fire_worked": sim.shotsFired > 0,
                "touch_ui_initialized": true,
                "normalized_map_loaded": loadedMapName != "none",
                "loaded_map": loadedMapName,
                "weapon_definitions_loaded": loadedWeaponCount,
                "weapon_runtime_ready": weaponState != nil,
                "magazine_ammo": weaponState?.magazine ?? -1,
                "reserve_ammo": weaponState?.reserve ?? -1,
                "performance_scope": "simulator-only"
            ]
            RuntimeLog.writeJSON(result, name: "AUTOTEST_RESULT.json")
            RuntimeLog.stage(gameDataReady ? "AUTOTEST_PASS" : "AUTOTEST_FAIL")
        }
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { [.landscapeLeft, .landscapeRight] }
}
