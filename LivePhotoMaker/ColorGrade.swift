// ColorGrade.swift — Per-parameter color grading for LivePhotoMaker
// Applied to both the cover frame HEIC and the exported MOV via AVVideoComposition.
import CoreImage
import CoreGraphics

/// Holds adjustable color-grading parameters. All defaults = identity (no change).
struct ColorGrade: Equatable {
    var exposure:   Double = 0.0  // CIExposureAdjust inputEV: -3…+3  (0 = neutral)
    var contrast:   Double = 1.0  // CIColorControls inputContrast: 0.5…1.5 (1 = neutral)
    var brightness: Double = 0.0  // CIColorControls inputBrightness: -0.5…+0.5 (0 = neutral)
    var saturation: Double = 1.0  // CIColorControls inputSaturation: 0…2 (1 = neutral)
    var highlights: Double = 1.0  // CIHighlightShadowAdjust inputHighlightAmount: 0…1 (1 = no change)
    var shadows:    Double = 0.0  // CIHighlightShadowAdjust inputShadowAmount: 0…1 (0 = no lift)
    var vibrance:   Double = 0.0  // CIVibrance inputAmount: -1…1 (0 = neutral)
    var sharpness:  Double = 0.0  // CISharpenLuminance inputSharpness: 0…2 (0 = neutral)
    var warmth:     Double = 0.0  // CITemperatureAndTint offset: -100…+100 (0 = neutral ≈ 6500K)
    var tint:       Double = 0.0  // CITemperatureAndTint tint: -100…+100 (0 = neutral)

    static let identity = ColorGrade()
    var isIdentity: Bool { self == .identity }

    // ── Apply to CIImage ─────────────────────────────────────────────────────
    /// Apply this grade to a CIImage. Optionally prepend pre-computed auto-enhance filters.
    /// `autoParams` is a thread-safe serialized representation of CIAutoAdjustmentFilters.
    func apply(to image: CIImage,
               autoParams: [(name: String, params: [String: Any])] = []) -> CIImage {
        var img = image

        // 1. Auto-enhance pass (recreate CIFilter instances per call for thread safety)
        for fp in autoParams {
            guard let f = CIFilter(name: fp.name) else { continue }
            f.setValue(img.clampedToExtent(), forKey: kCIInputImageKey)
            for (k, v) in fp.params { f.setValue(v, forKey: k) }
            if let out = f.outputImage { img = out.cropped(to: image.extent) }
        }

        // 2. Exposure
        if exposure != 0 {
            if let f = CIFilter(name: "CIExposureAdjust") {
                f.setValue(img, forKey: kCIInputImageKey)
                f.setValue(exposure, forKey: "inputEV")
                if let o = f.outputImage { img = o }
            }
        }

        // 3. Brightness / Contrast / Saturation
        if brightness != 0 || contrast != 1 || saturation != 1 {
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(img, forKey: kCIInputImageKey)
                f.setValue(brightness, forKey: "inputBrightness")
                f.setValue(contrast,   forKey: "inputContrast")
                f.setValue(saturation, forKey: "inputSaturation")
                if let o = f.outputImage { img = o }
            }
        }

        // 4. Highlights / Shadows
        if highlights != 1 || shadows != 0 {
            if let f = CIFilter(name: "CIHighlightShadowAdjust") {
                f.setValue(img, forKey: kCIInputImageKey)
                f.setValue(highlights, forKey: "inputHighlightAmount")
                f.setValue(shadows,    forKey: "inputShadowAmount")
                if let o = f.outputImage { img = o }
            }
        }

        // 5. Vibrance
        if vibrance != 0 {
            if let f = CIFilter(name: "CIVibrance") {
                f.setValue(img, forKey: kCIInputImageKey)
                f.setValue(vibrance, forKey: "inputAmount")
                if let o = f.outputImage { img = o }
            }
        }

        // 6. Sharpness
        if sharpness != 0 {
            if let f = CIFilter(name: "CISharpenLuminance") {
                f.setValue(img, forKey: kCIInputImageKey)
                f.setValue(sharpness, forKey: "inputSharpness")
                if let o = f.outputImage { img = o }
            }
        }

        // 7. Warmth / Tint (CITemperatureAndTint)
        // inputNeutral = current source temperature (assumed 6500K)
        // inputTargetNeutral = desired temperature after shift
        if warmth != 0 || tint != 0 {
            if let f = CIFilter(name: "CITemperatureAndTint") {
                let neutralTemp = 6500.0
                let targetTemp  = neutralTemp + warmth * 30.0  // ±100 maps to ±3000K
                f.setValue(img, forKey: kCIInputImageKey)
                f.setValue(CIVector(x: neutralTemp, y: 0),    forKey: "inputNeutral")
                f.setValue(CIVector(x: targetTemp,  y: tint), forKey: "inputTargetNeutral")
                if let o = f.outputImage { img = o }
            }
        }

        return img
    }

    /// Apply to a CGImage synchronously (cover frame HEIC export + live preview).
    func apply(to cgImage: CGImage,
               autoParams: [(name: String, params: [String: Any])] = []) -> CGImage {
        guard !isIdentity || !autoParams.isEmpty else { return cgImage }
        let ci = CIImage(cgImage: cgImage)
        let result = apply(to: ci, autoParams: autoParams)
        let ctx = CIContext()
        let extent = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        return ctx.createCGImage(result, from: extent) ?? cgImage
    }

    // ── Auto-enhance helpers ─────────────────────────────────────────────────
    /// Run CIAutoAdjust on a reference CGImage and serialize the resulting filter parameters.
    /// Serialized form is safe to capture in concurrent closures (no live CIFilter state shared).
    static func computeAutoFilterParams(from cgImage: CGImage) -> [(name: String, params: [String: Any])] {
        let image = CIImage(cgImage: cgImage)
        let filters = image.autoAdjustmentFilters(options: [
            CIImageAutoAdjustmentOption.enhance: true,
            CIImageAutoAdjustmentOption.redEye:  false
        ])
        return filters.compactMap { filter in
            var params: [String: Any] = [:]
            for key in filter.inputKeys where key != kCIInputImageKey {
                if let val = filter.value(forKey: key) {
                    params[key] = val
                }
            }
            return params.isEmpty ? nil : (name: filter.name, params: params)
        }
    }
}
