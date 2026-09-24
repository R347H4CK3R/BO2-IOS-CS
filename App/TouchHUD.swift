import UIKit

final class TouchHUD: UIView {
    var onAction: ((String) -> Void)?
    var onMove: ((CGVector) -> Void)?
    var onLook: ((CGVector) -> Void)?

    private let stick = UIView()
    private let labels = ["FIRE", "ADS", "RELOAD", "JUMP", "CROUCH", "USE", "SWAP", "MOD"]
    private var moveTouch: UITouch?
    private var lookTouch: UITouch?
    private var moveOrigin = CGPoint.zero
    private var lookPrevious = CGPoint.zero

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
            b.backgroundColor = UIColor.black.withAlphaComponent(0.28)
            b.layer.borderWidth = 1
            b.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if point.x < bounds.midX, moveTouch == nil {
                moveTouch = touch
                moveOrigin = point
            } else if point.x >= bounds.midX, lookTouch == nil {
                lookTouch = touch
                lookPrevious = point
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if touch === moveTouch {
                let dx = point.x - moveOrigin.x
                let dy = point.y - moveOrigin.y
                let radius: CGFloat = 60
                onMove?(CGVector(dx: max(-1, min(1, dx / radius)),
                                 dy: max(-1, min(1, -dy / radius))))
            } else if touch === lookTouch {
                let dx = point.x - lookPrevious.x
                let dy = point.y - lookPrevious.y
                lookPrevious = point
                onLook?(CGVector(dx: dx, dy: dy))
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { endTouches(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { endTouches(touches) }

    private func endTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if touch === moveTouch {
                moveTouch = nil
                onMove?(.zero)
            }
            if touch === lookTouch { lookTouch = nil }
        }
    }

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
