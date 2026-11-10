import Foundation
import CoreGraphics
import ImageIO
import AVFoundation

let filmDir = "/Users/hs/Documents/work/token-hub/work/1af17eeb-d56d-431e-829c-09cedadbd73b/film"
let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "frames"

func loadImg(_ path: String) -> ([UInt8], Int, Int) {
    let url = URL(fileURLWithPath: path)
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (buf, w, h)
}

func diffBox(_ a: [UInt8], _ b: [UInt8], w: Int, x0: Int, y0: Int, x1: Int, y1: Int, thresh: Int = 2) -> (Int, Int) {
    var cnt = 0
    var maxD = 0
    for y in y0..<y1 {
        let row = y * w * 4
        for x in x0..<x1 {
            let i = row + x * 4
            let d = max(abs(Int(a[i]) - Int(b[i])), max(abs(Int(a[i+1]) - Int(b[i+1])), abs(Int(a[i+2]) - Int(b[i+2]))))
            if d > thresh {
                cnt += 1
                if d > maxD { maxD = d }
            }
        }
    }
    return (cnt, maxD)
}

if mode == "frames" {
    let framesDir = "\(filmDir)/frames_16x9"
    print("=== AUDITING 2,340 RENDERED 16:9 FRAMES (thresh > 2 for JPEG q=95) ===")

    // 1. All 10 Headline stationary windows (y=82..128, x=400..1520 — strictly the centered headline text)
    let headlines: [(Double, Double, String)] = [
        (0.50, 2.70, "H0 00:01"),
        (3.40, 6.15, "H1 00:05"),
        (6.85, 10.95, "H2 00:08"),
        (11.65, 13.25, "H3 00:12"),
        (13.95, 17.32, "H4 00:16"),
        (18.02, 21.32, "H5 00:20"),
        (22.05, 26.12, "H6 00:24"),
        (26.82, 29.28, "H7 00:28"),
        (29.98, 31.88, "H8 00:31"),
        (32.58, 35.92, "H9 00:34")
    ]

    var anyFail = false
    for (t0, t1, name) in headlines {
        let f0 = Int(ceil(t0 * 60.0))
        let f1 = Int(floor(t1 * 60.0))
        var prev = loadImg(String(format: "%@/frame_%05d.jpg", framesDir, f0)).0
        var sumCnt = 0
        var worstD = 0
        for f in (f0+1)...f1 {
            let cur = loadImg(String(format: "%@/frame_%05d.jpg", framesDir, f)).0
            let yBottom = (name.hasPrefix("H6") || name.hasPrefix("H7")) ? 116 : 128
            let (c, m) = diffBox(prev, cur, w: 1920, x0: 400, y0: 82, x1: 1520, y1: yBottom, thresh: 2)
            sumCnt += c
            if m > worstD { worstD = m }
            prev = cur
        }
        print("  [Headline \(name)] frames \(f0)..\(f1): diffPx=\(sumCnt), maxDelta=\(worstD)")
        if sumCnt > 0 { anyFail = true }
    }

    // 2. Stationary Scene / Subregion Windows across the entire 39s film (y <= 1070 excludes bottom 8px JPEG block of 3px progress bar)
    let windows: [(Double, Double, String, Int, Int, Int, Int)] = [
        (0.50, 1.70, "00:01 Card Shell Top (above typing)", 0, 140, 1920, 520),
        (3.80, 4.50, "00:04 Full Stage Settled", 0, 82, 1920, 1070),
        (4.75, 6.25, "00:05 Card TopBar + Prose (during arrow extract)", 380, 150, 1540, 232),
        (7.86, 8.00, "00:07.9 Post-Mint Settled", 0, 82, 1920, 1070),
        (10.18, 10.94, "00:10.6 Post-Backfill Settled", 0, 82, 1920, 1070),
        (12.02, 13.20, "00:12.7 Cloud Outbound: CloudCard", 895, 250, 1850, 620),
        (16.08, 17.34, "00:16.5 ENTIRE 1920x1070 SCREEN", 0, 0, 1920, 1070),
        (18.18, 21.10, "00:20.5 Tool Use Return: Header + MiniVault", 0, 0, 580, 340),
        (18.18, 21.10, "00:20.5 Tool Use Return: CloudCard", 895, 250, 1850, 860),
        (25.92, 26.08, "00:26.0 Post-Decrypt Settled", 0, 82, 1920, 1070),
        (28.80, 29.22, "00:29.0 Post-Shatter Cleared Vault", 0, 0, 1920, 1070),
        (30.00, 31.86, "00:31.0 ENTIRE 1920x1070 SCREEN (Client Restored)", 0, 0, 1920, 1070),
        (33.20, 35.90, "00:34.5 ENTIRE 1920x1070 SCREEN (16.8ms Card)", 0, 0, 1920, 1070),
        (37.15, 38.95, "00:38.0 ENTIRE 1920x1070 SCREEN (Finale Lockup)", 0, 0, 1920, 1070)
    ]

    for (t0, t1, name, x0, y0, x1, y1) in windows {
        let f0 = Int(ceil(t0 * 60.0))
        let f1 = Int(floor(t1 * 60.0))
        var prev = loadImg(String(format: "%@/frame_%05d.jpg", framesDir, f0)).0
        var sumCnt = 0
        var worstD = 0
        for f in (f0+1)...f1 {
            let cur = loadImg(String(format: "%@/frame_%05d.jpg", framesDir, f)).0
            let (c, m) = diffBox(prev, cur, w: 1920, x0: x0, y0: y0, x1: x1, y1: y1, thresh: 2)
            sumCnt += c
            if m > worstD { worstD = m }
            prev = cur
        }
        print("  [Window \(name)] frames \(f0)..\(f1): diffPx=\(sumCnt), maxDelta=\(worstD)")
        if sumCnt > 0 { anyFail = true }
    }

    // 3. Also audit 9:16 key stationary windows!
    let frames916 = "\(filmDir)/frames_9x16"
    let win916: [(Double, Double, String, Int, Int, Int, Int)] = [
        (0.50, 2.70, "9x16 H0 Headline", 80, 112, 1000, 165),
        (3.40, 6.15, "9x16 H1 Headline", 80, 112, 1000, 165),
        (16.08, 17.34, "9x16 00:16.5 ENTIRE 1080x1910 SCREEN", 0, 0, 1080, 1910),
        (18.18, 21.10, "9x16 00:20.5 CloudCard", 60, 672, 1020, 1480),
        (30.00, 31.86, "9x16 00:31.0 ENTIRE 1080x1910 SCREEN", 0, 0, 1080, 1910),
        (33.20, 35.90, "9x16 00:34.5 ENTIRE 1080x1910 SCREEN", 0, 0, 1080, 1910),
        (37.15, 38.95, "9x16 00:38.0 ENTIRE 1080x1910 SCREEN", 0, 0, 1080, 1910)
    ]
    print("\n=== AUDITING 9:16 RENDERED FRAMES ===")
    for (t0, t1, name, x0, y0, x1, y1) in win916 {
        let f0 = Int(ceil(t0 * 60.0))
        let f1 = Int(floor(t1 * 60.0))
        var prev = loadImg(String(format: "%@/frame_%05d.jpg", frames916, f0)).0
        var sumCnt = 0
        var worstD = 0
        for f in (f0+1)...f1 {
            let cur = loadImg(String(format: "%@/frame_%05d.jpg", frames916, f)).0
            let (c, m) = diffBox(prev, cur, w: 1080, x0: x0, y0: y0, x1: x1, y1: y1, thresh: 2)
            sumCnt += c
            if m > worstD { worstD = m }
            prev = cur
        }
        print("  [\(name)] frames \(f0)..\(f1): diffPx=\(sumCnt), maxDelta=\(worstD)")
        if sumCnt > 0 { anyFail = true }
    }

    if anyFail {
        print("FAIL: non-zero jitter detected!")
        exit(1)
    } else {
        print("\nPASS: 0 JITTER PIXELS ACROSS ALL 16:9 AND 9:16 WINDOWS!")
    }
} else if mode == "mp4" {
    let mp4Path = CommandLine.arguments[2]
    let url = URL(fileURLWithPath: mp4Path)
    let asset = AVURLAsset(url: url)
    let track = asset.tracks(withMediaType: .video).first!
    let reader = try! AVAssetReader(asset: asset)
    let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    reader.add(out)
    reader.startReading()

    // Check high-frequency oscillation across decoded H.264 frames in stationary windows
    // Windows: [965..1040] (16.1..17.3s), [1805..1915] (30.1..31.9s), [2000..2150] (33.3..35.8s), [2235..2330] (37.25..38.8s)
    var fIdx = 0
    var prevBuf: [UInt8]? = nil
    var w = 0, h = 0
    var maxMp4Delta = 0
    var jitterFrames = 0
    while let sample = out.copyNextSampleBuffer() {
        let pb = CMSampleBufferGetImageBuffer(sample)!
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        w = CVPixelBufferGetWidth(pb)
        h = CVPixelBufferGetHeight(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        var cur = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            memcpy(&cur[y * w * 4], base.advanced(by: y * bpr), w * 4)
        }
        CVPixelBufferUnlockBaseAddress(pb, .readOnly)

        let inFrozen = (fIdx >= 966 && fIdx <= 1038) || (fIdx >= 1805 && fIdx <= 1910) || (fIdx >= 2000 && fIdx <= 2150) || (fIdx >= 2235 && fIdx <= 2330)
        if inFrozen, let p = prevBuf {
            let (cnt, m) = diffBox(p, cur, w: w, x0: 0, y0: 0, x1: w, y1: h - 16, thresh: 6)
            if cnt > 0 { jitterFrames += 1 }
            if m > maxMp4Delta { maxMp4Delta = m }
        }
        prevBuf = cur
        fIdx += 1
    }
    print("[MP4 \(URL(fileURLWithPath: mp4Path).lastPathComponent)] decoded \(fIdx) frames (\(w)x\(h)): frozenJitterFrames(d>6)=\(jitterFrames), maxFrozenDelta=\(maxMp4Delta)")
}
