import SwiftUI

struct RouteBadge: View {
    let route: Route
    var small = false

    var body: some View {
        let corner: CGFloat = small ? 4 : 6
        Text(route.name)
            .font((small ? Font.caption : .headline).weight(.semibold).monospacedDigit())
            .foregroundStyle(Color(hex: route.textColor) ?? .white)
            .padding(.horizontal, small ? 4 : 6)
            .frame(minWidth: small ? 28 : 44, minHeight: small ? 20 : 32)
            .background(Color(hex: route.color) ?? .accentColor, in: .rect(cornerRadius: corner))
            .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(Color.primary.opacity(0.1)))
    }
}

extension Color {
    init?(hex: String) {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(red: Double(value >> 16 & 0xFF) / 255,
                  green: Double(value >> 8 & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
