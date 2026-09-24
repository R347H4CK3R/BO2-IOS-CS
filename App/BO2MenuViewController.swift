import UIKit
import GameController

struct BO2LaunchConfiguration {
    enum Mode: String { case multiplayer, zombies }
    let mode: Mode
    let map: String
    let gameMode: String
}

final class BO2MenuViewController: UIViewController {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let stack = UIStackView()
    private var selectedMode: BO2LaunchConfiguration.Mode = .multiplayer
    private var selectedMap = "Hijacked"
    private var selectedGameMode = "Team Deathmatch"
    private let multiplayerMaps = ["Hijacked", "Raid", "Standoff", "Slums", "Express", "Carrier", "Meltdown", "Plaza", "Nuketown 2025"]
    private let zombieMaps = ["Tranzit", "Bus Depot", "Town", "Farm"]
    private let multiplayerModes = ["Team Deathmatch", "Free-for-All", "Domination", "Search & Destroy", "Hardpoint", "Kill Confirmed", "Capture the Flag"]
    private let zombieModes = ["Survival", "Grief"]

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        showRoot()
        installControllerNavigation()
        RuntimeLog.stage("BO2_FRONTEND_READY")
    }

    private func buildUI() {
        view.backgroundColor = UIColor(red: 0.025, green: 0.035, blue: 0.04, alpha: 1)
        let accent = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: view.bounds.height))
        accent.autoresizingMask = [.flexibleHeight]
        accent.backgroundColor = UIColor(red: 0.92, green: 0.40, blue: 0.08, alpha: 1)
        view.addSubview(accent)

        titleLabel.frame = CGRect(x: 52, y: 42, width: 700, height: 55)
        titleLabel.autoresizingMask = [.flexibleWidth]
        titleLabel.font = .systemFont(ofSize: 34, weight: .black)
        titleLabel.textColor = .white
        view.addSubview(titleLabel)

        detailLabel.frame = CGRect(x: 54, y: 98, width: 760, height: 30)
        detailLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        view.addSubview(detailLabel)

        stack.axis = .vertical
        stack.spacing = 5
        stack.frame = CGRect(x: 52, y: 145, width: 390, height: 390)
        view.addSubview(stack)

        let footer = UILabel(frame: CGRect(x: 54, y: view.bounds.height - 42, width: 760, height: 24))
        footer.autoresizingMask = [.flexibleTopMargin, .flexibleWidth]
        footer.text = "SELECT   •   BACK   •   TOUCH + CONTROLLER"
        footer.textColor = UIColor.white.withAlphaComponent(0.35)
        footer.font = .systemFont(ofSize: 11, weight: .bold)
        view.addSubview(footer)
    }

    private func menuButton(_ text: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(text.uppercased(), for: .normal)
        b.contentHorizontalAlignment = .left
        b.titleLabel?.font = .systemFont(ofSize: 21, weight: .bold)
        b.setTitleColor(.white, for: .normal)
        b.setTitleColor(UIColor(red: 1.0, green: 0.52, blue: 0.12, alpha: 1), for: .highlighted)
        b.heightAnchor.constraint(equalToConstant: 45).isActive = true
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func clearMenu() { stack.arrangedSubviews.forEach { $0.removeFromSuperview() } }

    private func showRoot() {
        clearMenu()
        titleLabel.text = "BLACK OPS II"
        detailLabel.text = "SELECT MODE"
        stack.addArrangedSubview(menuButton("Multiplayer", action: #selector(openMultiplayer)))
        stack.addArrangedSubview(menuButton("Zombies", action: #selector(openZombies)))
        stack.addArrangedSubview(menuButton("Controls", action: #selector(showControls)))
    }

    @objc private func openMultiplayer() {
        selectedMode = .multiplayer
        selectedMap = multiplayerMaps[0]
        selectedGameMode = multiplayerModes[0]
        showLobby()
    }

    @objc private func openZombies() {
        selectedMode = .zombies
        selectedMap = zombieMaps[0]
        selectedGameMode = zombieModes[0]
        showLobby()
    }

    private func showLobby() {
        clearMenu()
        titleLabel.text = selectedMode == .multiplayer ? "MULTIPLAYER" : "ZOMBIES"
        detailLabel.text = "\(selectedGameMode.uppercased())  •  \(selectedMap.uppercased())"
        stack.addArrangedSubview(menuButton("Start Match", action: #selector(startMatch)))
        stack.addArrangedSubview(menuButton("Game Mode", action: #selector(selectGameMode)))
        stack.addArrangedSubview(menuButton("Map", action: #selector(selectMap)))
        stack.addArrangedSubview(menuButton("Controls", action: #selector(showControls)))
        stack.addArrangedSubview(menuButton("Back", action: #selector(backToRoot)))
    }

    @objc private func selectMap() {
        let values = selectedMode == .multiplayer ? multiplayerMaps : zombieMaps
        showChoice(title: "SELECT MAP", values: values) { [weak self] value in self?.selectedMap = value; self?.showLobby() }
    }

    @objc private func selectGameMode() {
        let values = selectedMode == .multiplayer ? multiplayerModes : zombieModes
        showChoice(title: "SELECT GAME MODE", values: values) { [weak self] value in self?.selectedGameMode = value; self?.showLobby() }
    }

    private func showChoice(title: String, values: [String], selected: @escaping (String) -> Void) {
        clearMenu()
        titleLabel.text = title
        detailLabel.text = selectedMode.rawValue.uppercased()
        for value in values.prefix(8) {
            let b = menuButton(value, action: #selector(choicePressed(_:)))
            b.accessibilityIdentifier = value
            stack.addArrangedSubview(b)
        }
        pendingChoice = selected
        stack.addArrangedSubview(menuButton("Back", action: #selector(returnToLobby)))
    }

    private var pendingChoice: ((String) -> Void)?
    @objc private func choicePressed(_ sender: UIButton) {
        guard let value = sender.accessibilityIdentifier else { return }
        pendingChoice?(value)
        pendingChoice = nil
    }
    @objc private func returnToLobby() { pendingChoice = nil; showLobby() }
    @objc private func backToRoot() { showRoot() }

    @objc private func startMatch() {
        let config = BO2LaunchConfiguration(mode: selectedMode, map: selectedMap, gameMode: selectedGameMode)
        RuntimeLog.stage("MENU_START_\(selectedMode.rawValue.uppercased())_\(selectedMap.uppercased().replacingOccurrences(of: " ", with: "_"))")
        let game = GameViewController(configuration: config)
        game.modalPresentationStyle = .fullScreen
        present(game, animated: false)
    }

    @objc private func showControls() {
        let text = "Touch: left joystick movement, right-side swipe aim, ADS, fire, reload, jump, crouch, use and weapon controls. Controller: left/right sticks, LT aim, RT fire, A jump, B crouch, X reload/use, Y weapon swap, Menu pause."
        let a = UIAlertController(title: "CONTROLS", message: text, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    private func installControllerNavigation() {
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let controller = note.object as? GCController, let pad = controller.extendedGamepad else { return }
            pad.buttonA.pressedChangedHandler = { _,_,pressed in if pressed { DispatchQueue.main.async { self.activateFocusedButton() } } }
            pad.buttonB.pressedChangedHandler = { _,_,pressed in if pressed { DispatchQueue.main.async { self.backToRoot() } } }
        }
    }

    private func activateFocusedButton() {
        if let b = stack.arrangedSubviews.compactMap({ $0 as? UIButton }).first { b.sendActions(for: .touchUpInside) }
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { [.landscapeLeft, .landscapeRight] }
}
