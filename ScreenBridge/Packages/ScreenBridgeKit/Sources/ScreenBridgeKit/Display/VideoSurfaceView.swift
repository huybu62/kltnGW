import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Shows a `DisplayStreamController`'s video. Letterboxes to keep the
/// Host's aspect ratio.
public struct VideoSurfaceView {
    let layer: AVSampleBufferDisplayLayer

    public init(controller: DisplayStreamController) {
        self.layer = controller.displayLayer
    }
}

#if os(iOS)
extension VideoSurfaceView: UIViewRepresentable {
    public func makeUIView(context: Context) -> LayerHostingView {
        LayerHostingView(hosted: layer)
    }

    public func updateUIView(_ view: LayerHostingView, context: Context) {}
}

public final class LayerHostingView: UIView {
    private let hosted: CALayer

    init(hosted: CALayer) {
        self.hosted = hosted
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(hosted)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted.frame = bounds
        CATransaction.commit()
    }
}

#elseif os(macOS)
extension VideoSurfaceView: NSViewRepresentable {
    public func makeNSView(context: Context) -> LayerHostingView {
        LayerHostingView(hosted: layer)
    }

    public func updateNSView(_ view: LayerHostingView, context: Context) {}
}

public final class LayerHostingView: NSView {
    private let hosted: CALayer

    init(hosted: CALayer) {
        self.hosted = hosted
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(hosted)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted.frame = bounds
        CATransaction.commit()
    }
}
#endif
