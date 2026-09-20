import UIKit

final class TouchHUD: UIView {
    var onAction: ((String) -> Void)?
    private let stick = UIView()
    private let labels = ["FIRE", "RELOAD", "JUMP", "CROUCH", "USE", "SWAP", "SCORE", "PAUSE"]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        stick.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        stick.layer.cornerRadius = 42
        addSubview(stick)
        for (i, title) in labels.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
            b.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            b.layer.cornerRadius = 22
            b.tag = 100 + i
            b.addTarget(self, action: #selector(buttonPressed(_:)), for: .touchUpInside)
            addSubview(b)
        }
        RuntimeLog.stage("INPUT_INIT")
    }

    @objc private func buttonPressed(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        onAction?(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let safe = safeAreaInsets
        stick.frame = CGRect(x: safe.left + 32, y: bounds.height - safe.bottom - 116, width: 84, height: 84)
        let right = bounds.width - safe.right
        for i in 0..<labels.count {
            guard let b = viewWithTag(100 + i) else { continue }
            let col = i % 4
            let row = i / 4
            b.frame = CGRect(x: right - CGFloat(4-col) * 66,
                             y: bounds.height - safe.bottom - 54 - CGFloat(row) * 58,
                             width: 60, height: 44)
        }
    }
}
