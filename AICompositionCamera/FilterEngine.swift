import CoreImage
import UIKit

final class FilterEngine {
    private let context = CIContext()

    func apply(filter: PhotoFilter, to image: CIImage) -> CIImage {
        switch filter.id {
        case "vivid":
            return image
                .applyingColorControls(saturation: 1.25, brightness: 0.02, contrast: 1.18)
                .applyingHighlightShadow(highlight: 0.85, shadow: 0.18)
        case "warmFilm":
            return image
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 7600, y: 0))
                .applyingColorControls(saturation: 1.05, brightness: 0.015, contrast: 0.96)
                .applyingHighlightShadow(highlight: 0.72, shadow: 0.25)
        case "japaneseSoft":
            return image
                .applyingExposure(0.18)
                .applyingColorControls(saturation: 0.86, brightness: 0.03, contrast: 0.86)
                .applyingHighlightShadow(highlight: 0.68, shadow: 0.28)
        case "coolStreet":
            return image
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 5200, y: 0))
                .applyingColorControls(saturation: 0.95, brightness: -0.015, contrast: 1.28)
                .applyingHighlightShadow(highlight: 0.9, shadow: 0.02)
        case "monoClassic":
            return image
                .applyingFilter("CIPhotoEffectMono")
                .applyingColorControls(saturation: 0, brightness: 0, contrast: 1.16)
        case "retro":
            return image
                .applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.32])
                .applyingColorControls(saturation: 0.82, brightness: 0.01, contrast: 0.94)
        case "cyber":
            return image
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 4700, y: 70))
                .applyingColorControls(saturation: 1.34, brightness: -0.02, contrast: 1.32)
                .applyingHighlightShadow(highlight: 0.95, shadow: 0.0)
        case "softPortrait":
            return image
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 7100, y: 0))
                .applyingColorControls(saturation: 0.96, brightness: 0.035, contrast: 0.9)
                .applyingHighlightShadow(highlight: 0.76, shadow: 0.22)
        case "landscapePop":
            return image
                .applyingColorControls(saturation: 1.18, brightness: 0.01, contrast: 1.14)
                .applyingHighlightShadow(highlight: 0.82, shadow: 0.1)
        case "clarendon":
            return applyingClarendon(to: image)
        case "nashville":
            return applyingNashville(to: image)
        case "tealOrange":
            return image
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 5900, y: 45))
                .applyingColorControls(saturation: 1.2, brightness: -0.01, contrast: 1.24)
                .applyingToneCurve(p0: (0, 0), p1: (0.25, 0.18), p2: (0.5, 0.52), p3: (0.75, 0.84), p4: (1, 1))
        case "kodakGold":
            return image
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 7800, y: -20))
                .applyingColorControls(saturation: 1.12, brightness: 0.025, contrast: 1.04)
                .applyingHighlightShadow(highlight: 0.78, shadow: 0.2)
        case "fujiGreen":
            return image
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 6100, y: -55))
                .applyingColorControls(saturation: 1.04, brightness: 0.018, contrast: 1.06)
                .applyingHighlightShadow(highlight: 0.82, shadow: 0.22)
        case "cream":
            return image
                .applyingExposure(0.12)
                .applyingColorControls(saturation: 0.82, brightness: 0.04, contrast: 0.82)
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 7200, y: 0))
        case "foodie":
            return image
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 7600, y: 0))
                .applyingColorControls(saturation: 1.28, brightness: 0.035, contrast: 1.12)
        case "nightCity":
            return image
                .applyingExposure(-0.08)
                .applyingColorControls(saturation: 1.3, brightness: -0.025, contrast: 1.35)
                .applyingHighlightShadow(highlight: 0.98, shadow: 0.08)
        case "moodyDark":
            return image
                .applyingExposure(-0.22)
                .applyingColorControls(saturation: 0.88, brightness: -0.02, contrast: 1.34)
                .applyingToneCurve(p0: (0, 0), p1: (0.25, 0.16), p2: (0.5, 0.48), p3: (0.75, 0.82), p4: (1, 1))
        case "brightAir":
            return image
                .applyingExposure(0.18)
                .applyingColorControls(saturation: 0.94, brightness: 0.04, contrast: 0.9)
                .applyingHighlightShadow(highlight: 0.68, shadow: 0.26)
        case "noirHigh":
            return image
                .applyingFilter("CIPhotoEffectNoir")
                .applyingColorControls(saturation: 0, brightness: -0.01, contrast: 1.32)
        case "instant":
            return image
                .applyingFilter("CIPhotoEffectInstant")
                .applyingColorControls(saturation: 1.06, brightness: 0.01, contrast: 0.98)
        case "chrome":
            return image
                .applyingFilter("CIPhotoEffectChrome")
                .applyingColorControls(saturation: 1.08, brightness: 0, contrast: 1.08)
        case "fadeMatte":
            return image
                .applyingFilter("CIPhotoEffectFade")
                .applyingColorControls(saturation: 0.86, brightness: 0.015, contrast: 0.92)
                .applyingToneCurve(p0: (0, 0.08), p1: (0.25, 0.28), p2: (0.5, 0.52), p3: (0.75, 0.76), p4: (1, 0.96))
        case "summer":
            return image
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 7200, y: -15))
                .applyingColorControls(saturation: 1.24, brightness: 0.045, contrast: 1.08)
        case "autumn":
            return image
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 8200, y: -30))
                .applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.16])
                .applyingColorControls(saturation: 1.08, brightness: 0.005, contrast: 1.08)
        case "skinGlow":
            return image
                .applyingExposure(0.1)
                .applyingTemperature(neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 7000, y: 5))
                .applyingColorControls(saturation: 0.98, brightness: 0.035, contrast: 0.88)
        default:
            return image
        }
    }

    // Adapted from Yummypets/YPImagePicker's MIT-licensed CoreImage filter recipes.
    private func applyingClarendon(to image: CIImage) -> CIImage {
        let background = colorImage(red: 127, green: 187, blue: 227, alpha: 0.2, rect: image.extent)
        return image
            .applyingFilter("CIOverlayBlendMode", parameters: ["inputBackgroundImage": background])
            .applyingColorControls(saturation: 1.35, brightness: 0.05, contrast: 1.1)
    }

    private func applyingNashville(to image: CIImage) -> CIImage {
        let warm = colorImage(red: 247, green: 176, blue: 153, alpha: 0.56, rect: image.extent)
        let cool = colorImage(red: 0, green: 70, blue: 150, alpha: 0.4, rect: image.extent)
        return image
            .applyingFilter("CIDarkenBlendMode", parameters: ["inputBackgroundImage": warm])
            .applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.2])
            .applyingColorControls(saturation: 1.2, brightness: 0.05, contrast: 1.1)
            .applyingFilter("CILightenBlendMode", parameters: ["inputBackgroundImage": cool])
    }

    private func colorImage(red: Int, green: Int, blue: Int, alpha: Double, rect: CGRect) -> CIImage {
        let color = CIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha)
        )
        return CIImage(color: color).cropped(to: rect)
    }

    func makeUIImage(from image: CIImage) -> UIImage? {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    func apply(filter: PhotoFilter, to image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return image }
        let output = apply(filter: filter, to: ciImage)
        return makeUIImage(from: output)
    }
}

private extension CIImage {
    func applyingColorControls(saturation: Double, brightness: Double, contrast: Double) -> CIImage {
        applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: saturation,
                kCIInputBrightnessKey: brightness,
                kCIInputContrastKey: contrast
            ]
        )
    }

    func applyingExposure(_ ev: Double) -> CIImage {
        applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: ev])
    }

    func applyingTemperature(neutral: CIVector, target: CIVector) -> CIImage {
        applyingFilter(
            "CITemperatureAndTint",
            parameters: [
                "inputNeutral": neutral,
                "inputTargetNeutral": target
            ]
        )
    }

    func applyingHighlightShadow(highlight: Double, shadow: Double) -> CIImage {
        applyingFilter(
            "CIHighlightShadowAdjust",
            parameters: [
                "inputHighlightAmount": highlight,
                "inputShadowAmount": shadow
            ]
        )
    }

    func applyingToneCurve(
        p0: (Double, Double),
        p1: (Double, Double),
        p2: (Double, Double),
        p3: (Double, Double),
        p4: (Double, Double)
    ) -> CIImage {
        applyingFilter(
            "CIToneCurve",
            parameters: [
                "inputPoint0": CIVector(x: p0.0, y: p0.1),
                "inputPoint1": CIVector(x: p1.0, y: p1.1),
                "inputPoint2": CIVector(x: p2.0, y: p2.1),
                "inputPoint3": CIVector(x: p3.0, y: p3.1),
                "inputPoint4": CIVector(x: p4.0, y: p4.1)
            ]
        )
    }
}
