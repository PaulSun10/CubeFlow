import SwiftUI

struct GradientStop: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var color: Color
    var location: CGFloat
}

struct GradientStopData: Codable, Equatable {
    var id: String?
    var r: Double
    var g: Double
    var b: Double
    var a: Double
    var location: Double
}

extension GradientStopData {
    nonisolated init(from stop: GradientStop) {
        let rgba = stop.color.toRGBA()
        self.id = stop.id
        self.r = rgba.r
        self.g = rgba.g
        self.b = rgba.b
        self.a = rgba.a
        self.location = Double(stop.location)
    }

    var toStop: GradientStop {
        GradientStop(
            id: id ?? legacyIdentifier,
            color: Color(red: r, green: g, blue: b, opacity: a),
            location: CGFloat(location)
        )
    }

    private var legacyIdentifier: String {
        "\(r)-\(g)-\(b)-\(a)-\(location)"
    }
}

extension Array where Element == GradientStopData {
    var toStops: [GradientStop] {
        map { $0.toStop }
    }
}

extension Color {
    nonisolated func toRGBA() -> (r: Double, g: Double, b: Double, a: Double) {
        #if os(iOS)
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #else
        return (0, 0, 0, 1)
        #endif
    }
}

struct GradientPicker: View {
    @Binding var stops: [GradientStop]
    @Binding var angle: Double

    @State private var selectedStopID: String?

    private let barHeight: CGFloat = 18
    private let handleSize: CGFloat = 18

    var body: some View {
        VStack(spacing: 10) {
            gradientEditor
            if let selectedIndex {
                ColorPicker(
                    "gradient_picker.color",
                    selection: Binding(
                        get: { stops[selectedIndex].color },
                        set: { newValue in
                            stops[selectedIndex].color = newValue
                        }
                    )
                )
                .labelsHidden()
            }

            HStack(spacing: 12) {
                Button("gradient_picker.remove_stop") {
                    removeSelectedStop()
                }
                .disabled(!canRemoveSelected)

                Spacer()
            }

            HStack {
                Text("gradient_picker.angle")
                    .font(.system(size: 15, weight: .medium))
                Slider(value: $angle, in: 0...360, step: 1)
                Text("\(Int(angle))°")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if selectedStopID == nil {
                selectedStopID = stops.first?.id
            }
        }
    }

    private var gradientEditor: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous)
                    .fill(LinearGradient(
                        gradient: Gradient(stops: gradientStops),
                        startPoint: gradientStartPoint,
                        endPoint: gradientEndPoint
                    ))
                    .frame(height: barHeight)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                addStop(at: value.location, width: width)
                            }
                    )

                ForEach(stops) { stop in
                    stopHandle(stop: stop, width: width)
                }
            }
        }
        .frame(height: 48)
    }

    private func stopHandle(stop: GradientStop, width: CGFloat) -> some View {
        let isSelected = stop.id == selectedStopID
        return Circle()
            .fill(stop.color)
            .frame(
                width: isSelected ? handleSize + 6 : handleSize,
                height: isSelected ? handleSize + 6 : handleSize
            )
            .overlay(
                Circle()
                    .stroke(.white.opacity(isSelected ? 0.9 : 0.5), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            .position(
                x: clamp(stop.location, min: 0, max: 1) * width,
                y: 12
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectedStopID = stop.id
                        let newLocation = clamp(value.location.x / width, min: 0, max: 1)
                        updateStop(id: stop.id, location: newLocation)
                    }
            )
            .onTapGesture {
                selectedStopID = stop.id
            }
    }

    private var selectedIndex: Int? {
        guard let selectedStopID else { return nil }
        return stops.firstIndex(where: { $0.id == selectedStopID })
    }

    private var canRemoveSelected: Bool {
        stops.count > 2 && selectedIndex != nil
    }

    private func removeSelectedStop() {
        guard canRemoveSelected, let selectedIndex else { return }
        stops.remove(at: selectedIndex)
        selectedStopID = stops.first?.id
    }

    private func updateStop(id: String, location: CGFloat) {
        guard let index = stops.firstIndex(where: { $0.id == id }) else { return }
        stops[index].location = location
    }

    private func addStop(at tapLocation: CGPoint, width: CGFloat) {
        let location = clamp(tapLocation.x / width, min: 0, max: 1)
        let color = interpolatedColor(at: location)
        let newStop = GradientStop(color: color, location: location)
        stops.append(newStop)
        selectedStopID = newStop.id
        normalizeStopOrder()
    }

    private func normalizeStopOrder() {
        stops.sort { $0.location < $1.location }
    }

    private func interpolatedColor(at location: CGFloat) -> Color {
        let sorted = stops.sorted { $0.location < $1.location }
        guard let first = sorted.first, let last = sorted.last else {
            return .white
        }

        if location <= first.location {
            return first.color
        }
        if location >= last.location {
            return last.color
        }

        var lower = first
        var upper = last
        for stop in sorted {
            if stop.location <= location {
                lower = stop
            } else {
                upper = stop
                break
            }
        }

        let range = max(upper.location - lower.location, 0.0001)
        let t = (location - lower.location) / range
        let c1 = lower.color.toRGBA()
        let c2 = upper.color.toRGBA()
        return Color(
            red: c1.r + (c2.r - c1.r) * Double(t),
            green: c1.g + (c2.g - c1.g) * Double(t),
            blue: c1.b + (c2.b - c1.b) * Double(t),
            opacity: c1.a + (c2.a - c1.a) * Double(t)
        )
    }

    private var gradientStops: [Gradient.Stop] {
        stops.map { stop in
            Gradient.Stop(color: stop.color, location: clamp(stop.location, min: 0, max: 1))
        }
    }

    private var gradientStartPoint: UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    private var gradientEndPoint: UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}
