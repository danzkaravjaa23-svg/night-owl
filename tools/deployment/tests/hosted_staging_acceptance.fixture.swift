// Original synthetic fixture: one second of a solid color, no audio or assets.
// Uses the installed macOS AVFoundation encoder; no download or network access.
// swift -module-cache-path /private/tmp/nightowl-swift-cache this-file.swift NEW.mp4
import AVFoundation
import CoreVideo
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("One new output path required") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Output exists") }
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: 128, AVVideoHeightKey: 128,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12000,
                                    AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel]
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
    sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                 kCVPixelBufferWidthKey as String: 128,
                                 kCVPixelBufferHeightKey as String: 128])
writer.add(input)
guard writer.startWriting() else {
    let error = writer.error as NSError?
    let cause = error?.userInfo[NSUnderlyingErrorKey] as? NSError
    print("Encoder unavailable: \(error?.domain ?? "unknown") \(error?.code ?? 0); underlying \(cause?.domain ?? "none") \(cause?.code ?? 0)")
    exit(1)
}
writer.startSession(atSourceTime: .zero)
for frame in 0...1 {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess,
          let pixels = buffer else { fatalError("Pixel buffer failed") }
    CVPixelBufferLockBaseAddress(pixels, [])
    let stride = CVPixelBufferGetBytesPerRow(pixels)
    let bytes = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<128 { for x in 0..<128 {
        let offset = y * stride + x * 4
        bytes[offset] = 255; bytes[offset + 1] = 24; bytes[offset + 2] = 80; bytes[offset + 3] = 120
    }}
    CVPixelBufferUnlockBaseAddress(pixels, [])
    guard adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 2)) else {
        fatalError("Frame encode failed")
    }
}
writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError("Encoder finish failed") }
// Decode a frame with the native reader as a separate fixture validity check.
let asset = AVURLAsset(url: output)
let decoder = AVAssetImageGenerator(asset: asset)
let decoded = try decoder.copyCGImage(at: .zero, actualTime: nil)
guard decoded.width == 128 && decoded.height == 128 else { fatalError("Decode dimensions failed") }
print("PASS: original 128x128 H.264 MP4 encoded and native frame decoded")
