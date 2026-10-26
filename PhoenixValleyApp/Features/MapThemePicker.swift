import PhoenixValleyCore
import SwiftUI

struct ThemePicker: View {
    @Binding var selection: MapTheme
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(MapTheme.allCases) { theme in
                Button { selection = theme } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        ThemeSwatch(theme: theme)
                            .frame(height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            .overlay(alignment: .topTrailing) {
                                if selection == theme {
                                    Image(systemName: "checkmark.circle.fill")
                                        .symbolRenderingMode(.palette).foregroundStyle(.white, .tint)
                                        .padding(7)
                                }
                            }
                            .overlay { RoundedRectangle(cornerRadius: 13).stroke(selection == theme ? Color.accentColor : .primary.opacity(0.08), lineWidth: selection == theme ? 2 : 1) }
                        Text(theme.displayName).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map-theme-\(theme.rawValue)")
                .accessibilityLabel(theme.displayName)
                .accessibilityHint(theme.detail)
                .accessibilityAddTraits(selection == theme ? .isSelected : [])
            }
        }
        Text(selection.detail).font(.caption).foregroundStyle(.secondary)
    }
}

private struct ThemeSwatch: View {
    let theme: MapTheme
    var body: some View {
        Canvas { context, size in
            let p = theme.palette
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(cgColor: p.plain.cgColor)))
            let hill = Path(ellipseIn: CGRect(x: size.width*0.1, y: -size.height*0.4, width: size.width*0.95, height: size.height*1.35))
            context.fill(hill, with: .color(Color(cgColor: p.lowland.cgColor)))
            let ridge = Path(ellipseIn: CGRect(x: size.width*0.4, y: -size.height*0.25, width: size.width*0.65, height: size.height*0.8))
            context.fill(ridge, with: .color(Color(cgColor: p.hill.cgColor)))
            var water = Path()
            water.move(to: CGPoint(x: -10, y: size.height*0.68))
            water.addCurve(to: CGPoint(x: size.width+10, y: size.height*0.82), control1: CGPoint(x: size.width*0.3, y: size.height*0.05), control2: CGPoint(x: size.width*0.6, y: size.height*1.4))
            context.stroke(water, with: .color(Color(cgColor: p.water.cgColor)), style: StrokeStyle(lineWidth: 17, lineCap: .round))
            var road = Path()
            road.move(to: CGPoint(x: size.width*0.08, y: size.height*0.96))
            road.addCurve(to: CGPoint(x: size.width*0.88, y: -6), control1: CGPoint(x: size.width*0.15, y: size.height*0.28), control2: CGPoint(x: size.width*0.7, y: size.height*0.75))
            context.stroke(road, with: .color(Color(cgColor: p.roadCasing.cgColor)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            context.stroke(road, with: .color(Color(cgColor: p.motorway.cgColor)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            var branch = Path(); branch.move(to: CGPoint(x: 0, y: size.height*0.2)); branch.addLine(to: CGPoint(x: size.width, y: size.height*0.63))
            context.stroke(branch, with: .color(Color(cgColor: p.roadCasing.cgColor)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            context.stroke(branch, with: .color(Color(cgColor: p.street.cgColor)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
