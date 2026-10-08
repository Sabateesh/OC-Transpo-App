import MapKit
import SwiftUI

struct JourneyCompanionBar: View {
    let open: () -> Void
    @State private var session = JourneySession.shared
    var body: some View {
        if let cue = session.cue {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: cue.symbol).font(.title3).frame(width: 40, height: 40).background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cue.title).font(.headline).lineLimit(1)
                        Text(session.destination?.title ?? "Your journey").font(.caption).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").font(.headline)
                }.padding(12).foregroundStyle(.white).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 6)
                .accessibilityLabel("Resume journey. \(cue.title). \(session.destination?.title ?? "")")
        }
    }
}

struct JourneyCompanionHost: ViewModifier {
    var handlesDeepLinks = false
    @State private var showGuide = false
    @State private var pendingDestination: Destination?
    @State private var replanDestination: Destination?
    @State private var replanOrigin: Destination?
    @State private var session = JourneySession.shared

    func body(content: Content) -> some View {
        content
            .onAppear {
                #if DEBUG
                if JourneyPreview.enabled, !session.isRunning { JourneyPreview.start(); showGuide = !ProcessInfo.processInfo.arguments.contains("--minimized") }
                #endif
            }
            .onChange(of: session.openRequested) { _, requested in
                if requested && handlesDeepLinks && session.isRunning {
                    showGuide = true; session.openRequested = false
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { JourneyCompanionBar { showGuide = true } }
            .fullScreenCover(isPresented: $showGuide, onDismiss: {
                replanDestination = pendingDestination; pendingDestination = nil
            }) {
                JourneyGuideView { here in
                    pendingDestination = session.destination
                    replanOrigin = here.map { location in
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate)); item.name = "Current location"
                        return Destination(item: item)
                    }
                }
            }
            .sheet(item: $replanDestination) { destination in DestinationView(destination: destination, startingPoint: replanOrigin) }
    }
}
