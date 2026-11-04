#if os(macOS)
import Foundation
import CoreGraphics
import CGVirtualDisplayPrivate

/// A software display that macOS treats like a real monitor. While this
/// object is alive the display exists (you can drag windows onto it and
/// arrange it in System Settings → Displays); releasing it removes it and
/// macOS moves its windows back.
final class VirtualDisplay: @unchecked Sendable {
    let displayID: CGDirectDisplayID
    let pixelWidth: Int
    let pixelHeight: Int
    private let display: CGVirtualDisplay

    /// - Parameters:
    ///   - pixelWidth/pixelHeight: native pixels of the receiving screen.
    ///   - hiDPI: offer a Retina ("looks like" half-size) mode, which is what
    ///     makes text sharp on an iPad.
    ///   - pixelsPerInch: used only to report a plausible physical size.
    /// Must be called on the main thread.
    ///   - serialNumber: distinct per receiving device, so two extra screens
    ///     are told apart and each keeps its place in Displays → Arrange.
    init?(name: String, pixelWidth: Int, pixelHeight: Int, refreshRate: Double = 60,
          hiDPI: Bool = true, pixelsPerInch: Double = 264, serialNumber: UInt32 = 1) {
        dispatchPrecondition(condition: .onQueue(.main))
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = name
        descriptor.maxPixelsWide = UInt32(pixelWidth)
        descriptor.maxPixelsHigh = UInt32(pixelHeight)
        descriptor.sizeInMillimeters = CGSize(width: Double(pixelWidth) / pixelsPerInch * 25.4,
                                              height: Double(pixelHeight) / pixelsPerInch * 25.4)
        // Arbitrary but stable IDs so macOS remembers the arrangement.
        descriptor.vendorID = 0x5342   // "SB"
        descriptor.productID = 0x0001
        descriptor.serialNum = serialNumber
        descriptor.terminationHandler = { _, _ in }

        guard let display = CGVirtualDisplay(descriptor: descriptor) else { return nil }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = hiDPI ? 1 : 0
        var modes = [CGVirtualDisplayMode(width: UInt32(pixelWidth), height: UInt32(pixelHeight),
                                          refreshRate: refreshRate)]
        if hiDPI {
            modes.insert(CGVirtualDisplayMode(width: UInt32(pixelWidth / 2), height: UInt32(pixelHeight / 2),
                                              refreshRate: refreshRate), at: 0)
        }
        settings.modes = modes
        guard display.apply(settings) else { return nil }

        self.display = display
        self.displayID = display.displayID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// The pixel size macOS is actually rendering this display at right now.
    var currentPixelSize: (width: Int, height: Int)? {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }
        return (mode.pixelWidth, mode.pixelHeight)
    }
}
#endif
