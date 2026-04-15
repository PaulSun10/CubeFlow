import SwiftUI

enum AppearanceStyleOption: String, CaseIterable, Identifiable, Codable {
    case system
    case color
    case gradient
    case photo

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .system:
            return "settings.timer_bg_system"
        case .color:
            return "settings.timer_bg_color"
        case .gradient:
            return "settings.timer_bg_gradient"
        case .photo:
            return "settings.timer_bg_photo"
        }
    }
}

enum AppearanceModeVariant: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .light:
            return "settings.appearance_light_mode"
        case .dark:
            return "settings.appearance_dark_mode"
        }
    }
}

struct StoredColorData: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(color: Color) {
        let rgba = color.toRGBA()
        self.init(r: rgba.r, g: rgba.g, b: rgba.b, a: rgba.a)
    }

    var color: Color {
        let sanitized = sanitized()
        return Color(
            red: sanitized.r,
            green: sanitized.g,
            blue: sanitized.b,
            opacity: sanitized.a
        )
    }

    func sanitized() -> StoredColorData {
        StoredColorData(
            r: sanitizeUnit(r),
            g: sanitizeUnit(g),
            b: sanitizeUnit(b),
            a: sanitizeUnit(a)
        )
    }
}

struct StoredGradientData: Codable, Equatable {
    var stops: [GradientStopData]
    var angle: Double

    init(stops: [GradientStopData], angle: Double) {
        self.stops = stops
        self.angle = angle
    }

    init(stops: [GradientStop], angle: Double) {
        self.init(stops: stops.map(GradientStopData.init(from:)), angle: angle)
    }

    var resolvedStops: [Gradient.Stop] {
        let sanitizedStops = sanitized().stops
        if sanitizedStops.isEmpty {
            return AppearanceConfiguration.defaultGradientStops
        }

        return sanitizedStops.map { stop in
            Gradient.Stop(
                color: Color(red: stop.r, green: stop.g, blue: stop.b, opacity: stop.a),
                location: max(0, min(1, stop.location))
            )
        }
    }

    var pickerStops: [GradientStop] {
        let sanitizedStops = sanitized().stops
        if sanitizedStops.isEmpty {
            return AppearanceConfiguration.defaultPickerStops
        }
        return sanitizedStops.toStops
    }

    func sanitized() -> StoredGradientData {
        let sanitizedStops = stops
            .map { stop in
                GradientStopData(
                    id: stop.id,
                    r: sanitizeUnit(stop.r),
                    g: sanitizeUnit(stop.g),
                    b: sanitizeUnit(stop.b),
                    a: sanitizeUnit(stop.a),
                    location: sanitizeUnit(stop.location)
                )
            }
            .sorted { $0.location < $1.location }

        return StoredGradientData(
            stops: sanitizedStops,
            angle: angle.isFinite ? angle.truncatingRemainder(dividingBy: 360) : 0
        )
    }
}

struct AppearanceConfiguration: Codable, Equatable {
    var styleRaw: String
    var lightColor: StoredColorData
    var darkColor: StoredColorData
    var lightGradient: StoredGradientData
    var darkGradient: StoredGradientData

    var style: AppearanceStyleOption {
        get { AppearanceStyleOption(rawValue: styleRaw) ?? .system }
        set { styleRaw = newValue.rawValue }
    }

    func color(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? darkColor.color : lightColor.color
    }

    func gradient(for colorScheme: ColorScheme) -> StoredGradientData {
        colorScheme == .dark ? darkGradient : lightGradient
    }

    mutating func setColor(_ color: Color, for variant: AppearanceModeVariant) {
        switch variant {
        case .light:
            lightColor = StoredColorData(color: color).sanitized()
        case .dark:
            darkColor = StoredColorData(color: color).sanitized()
        }
    }

    mutating func setGradientStops(_ stops: [GradientStop], for variant: AppearanceModeVariant) {
        switch variant {
        case .light:
            lightGradient = StoredGradientData(stops: stops, angle: lightGradient.angle).sanitized()
        case .dark:
            darkGradient = StoredGradientData(stops: stops, angle: darkGradient.angle).sanitized()
        }
    }

    mutating func setGradientAngle(_ angle: Double, for variant: AppearanceModeVariant) {
        switch variant {
        case .light:
            lightGradient.angle = angle.isFinite ? angle.truncatingRemainder(dividingBy: 360) : 0
        case .dark:
            darkGradient.angle = angle.isFinite ? angle.truncatingRemainder(dividingBy: 360) : 0
        }
    }

    static func decode(from data: Data?, fallback: AppearanceConfiguration) -> AppearanceConfiguration {
        guard let data,
              let decoded = try? JSONDecoder().decode(AppearanceConfiguration.self, from: data) else {
            return fallback
        }
        return decoded.sanitized()
    }

    func sanitized() -> AppearanceConfiguration {
        AppearanceConfiguration(
            styleRaw: style.rawValue,
            lightColor: lightColor.sanitized(),
            darkColor: darkColor.sanitized(),
            lightGradient: lightGradient.sanitized(),
            darkGradient: darkGradient.sanitized()
        )
    }

    static let defaultPickerStops: [GradientStop] = [
        GradientStop(color: Color(red: 0.92, green: 0.96, blue: 1.0), location: 0),
        GradientStop(color: Color(red: 0.98, green: 0.93, blue: 1.0), location: 1)
    ]

    static let defaultGradientStops: [Gradient.Stop] = [
        Gradient.Stop(color: Color(red: 0.92, green: 0.96, blue: 1.0), location: 0),
        Gradient.Stop(color: Color(red: 0.98, green: 0.93, blue: 1.0), location: 1)
    ]

    static let defaultLightGradient = StoredGradientData(
        stops: defaultPickerStops,
        angle: 0
    )

    static let defaultDarkGradient = StoredGradientData(
        stops: [
            GradientStop(color: Color(red: 0.18, green: 0.21, blue: 0.28), location: 0),
            GradientStop(color: Color(red: 0.09, green: 0.11, blue: 0.16), location: 1)
        ],
        angle: 0
    )

    static let defaultBackground = AppearanceConfiguration(
        styleRaw: AppearanceStyleOption.system.rawValue,
        lightColor: StoredColorData(r: 0.90, g: 0.95, b: 1.00),
        darkColor: StoredColorData(r: 0.13, g: 0.15, b: 0.20),
        lightGradient: defaultLightGradient,
        darkGradient: defaultDarkGradient
    )

    static let defaultTimerText = AppearanceConfiguration(
        styleRaw: AppearanceStyleOption.system.rawValue,
        lightColor: StoredColorData(r: 0.05, g: 0.05, b: 0.06),
        darkColor: StoredColorData(r: 0.95, g: 0.95, b: 0.97),
        lightGradient: defaultLightGradient,
        darkGradient: defaultDarkGradient
    )

    static let defaultScrambleText = AppearanceConfiguration(
        styleRaw: AppearanceStyleOption.system.rawValue,
        lightColor: StoredColorData(r: 0.14, g: 0.14, b: 0.16),
        darkColor: StoredColorData(r: 0.90, g: 0.90, b: 0.92),
        lightGradient: defaultLightGradient,
        darkGradient: defaultDarkGradient
    )

    static let defaultAverageText = AppearanceConfiguration(
        styleRaw: AppearanceStyleOption.system.rawValue,
        lightColor: StoredColorData(r: 114.0 / 255.0, g: 114.0 / 255.0, b: 114.0 / 255.0),
        darkColor: StoredColorData(r: 0.72, g: 0.72, b: 0.74),
        lightGradient: defaultLightGradient,
        darkGradient: defaultDarkGradient
    )
}

private func sanitizeUnit(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return max(0, min(1, value))
}
