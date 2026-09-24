import SwiftUI
import UIKit

/// The card Siri shows for "take me to the place I ate four days ago".
/// Styled like Siri's own weather card: a rounded deep-blue gradient card, white text.
struct PlaceSnippetView: View {
    var place: RecalledPlace
    var route: RouteSnapshot? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SiriAppLine()
            if let route, let image = UIImage(data: route.image) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 170).clipped()
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Text(route.etaText).font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(.black.opacity(0.7), in: .capsule).padding(10)
                    }
            } else if !place.photos.isEmpty {
                PhotoStrip(photos: place.photos, height: 104)
            }
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name).font(.headline).lineLimit(1)
                    if let route { Text(route.detailText).font(.footnote).foregroundStyle(.white.opacity(0.6)) }
                    Text("Last visit \(place.whenText)").font(.footnote).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Link(destination: place.directionsURL) {
                    Text("Go").font(.body.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(Color.green, in: .capsule)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(SiriCardBackground())
    }
}

struct SiriCardBackground: View {
    var body: some View {
        // Black so the card blends into the iOS 27 Siri background (approved mockup).
        Color.black
    }
}

struct PhotoStrip: View {
    var photos: [Data]
    var height: CGFloat
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(photos.prefix(3).enumerated()), id: \.offset) { _, data in
                if let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: height)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}
