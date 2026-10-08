import SwiftUI

struct LocationRecoveryView: View {
    @Environment(Location.self) private var location
    @Environment(\.openURL) private var openURL
    let chooseAddress: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if location.status == .locating { ProgressView() }
                else { Image(systemName: "location.slash") }
                Text(location.status.message).font(.subheadline)
            }
            HStack {
                if location.status == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } else if location.status != .restricted {
                    Button("Try again") { location.retry() }.disabled(location.status == .locating)
                }
                Button("Choose starting address", action: chooseAddress)
            }.font(.subheadline.weight(.semibold))
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding().background(.background, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
    }
}
