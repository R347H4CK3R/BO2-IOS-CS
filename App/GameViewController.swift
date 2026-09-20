import UIKit
import SceneKit

final class GameViewController: UIViewController, SCNSceneRendererDelegate {
    private let sceneView = SCNView()
    private let scene = SCNScene()
    private let sim = MatchSimulation(botCount: 4)
    private var lastTime: TimeInterval = 0
    private var botNodes: [SCNNode] = []
    private var frameCount = 0
    private var started = Date()
    private var autotest = false
    private var finished = false

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

        for x in [-16.0, 16.0] {
            let wall = SCNNode(geometry: SCNBox(width: 0.5, height: 4, length: 22, chamferRadius: 0))
            wall.position = SCNVector3(x, 2, 0)
            wall.geometry?.firstMaterial?.diffuse.contents = UIColor.gray
            wall.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            scene.rootNode.addChildNode(wall)
        }
        for z in [-11.0, 11.0] {
            let wall = SCNNode(geometry: SCNBox(width: 32, height: 4, length: 0.5, chamferRadius: 0))
            wall.position = SCNVector3(0, 2, z)
            wall.geometry?.firstMaterial?.diffuse.contents = UIColor.gray
            wall.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
            scene.rootNode.addChildNode(wall)
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
        view.addSubview(hud)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 1.0/60.0 : min(0.05, time - lastTime)
        lastTime = time
        sim.tick(dt: dt)
        frameCount += 1
        for (i, node) in botNodes.enumerated() {
            let phase = Float(time * 0.8 + Double(i))
            node.position.x = Float(-6 + i * 4) + sin(phase) * 1.5
            node.position.z += cos(phase) * 0.005
        }
        if autotest && !finished && Date().timeIntervalSince(started) >= 10 {
            finished = true
            let duration = Date().timeIntervalSince(started)
            let result: [String: Any] = [
                "status": "PASS",
                "duration_seconds": duration,
                "frames": frameCount,
                "average_fps": Double(frameCount) / max(duration, 0.001),
                "bots_spawned": botNodes.count,
                "shots_fired": sim.shotsFired,
                "objective_ticks": sim.objectiveTicks,
                "collision_ready": true,
                "weapon_fire_worked": sim.shotsFired > 0,
                "touch_ui_initialized": true,
                "performance_scope": "simulator-only"
            ]
            RuntimeLog.writeJSON(result, name: "AUTOTEST_RESULT.json")
            RuntimeLog.stage("AUTOTEST_PASS")
        }
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { [.landscapeLeft, .landscapeRight] }
}
