import ActivityKit
import ImageIO
import SwiftUI
import WidgetKit

private struct SpindleCardView: View {
    let name: String
    let card: SpindleActivityCard?
    let stale: Bool
    private var preview: UIImage? {
        guard let encoded = card?.imageBase64, let data = Data(base64Encoded: encoded), data.count <= 700,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 64,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 12) {
                if card?.layout == "image" {
                    Group {
                        if let image = preview { Image(uiImage: image).resizable().scaledToFit() }
                        else { Image(systemName: "photo").font(.title) }
                    }
                    .frame(width: 58, height: 58).clipped().accessibilityLabel("Image preview")
                } else {
                    Image(systemName: card?.symbol ?? "bell.fill").font(.title2).frame(width: 30).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(card?.title ?? "Open Lumiverse to refresh").font(.headline).lineLimit(2)
                    if stale && card?.terminal != true { Text("Waiting for update").font(.caption).foregroundStyle(.secondary) }
                    else if let body = card?.body, !body.isEmpty { Text(body).font(.subheadline).lineLimit(2) }
                }
            }
            if card?.layout == "progress", let value = card?.progress {
                ProgressView(value: value).accessibilityLabel("Progress").accessibilityValue("\(Int(value * 100)) percent")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14).foregroundStyle(.white)
    }
}

@available(iOS 16.1, *)
struct SpindleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpindleActivityAttributes.self) { context in
            SpindleCardView(name: context.attributes.extensionName, card: context.attributes.card(context.state), stale: isStale(context))
                .activityBackgroundTint(Color(white: 0.08)).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let card = context.attributes.card(context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    SpindleCardView(name: context.attributes.extensionName, card: card, stale: isStale(context))
                }
            } compactLeading: {
                Image(systemName: card?.symbol ?? "bell.fill").accessibilityLabel(context.attributes.extensionName)
            } compactTrailing: {
                if card?.layout == "progress", let progress = card?.progress {
                    Text("\(Int(progress * 100))%").font(.caption).monospacedDigit()
                } else { Image(systemName: card?.terminal == true ? "checkmark" : "ellipsis").accessibilityLabel(card?.title ?? "Activity") }
            } minimal: {
                Image(systemName: card?.symbol ?? "bell.fill").accessibilityLabel(card?.title ?? context.attributes.extensionName)
            }
        }
    }
    private func isStale(_ context: ActivityViewContext<SpindleActivityAttributes>) -> Bool {
        if #available(iOS 16.2, *) { return context.isStale }
        return false
    }
}
