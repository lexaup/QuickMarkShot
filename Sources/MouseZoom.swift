import AppKit
import AVFoundation
import CoreGraphics

struct CursorSample {
    let time: TimeInterval
    let point: CGPoint
}

final class CursorTracker {
    private var timer: Timer?
    private var startDate = Date()
    private var bounds: CGRect = .zero
    private(set) var samples: [CursorSample] = []

    func start(in bounds: CGRect) {
        self.bounds = bounds
        startDate = Date()
        samples.removeAll(keepingCapacity: true)
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func stop() -> [CursorSample] {
        sample()
        timer?.invalidate()
        timer = nil
        return samples
    }

    private func sample() {
        guard bounds.width > 1, bounds.height > 1,
              let location = CGEvent(source: nil)?.location else { return }
        let normalized = CGPoint(x: min(1, max(0, (location.x - bounds.minX) / bounds.width)),
                                 y: min(1, max(0, (location.y - bounds.minY) / bounds.height)))
        samples.append(CursorSample(time: Date().timeIntervalSince(startDate), point: normalized))
    }
}

enum MouseZoomError: LocalizedError {
    case missingVideo
    case cannotCreateExporter
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingVideo: return "录制文件中没有可处理的视频轨道。"
        case .cannotCreateExporter: return "无法创建鼠标跟随放大视频。"
        case .exportFailed(let detail): return "鼠标跟随放大处理失败：\(detail)"
        }
    }
}

enum MouseZoomProcessor {
    static func process(inputURL: URL,
                        outputURL: URL,
                        samples: [CursorSample],
                        zoomAmount: CGFloat,
                        completion: @escaping (Result<Void, Error>) -> Void) {
        let asset = AVURLAsset(url: inputURL)
        guard let track = asset.tracks(withMediaType: .video).first else {
            completion(.failure(MouseZoomError.missingVideo))
            return
        }

        let size = track.naturalSize
        let duration = asset.duration
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = makeInstructions(track: track,
                                                         size: size,
                                                         duration: duration,
                                                         samples: samples,
                                                         zoomAmount: zoomAmount)

        try? FileManager.default.removeItem(at: outputURL)
        guard let exporter = AVAssetExportSession(asset: asset,
                                                  presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(MouseZoomError.cannotCreateExporter))
            return
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        exporter.exportAsynchronously {
            switch exporter.status {
            case .completed:
                completion(.success(()))
            case .failed, .cancelled:
                completion(.failure(MouseZoomError.exportFailed(exporter.error?.localizedDescription ?? "未知错误")))
            default:
                completion(.failure(MouseZoomError.exportFailed("导出未完成")))
            }
        }
    }

    private static func makeInstructions(track: AVAssetTrack,
                                         size: CGSize,
                                         duration: CMTime,
                                         samples: [CursorSample],
                                         zoomAmount: CGFloat) -> [AVVideoCompositionInstructionProtocol] {
        let frameStep = 1.0 / 30.0
        let totalSeconds = max(frameStep, duration.seconds.isFinite ? duration.seconds : frameStep)
        var timedPoints = samples
        if timedPoints.isEmpty {
            timedPoints = [CursorSample(time: 0, point: CGPoint(x: 0.5, y: 0.5))]
        }

        var center = CGPoint(x: 0.5, y: 0.5)
        var velocity = CGVector.zero
        var target = center
        var instructions: [AVVideoCompositionInstructionProtocol] = []
        var index = 0
        var time = 0.0
        var previousTransform = transform(center: center, size: size, zoom: zoomAmount)

        while time < totalSeconds {
            while index + 1 < timedPoints.count && timedPoints[index + 1].time <= time {
                index += 1
            }
            let cursor = timedPoints[index].point

            // A generous dead zone prevents nervous micro-movement; the spring then
            // carries velocity across retargets for a natural camera-follow feel.
            let halfDeadX = 0.25 / zoomAmount
            let halfDeadY = 0.35 / zoomAmount
            if abs(cursor.x - target.x) > halfDeadX || abs(cursor.y - target.y) > halfDeadY {
                target = snappedTarget(cursor, zoom: zoomAmount)
            }

            let stiffness: CGFloat = 180
            let damping: CGFloat = 36
            let mass: CGFloat = 2
            let dt = CGFloat(frameStep)
            let accelerationX = (stiffness * (target.x - center.x) - damping * velocity.dx) / mass
            let accelerationY = (stiffness * (target.y - center.y) - damping * velocity.dy) / mass
            velocity.dx += accelerationX * dt
            velocity.dy += accelerationY * dt
            center.x += velocity.dx * dt
            center.y += velocity.dy * dt

            let nextTime = min(totalSeconds, time + frameStep)
            let nextTransform = transform(center: center, size: size, zoom: zoomAmount)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            let range = CMTimeRange(start: CMTime(seconds: time, preferredTimescale: 600),
                                    end: CMTime(seconds: nextTime, preferredTimescale: 600))
            layer.setTransformRamp(fromStart: previousTransform,
                                   toEnd: nextTransform,
                                   timeRange: range)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = range
            instruction.layerInstructions = [layer]
            instructions.append(instruction)
            previousTransform = nextTransform
            time = nextTime
        }
        return instructions
    }

    private static func snappedTarget(_ point: CGPoint, zoom: CGFloat) -> CGPoint {
        let halfX = 0.5 / zoom
        let halfY = 0.5 / zoom
        let snap: CGFloat = 0.20
        var x = min(1 - halfX, max(halfX, point.x))
        var y = min(1 - halfY, max(halfY, point.y))
        if point.x < snap { x = halfX }
        if point.x > 1 - snap { x = 1 - halfX }
        if point.y < snap { y = halfY }
        if point.y > 1 - snap { y = 1 - halfY }
        return CGPoint(x: x, y: y)
    }

    private static func transform(center: CGPoint, size: CGSize, zoom: CGFloat) -> CGAffineTransform {
        let halfX = 0.5 / zoom
        let halfY = 0.5 / zoom
        let x = min(1 - halfX, max(halfX, center.x)) * size.width
        let y = min(1 - halfY, max(halfY, center.y)) * size.height
        return CGAffineTransform(a: zoom,
                                 b: 0,
                                 c: 0,
                                 d: zoom,
                                 tx: size.width / 2 - x * zoom,
                                 ty: size.height / 2 - y * zoom)
    }
}
