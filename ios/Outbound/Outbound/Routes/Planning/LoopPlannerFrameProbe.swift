#if DEBUG
import MapKit
import SwiftUI

/// Opt-in, frame-by-frame native evidence. It never publishes SwiftUI state or
/// changes presentation, camera, location or networking behavior.
struct LoopPlannerFrameProbe: UIViewRepresentable {
    let presentation: LoopPlanningPresentation
    func makeUIView(context: Context) -> ProbeView { ProbeView(presentation: presentation) }
    func updateUIView(_ view: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        private let presentation: LoopPlanningPresentation
        private var displayLink: CADisplayLink?
        private var sheetID: ObjectIdentifier?
        private var observedSheetID: ObjectIdentifier?
        private var mapID: ObjectIdentifier?
        private var presentationStarts = 0
        private var baselineY: CGFloat?
        private var samples = 0, sheetReplacements = 0, sheetMissing = 0, sheetMoves = 0
        private var mapReplacements = 0, mapMissing = 0, inputStateLost = 0
        init(presentation: LoopPlanningPresentation) {
            self.presentation = presentation
            super.init(frame: .zero)
            isAccessibilityElement = true
            accessibilityIdentifier = "loop.stability"
            accessibilityLabel = "Planner frame evidence"
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            displayLink?.invalidate(); displayLink = nil
            guard window != nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(sample))
            link.add(to: .main, forMode: .common); displayLink = link
        }
        @objc private func sample() {
            guard let window else { return }
            var cursor = window.rootViewController
            var planner: UIViewController?
            while let current = cursor {
                if String(describing: type(of: current)).contains("StableSheetHostingController") { planner = current }
                cursor = current.presentedViewController
            }
            // The library is also a stable host. The final stable host owns
            // this full-screen planner and its actual SwiftUI input sheet.
            guard let owner = planner else { return }
            let sheet = owner.presentedViewController
            if let sheet, observedSheetID != ObjectIdentifier(sheet) {
                observedSheetID = ObjectIdentifier(sheet)
                presentationStarts += 1
                StartupUIStabilityDiagnostics.emit("ui_stability component=loop_native event=input_controller_seen count=\(presentationStarts) transitioning=\(sheet.isBeingPresented || sheet.transitionCoordinator != nil)")
            }
            let map = findMap(owner.view)
            if let map {
                if let mapID, ObjectIdentifier(map) != mapID {
                    mapReplacements += 1
                    self.mapID = ObjectIdentifier(map)
                    StartupUIStabilityDiagnostics.emit("ui_stability component=loop_native event=map_replaced count=\(mapReplacements)")
                } else if mapID == nil {
                    mapID = ObjectIdentifier(map)
                    StartupUIStabilityDiagnostics.emit("ui_stability component=loop_native event=map_seen")
                }
            } else if mapID != nil { mapMissing += 1 }
            // Ignore the single intended entry transition. Once settled, every
            // missing/replaced sheet and out-of-position frame stays recorded.
            if sheetID == nil, let sheet, !sheet.isBeingPresented, sheet.transitionCoordinator == nil {
                sheetID = ObjectIdentifier(sheet)
                baselineY = sheet.view.convert(sheet.view.bounds, to: window).minY
            }
            guard sheetID != nil else { return }
            samples += 1
            if case .inputs = presentation.sheet {} else { inputStateLost += 1 }
            if let sheet {
                if ObjectIdentifier(sheet) != sheetID { sheetReplacements += 1 }
                let bounds = sheet.view.layer.presentation()?.frame ?? sheet.view.frame
                let originY = sheet.view.superview?.convert(bounds, to: window).minY ?? bounds.minY
                if let baselineY, abs(originY - baselineY) > 8 { sheetMoves += 1 }
            } else { sheetMissing += 1 }
            accessibilityValue = "samples=\(samples);presentationStarts=\(presentationStarts);sheetReplacements=\(sheetReplacements);sheetMissing=\(sheetMissing);sheetMoves=\(sheetMoves);inputStateLost=\(inputStateLost);mapReplacements=\(mapReplacements);mapMissing=\(mapMissing);start=\(presentation.session.start != nil);parks=\(presentation.session.recommendations.count)"
            if samples % 60 == 0 { StartupUIStabilityDiagnostics.emit("ui_stability component=loop_native event=frame_summary " + (accessibilityValue ?? "")) }
        }
        private func findMap(_ view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            for child in view.subviews { if let map = findMap(child) { return map } }
            return nil
        }
        deinit { displayLink?.invalidate() }
    }
}
#endif
