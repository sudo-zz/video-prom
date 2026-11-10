import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// Usage: qa_video <video.mp4> <output-prefix>
// Reads the video and exports four PNGs without changing the input.
func inspect() throws {
    guard CommandLine.arguments.count == 3 else {
        throw NSError(domain: "qa_video", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Usage: qa_video <video.mp4> <output-prefix>"])
    }
    let input = URL(fileURLWithPath: CommandLine.arguments[1])
    let prefix = CommandLine.arguments[2]
    let asset = AVURLAsset(url: input)
    let tracks = asset.tracks(withMediaType: .video)
    print("duration_seconds=\(CMTimeGetSeconds(asset.duration))")
    print("video_tracks=\(tracks.count)")
    print("audio_tracks=\(asset.tracks(withMediaType: .audio).count)")
    for track in tracks {
        print("dimensions=\(Int(track.naturalSize.width))x\(Int(track.naturalSize.height))")
        print("fps=\(track.nominalFrameRate)")
        print("transform=\(track.preferredTransform)")
        for description in track.formatDescriptions {
            let format = description as! CMFormatDescription
            let code = CMFormatDescriptionGetMediaSubType(format)
            let bytes: [UInt8] = [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255), UInt8((code >> 8) & 255), UInt8(code & 255)]
            print("codec=\(String(bytes: bytes, encoding: .ascii) ?? String(code))")
        }
    }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    for (index, seconds) in [0.0, 9.5, 20.7, 26.0].enumerated() {
        let output = URL(fileURLWithPath: "\(prefix)-\(String(format: "%03d", index)).png")
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw NSError(domain: "qa_video", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Output exists: \(output.path)"])
        }
        let image = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "qa_video", code: 3)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "qa_video", code: 4)
        }
        print("frame_\(seconds)=\(output.path)")
    }
}

do { try inspect() } catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
