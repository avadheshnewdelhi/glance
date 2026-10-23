import AVFoundation
import GlanceCore
import Vision

/// Runs camera frames through Apple's on-device Vision face landmarks.
/// Frames are analysed in memory and dropped immediately; nothing is recorded, stored or sent anywhere.
final class GazeCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called on the main queue with a sample, or nil when no face is visible.
    var onSample: ((GazeSample?, TimeInterval) -> Void)?
    private(set) var isRunning = false
    /// Seconds between analysed frames; ~12 per second is plenty for gaze and keeps CPU use low.
    var frameInterval = 1.0 / 12 {
        didSet { queue.async { [self, frameInterval] in analysisInterval = frameInterval } }
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "Glance.camera")
    private let faces = VNDetectFaceRectanglesRequest()
    private let landmarks = VNDetectFaceLandmarksRequest()
    private var lastFrame: TimeInterval = 0
    private var analysisInterval = 1.0 / 12 // frameInterval, owned by `queue`

    override init() {
        faces.revision = VNDetectFaceRectanglesRequestRevision3
        landmarks.revision = VNDetectFaceLandmarksRequestRevision3
        super.init()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        queue.async { [self] in
            // Reconfigure every time: the available camera changes when the lid closes or a webcam is plugged in.
            if configure() { session.startRunning() }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        queue.async { [self] in session.stopRunning() }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)

        let builtIn = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices.first
        guard let device = builtIn ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time - lastFrame >= analysisInterval, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = time
        let sample = analyze(pixels)
        DispatchQueue.main.async { [weak self] in self?.onSample?(sample, time) }
    }

    private func analyze(_ pixels: CVPixelBuffer) -> GazeSample? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
        try? handler.perform([faces])
        guard let face = faces.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              let yaw = face.yaw?.doubleValue else { return nil }

        landmarks.inputFaceObservations = [face]
        try? handler.perform([landmarks])
        guard let marks = landmarks.results?.first?.landmarks else { return nil }
        let offsets = [(marks.leftEye, marks.leftPupil), (marks.rightEye, marks.rightPupil)].compactMap(Self.pupilOffset)
        guard !offsets.isEmpty else { return nil }
        return GazeSample(yaw: yaw, pupil: offsets.reduce(0, +) / Double(offsets.count))
    }

    /// Horizontal pupil position relative to the eye's centre, in eye widths.
    private static func pupilOffset(eye: VNFaceLandmarkRegion2D?, pupil: VNFaceLandmarkRegion2D?) -> Double? {
        guard let eye = eye?.normalizedPoints, let p = pupil?.normalizedPoints.first,
              let minX = eye.map(\.x).min(), let maxX = eye.map(\.x).max(), maxX > minX else { return nil }
        return (p.x - (minX + maxX) / 2) / (maxX - minX)
    }
}
