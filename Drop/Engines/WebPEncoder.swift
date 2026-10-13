import Accelerate
import CoreGraphics
import Foundation
import libwebp

/// ImageIO reads WebP but can't write it, so encoding goes through Google's libwebp.
nonisolated enum WebPEncoder {
    /// Encodes as lossy WebP (alpha preserved), or lossless when `quality` is 1.
    static func write(_ image: CGImage, to url: URL, quality: Double) throws {
        let width = image.width
        let height = image.height
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: stride,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

            // CoreGraphics draws premultiplied alpha; WebP expects straight alpha.
            if image.hasAlpha {
                var vImage = vImage_Buffer(data: buffer.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: stride)
                vImageUnpremultiplyData_RGBA8888(&vImage, &vImage, vImage_Flags(kvImageNoFlags))
            }
            return true
        }
        guard drawn else { throw DropError.failed("Couldn't prepare the image for WebP.") }

        var output: UnsafeMutablePointer<UInt8>?
        let size = pixels.withUnsafeBufferPointer { buffer -> Int in
            if quality >= 1 {
                return WebPEncodeLosslessRGBA(buffer.baseAddress, Int32(width), Int32(height), Int32(stride), &output)
            }
            return WebPEncodeRGBA(buffer.baseAddress, Int32(width), Int32(height), Int32(stride), Float(quality * 100), &output)
        }
        defer { WebPFree(output) }
        guard size > 0, let output else { throw DropError.failed("WebP encoding failed.") }
        try Data(bytes: output, count: size).write(to: url, options: .atomic)
    }
}
