import AppKit
import CoreImage
import ScreenCaptureKit

/// Exits with a concise failure so regression checks do not generate crash reports.
func require(_ condition: Bool, _ message: String) {
    guard condition else {
        print("FAIL: \(message)")
        exit(1)
    }
}

// Regression: stored positions must not depend on temporary collapsed divider widths.
let arrangement = BarArrangement(alwaysHidden: [], hidden: [], shown: [])
let collapsed = LayoutSorter.positionWrites(for: arrangement, fixedItems: [], ownWidths: OwnItemWidths(toggle: 22, hiddenDivider: 10_000, alwaysHiddenDivider: 10_000))
let expanded = LayoutSorter.positionWrites(for: arrangement, fixedItems: [], ownWidths: OwnItemWidths(toggle: 22, hiddenDivider: 1, alwaysHiddenDivider: 1))
require(collapsed.own.map(\.value) == expanded.own.map(\.value), "Collapsed widths leaked into saved positions")
require(collapsed.own.allSatisfy { $0.value < 100 }, "Saved divider position is off screen")
require(Set(collapsed.own.map(\.value)).count == 3, "Compact own items need distinct positions")
print("PASS: compact positions ignore collapsed widths and preserve distinct ordering")

// Regression: native status windows can extend above the display by 2.5 points.
let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
let paddedIcon = CGRect(x: 1061, y: -2.5, width: 50, height: 34)
require(MenuBarGeometry.visibleBounds(of: paddedIcon, on: [display]) == CGRect(x: 1061, y: 0, width: 50, height: 31.5), "Visible icon padding must not block native menus or screenshots")
require(MenuBarGeometry.visibleBounds(of: CGRect(x: -100, y: 0, width: 50, height: 34), on: [display]) == nil, "Hidden icons must not pass visibility checks")
require(MenuBarGeometry.visibleBounds(of: CGRect(x: 1700, y: 0, width: 50, height: 34), on: [display]) == nil, "Horizontally clipped icons must not pass visibility checks")
print("PASS: vertical window padding is accepted, off-screen icons rejected")

/// Creates deterministic status-window pixels without capturing the screen.
func iconFixture(background: CGColor, foreground: CGColor? = nil, foregroundRect: CGRect = CGRect(x: 24, y: 8, width: 16, height: 16)) -> CGImage {
    let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8,
                            bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(background)
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
    if let foreground {
        context.setFillColor(foreground)
        context.fill(foregroundRect)
    }
    return context.makeImage()!
}
let blackSnapshot = iconFixture(background: CGColor(gray: 0, alpha: 1))
let graySnapshot = iconFixture(background: CGColor(gray: 0.12, alpha: 1))
let emptySnapshot = iconFixture(background: CGColor(gray: 0, alpha: 0))
let whiteIcon = iconFixture(background: CGColor(gray: 0.1, alpha: 1), foreground: CGColor(gray: 1, alpha: 1))
let darkIcon = iconFixture(background: CGColor(gray: 0, alpha: 0), foreground: CGColor(gray: 0, alpha: 1))
require(!MenuBarImageValidation.isUsable(blackSnapshot), "Black status windows must not replace icons")
require(!MenuBarImageValidation.isUsable(graySnapshot), "Flat dark-gray snapshots must not become icons")
require(!MenuBarImageValidation.isUsable(emptySnapshot), "Transparent status windows must not replace icons")
require(MenuBarImageValidation.isUsable(whiteIcon), "White tray glyph must remain visible")
require(MenuBarImageValidation.isUsable(darkIcon), "Black glyph on transparency must remain usable")
print("PASS: blank snapshots rejected; light and dark glyphs accepted")

let paddedGlyph = NSImage(cgImage: whiteIcon, size: NSSize(width: 64, height: 32))
let normalizedGlyph = MenuBarIconPresentation.image(from: paddedGlyph)!
require(normalizedGlyph.size == NSSize(width: 16, height: 16), "Window padding must not shrink the glyph")
let transparentGlyph = MenuBarIconPresentation.image(from: NSImage(cgImage: darkIcon, size: NSSize(width: 64, height: 32)))!
require(transparentGlyph.size == normalizedGlyph.size, "Light and dark tray glyphs need the same visual height")
print("PASS: glyph sizes ignore captured window padding")

let temperature = NSImage(cgImage: iconFixture(background: CGColor(gray: 0.1, alpha: 1),
    foreground: CGColor(gray: 1, alpha: 1), foregroundRect: CGRect(x: 8, y: 8, width: 48, height: 16)),
    size: NSSize(width: 64, height: 32))
let temperatureIcon = MenuBarIconPresentation.image(from: temperature)!
require(temperatureIcon.size == NSSize(width: 48, height: 16), "Wide temperature text must retain the common glyph height")
require(MenuBarIconPresentation.buttonWidth(for: temperature) == 64, "Temperature text needs wider space instead of a smaller glyph")
let retinaGlyph = NSImage(cgImage: whiteIcon, size: NSSize(width: 32, height: 16))
require(MenuBarIconPresentation.image(from: retinaGlyph)!.size == normalizedGlyph.size, "Backing scale must not change visual glyph size")
print("PASS: temperature text keeps its aspect ratio and matches other glyph heights")

/// Reads RGBA from a normalized glyph in a known pixel format.
func rgba(at point: CGPoint, in image: NSImage) -> [UInt8] {
    let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let context = CGContext(data: nil, width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                            bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
    let offset = (Int(point.y) * bitmap.width + Int(point.x)) * 4
    let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
    return Array(UnsafeBufferPointer(start: pixels.advanced(by: offset), count: 4))
}

// Regression: removing a window matte must also clear the holes inside glyphs.
let ringFixture = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                            bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ringFixture.setFillColor(CGColor(gray: 0, alpha: 1))
ringFixture.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
ringFixture.setFillColor(CGColor(red: 0.45, green: 0.3, blue: 1, alpha: 1))
ringFixture.fillEllipse(in: CGRect(x: 8, y: 8, width: 16, height: 16))
ringFixture.setFillColor(CGColor(gray: 0, alpha: 1))
ringFixture.fillEllipse(in: CGRect(x: 13, y: 13, width: 6, height: 6))
let ring = MenuBarIconPresentation.image(from: NSImage(cgImage: ringFixture.makeImage()!,
    size: NSSize(width: 32, height: 32)))!
require(rgba(at: CGPoint(x: 0, y: 0), in: ring)[3] == 0, "Opaque black corners must become transparent")
require(rgba(at: CGPoint(x: 8, y: 8), in: ring)[3] == 0, "Black inside a glyph must become transparent")
let stroke = rgba(at: CGPoint(x: 8, y: 3), in: ring)
require(stroke[3] == 255 && stroke[2] > stroke[0] && stroke[0] > stroke[1],
    "Colored glyphs must retain their color and opacity")
require(rgba(at: CGPoint(x: 8, y: 8), in: transparentGlyph) == [0, 0, 0, 255],
    "Black foreground on a transparent capture must stay opaque")
print("PASS: captured black mattes become transparent while glyph color and alpha are preserved")

// Regression: a cached temperature picture must still participate in live refresh.
let cachedTemperature = MenuBarItem(id: "fan#0", bundleIdentifier: "fan", processIdentifier: getpid(),
    displayName: "Fan", indexInApp: 0, frame: .zero, element: AXUIElementCreateApplication(getpid()),
    windowID: nil, image: temperature, isMovable: true)
require(MenuBarScanner.captureCandidates(from: [cachedTemperature], refreshExisting: false, itemIDs: nil).isEmpty,
    "Initial capture must keep valid cached pictures")
require(MenuBarScanner.captureCandidates(from: [cachedTemperature], refreshExisting: true, itemIDs: ["fan#0"]).count == 1,
    "Live refresh must recapture cached temperature pictures")
require(MenuBarScanner.captureCandidates(from: [cachedTemperature], refreshExisting: true, itemIDs: ["other#0"]).isEmpty,
    "Live refresh must respect the displayed section")
print("PASS: cached dynamic icons participate in live refresh")

/// Creates complete stream frames from synthetic glyphs without accessing any screen.
func streamFixture(_ image: CGImage, status: SCFrameStatus = .complete) -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    require(CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height,
        kCVPixelFormatType_32BGRA, nil,
        &pixelBuffer) == kCVReturnSuccess, "Cannot create frame fixture")
    let buffer = pixelBuffer!
    CIContext(options: [.useSoftwareRenderer: true]).render(CIImage(cgImage: image), to: buffer)
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
        imageBuffer: buffer, formatDescriptionOut: &format)
    var timing = CMSampleTimingInfo(duration: CMTime(seconds: 1, preferredTimescale: 600),
        presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
        formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
    let attachments = CMSampleBufferGetSampleAttachmentsArray(sample!, createIfNecessary: true) as! [NSMutableDictionary]
    attachments[0][SCStreamFrameInfo.status.rawValue] = status.rawValue
    return sample!
}
let firstFrame = MenuBarLiveFrame.image(from: streamFixture(whiteIcon))!
let changedFixture = iconFixture(background: CGColor(gray: 0.1, alpha: 1),
    foreground: CGColor(gray: 1, alpha: 1), foregroundRect: CGRect(x: 16, y: 8, width: 32, height: 16))
let secondFrame = MenuBarLiveFrame.image(from: streamFixture(changedFixture))!
require((firstFrame.dataProvider!.data! as Data) != (secondFrame.dataProvider!.data! as Data),
    "New stream content must replace the previous image")
require(MenuBarLiveFrame.image(from: streamFixture(whiteIcon, status: .idle)) == nil,
    "Idle frames must not replace the latest complete frame")
print("PASS: successive stream frames change the icon; idle frames are ignored")

/// Builds an icon whose process and screen position can change between launches.
func layoutIcon(_ name: String, index: Int, pid: pid_t, x: CGFloat = 10) -> MenuBarItem {
    MenuBarItem(id: "test.app#\(index)", bundleIdentifier: "test.app", processIdentifier: pid,
                displayName: name, indexInApp: index, frame: CGRect(x: x, y: 0, width: 24, height: 25),
                element: AXUIElementCreateApplication(pid), windowID: nil, image: nil,
                isMovable: true, autosaveName: name)
}

let firstIcon = layoutIcon("First", index: 0, pid: 100)
let lateIcon = layoutIcon("Late", index: 1, pid: 100)
let lastIcon = layoutIcon("Last", index: 2, pid: 100)
let layoutSuite = "com.local.hider.tests.\(UUID().uuidString)"
let layoutDefaults = UserDefaults(suiteName: layoutSuite)!
let initialLayout = SavedBarLayout(sections: [.hidden: [firstIcon, lateIcon, lastIcon]])
SavedBarLayout(sections: [.hidden: [firstIcon, lastIcon]], previous: initialLayout).save(to: layoutDefaults)
let reloadedLayout = SavedBarLayout.load(from: UserDefaults(suiteName: layoutSuite)!)!
let restoredFirst = layoutIcon("First", index: 2, pid: 200)
let restoredLate = layoutIcon("Late", index: 0, pid: 200)
let restoredLast = layoutIcon("Last", index: 1, pid: 200)
let newIcon = layoutIcon("New", index: 3, pid: 200)
let scannedLayout: [BarSection: [MenuBarItem]] = [.shown: [restoredLate, newIcon, restoredFirst], .alwaysHidden: [restoredLast]]
let restoredLayout = reloadedLayout.restoredSections(from: scannedLayout)
require(restoredLayout[.hidden]?.map(\.displayName) == ["First", "Late", "Last"],
    "A new process and new indices must not change the saved order or section")
require(restoredLayout[.shown]?.map(\.displayName) == ["New"] && restoredLayout[.alwaysHidden]?.isEmpty == true,
    "Restoration must preserve the current section of an unknown icon")
require(reloadedLayout.presentProcesses(in: scannedLayout)[restoredLate.layoutID] == 200,
    "Restoration must recognize saved icons in a new process")

let dividerKey = "NSStatusItem Preferred Position HiderHiddenDivider"
SavedBarLayout.saveCompactPositions([dividerKey: 45], to: layoutDefaults)
layoutDefaults.set(10_045, forKey: dividerKey)
SavedBarLayout.restoreCompactPositions(in: UserDefaults(suiteName: layoutSuite)!)
require(layoutDefaults.double(forKey: dividerKey) == 45, "AppKit writes must not overwrite the remembered compact position")
layoutDefaults.removePersistentDomain(forName: layoutSuite)
let offscreenFixed = layoutIcon("Offscreen Fixed", index: 4, pid: 200, x: -10_000)
let compactWithoutOffscreenIcons = LayoutSorter.positionWrites(for: arrangement, fixedItems: [offscreenFixed],
    ownWidths: OwnItemWidths(toggle: 22, hiddenDivider: 10_000, alwaysHiddenDivider: 10_000), screenWidth: 1500)
require(compactWithoutOffscreenIcons.own.allSatisfy { $0.value < 100 },
    "Off-screen system icons must not move Tuck's preferred positions off-screen")
print("PASS: layouts and compact divider positions survive reload; missing icons keep their saved slots")
