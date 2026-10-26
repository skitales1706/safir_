import AVKit
import SwiftUI
import WebRTC

/// Picture in Picture for video calls (Android CallActivity.enterPictureInPictureMode): when the
/// app goes to the background during a video call, the other side keeps playing in a floating
/// window. WebRTC frames go into an AVSampleBufferDisplayLayer inside Apple's video-call PiP
/// controller (iOS 15+); the source view is an invisible anchor behind the call's video.
@MainActor
final class CallPiP: NSObject {
    static let shared = CallPiP()

    private var controller: AVPictureInPictureController?
    private let renderer = PiPFrameRenderer()
    private weak var track: RTCVideoTrack?

    var supported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// Called by the anchor once it is in the window.
    func attach(source: UIView) {
        guard supported, controller == nil else { return }
        let callVC = AVPictureInPictureVideoCallViewController()
        callVC.preferredContentSize = CGSize(width: 9, height: 16)
        renderer.view.frame = callVC.view.bounds
        renderer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        callVC.view.addSubview(renderer.view)
        let content = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: source,
                                                                  contentViewController: callVC)
        let pip = AVPictureInPictureController(contentSource: content)
        pip.canStartPictureInPictureAutomaticallyFromInline = track != nil
        pip.delegate = self
        controller = pip
    }

    /// The remote track to show (nil = audio only: PiP stays off).
    func show(_ newTrack: RTCVideoTrack?) {
        guard newTrack !== track else { return }
        track?.remove(renderer)
        track = newTrack
        newTrack?.add(renderer)
        controller?.canStartPictureInPictureAutomaticallyFromInline = newTrack != nil
    }

    func detach() {
        show(nil)
        controller?.stopPictureInPicture()
        controller = nil
    }
}

extension CallPiP: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
                                                completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            CallService.shared.showUI = true
            completionHandler(true)
        }
    }
}

/// RTCVideoRenderer that turns WebRTC frames into sample buffers for the display layer.
final class PiPFrameRenderer: NSObject, RTCVideoRenderer {
    let view = SampleBufferView()

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, let pixelBuffer = Self.pixelBuffer(frame.buffer),
              let sample = Self.sampleBuffer(pixelBuffer) else { return }
        let layer = view.displayLayer
        DispatchQueue.main.async {
            if layer.status == .failed { layer.flush() }
            layer.enqueue(sample)
        }
    }

    /// Hardware-decoded frames already are CVPixelBuffers; I420 (VP8 / software) is copied into NV12.
    private static func pixelBuffer(_ buffer: RTCVideoFrameBuffer) -> CVPixelBuffer? {
        if let cv = buffer as? RTCCVPixelBuffer { return cv.pixelBuffer }
        let i420 = buffer.toI420()
        let width = Int(i420.width), height = Int(i420.height)
        var out: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attrs, &out) == kCVReturnSuccess,
              let pb = out else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let yDst = CVPixelBufferGetBaseAddressOfPlane(pb, 0)?.assumingMemoryBound(to: UInt8.self),
              let uvDst = CVPixelBufferGetBaseAddressOfPlane(pb, 1)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        for row in 0..<height {
            memcpy(yDst + row * yStride, i420.dataY + row * Int(i420.strideY), width)
        }
        let chromaW = (width + 1) / 2, chromaH = (height + 1) / 2
        for row in 0..<chromaH {
            let u = i420.dataU + row * Int(i420.strideU)
            let v = i420.dataV + row * Int(i420.strideV)
            let dst = uvDst + row * uvStride
            for col in 0..<chromaW {
                dst[col * 2] = u[col]
                dst[col * 2 + 1] = v[col]
            }
        }
        return pb
    }

    private static func sampleBuffer(_ pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer,
                                                           formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: format,
                                                       sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

/// UIView backed by an AVSampleBufferDisplayLayer.
final class SampleBufferView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        // swiftlint:disable:next force_cast
        let layer = layer as! AVSampleBufferDisplayLayer
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}

/// Invisible view behind the call's video that PiP animates from and back to.
struct CallPiPAnchor: UIViewRepresentable {
    let track: RTCVideoTrack?

    func makeUIView(context: Context) -> UIView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        CallPiP.shared.show(track)
    }

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        CallPiP.shared.detach()
    }

    private final class AnchorView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { CallPiP.shared.attach(source: self) }
        }
    }
}
