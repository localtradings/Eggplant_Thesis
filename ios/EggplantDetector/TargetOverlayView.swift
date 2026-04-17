import UIKit

final class TargetOverlayView: UIView {
    var targetState: SelectedTargetState = .none {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        let target: (SelectedPlantTarget, Bool)?
        switch targetState {
        case let .selected(selectedTarget):
            target = (selectedTarget, false)
        case let .lost(previousTarget, _):
            guard let previousTarget else { return }
            target = (previousTarget, true)
        case .none:
            return
        }

        guard let target else { return }
        let viewRect = PreviewTargetMapper.viewRect(for: target.0.box, in: bounds)
        let path = UIBezierPath(roundedRect: viewRect, cornerRadius: 20)

        let fillColor = target.1
            ? UIColor(white: 0.86, alpha: 0.14)
            : UIColor(red: 0.30, green: 0.67, blue: 0.34, alpha: 0.18)
        fillColor.setFill()
        path.fill()

        let strokeColor = target.1
            ? UIColor(white: 0.86, alpha: 0.86)
            : UIColor(red: 0.30, green: 0.67, blue: 0.34, alpha: 0.96)
        strokeColor.setStroke()
        path.lineWidth = 4
        if target.1 {
            path.setLineDash([12, 8], count: 2, phase: 0)
        }
        path.stroke()
    }
}
