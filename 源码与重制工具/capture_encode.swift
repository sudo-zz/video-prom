import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import CoreVideo
import VideoToolbox

// Usage: capture_encode <frame-directory> <fps> <output.mp4> [bitrate]
enum EncodeError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let value): return value }
    }
}

func fail(_ message: String) -> EncodeError { .message(message) }

func imageAt(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw fail("Cannot read image: \(url.path)")
    }
    return image
}

func encode() throws {
    let args = CommandLine.arguments
    guard (args.count == 4 || args.count == 5), let fps = Int32(args[2]), fps > 0 else {
        throw fail("Usage: capture_encode <frame-directory> <fps> <output.mp4> [bitrate]")
    }
    let directory = URL(fileURLWithPath: args[1], isDirectory: true)
    let output = URL(fileURLWithPath: args[3])
    guard !FileManager.default.fileExists(atPath: output.path) else {
        throw fail("Output already exists: \(output.path)")
    }
    let frames = try FileManager.default.contentsOfDirectory(at: directory,
        includingPropertiesForKeys: nil).filter {
            ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard let firstURL = frames.first else { throw fail("No JPEG or PNG frames") }
    let first = try imageAt(firstURL)
    let width = first.width, height = first.height
    guard width % 2 == 0, height % 2 == 0 else {
        throw fail("H.264 dimensions must be even: \(width)x\(height)")
    }
    let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    let customBitrate = args.count == 5 ? Int(args[4]) : nil
    let bitrate = customBitrate ?? max(8_500_000, width * height * 5)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoMaxKeyFrameIntervalKey: fps * 10,
            AVVideoMaxKeyFrameIntervalDurationKey: 10.0,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
        ]
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
    guard writer.canAdd(input) else { throw fail("Cannot add H.264 writer input") }
    writer.add(input)
    writer.shouldOptimizeForNetworkUse = true
    guard writer.startWriting() else {
        throw fail("Cannot start writer: \(String(describing: writer.error))")
    }
    writer.startSession(atSourceTime: .zero)
    guard let pool = adaptor.pixelBufferPool else { throw fail("No pixel buffer pool") }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    for (index, frameURL) in frames.enumerated() {
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed {
                throw fail("Writer failed: \(String(describing: writer.error))")
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
        try autoreleasepool {
            let image = try imageAt(frameURL)
            guard image.width == width && image.height == height else {
                throw fail("Frame size differs: \(frameURL.lastPathComponent)")
            }
            var optionalBuffer: CVPixelBuffer?
            let result = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
            guard result == kCVReturnSuccess, let buffer = optionalBuffer else {
                throw fail("Cannot create pixel buffer: \(result)")
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
                throw fail("Cannot create bitmap context")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let time = CMTime(value: Int64(index), timescale: fps)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw fail("Cannot append frame \(index): \(String(describing: writer.error))")
            }
        }
        if index % Int(fps * 5) == 0 {
            print("Encoded \(index + 1)/\(frames.count) frames")
        }
    }
    writer.endSession(atSourceTime: CMTime(value: Int64(frames.count), timescale: fps))
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else {
        throw fail("Encoding did not complete: \(String(describing: writer.error))")
    }
    print("Saved \(output.path) — \(width)x\(height), \(fps)fps, \(frames.count) frames")
}

do {
    try encode()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
