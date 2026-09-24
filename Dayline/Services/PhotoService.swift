import Foundation
import Photos
import UIKit
import SwiftData

/// Pulls photos (and the location saved inside each photo) into the timeline.
@MainActor
final class PhotoService {
    static let shared = PhotoService()

    enum PhotoError: LocalizedError {
        case noAccess, noPhotos
        var errorDescription: String? {
            switch self {
            case .noAccess: "Dayline needs access to your photos."
            case .noPhotos: "No photos found."
            }
        }
    }

    func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Adds the latest `count` photos (skipping ones already in the journal). Used by "journal by voice" in Siri.
    @discardableResult
    func addLatestPhotos(count: Int, context: ModelContext) async throws -> [JournalEntry] {
        guard await requestAccess() else { throw PhotoError.noAccess }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = max(1, min(count, 20))
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        guard assets.count > 0 else { throw PhotoError.noPhotos }
        let known = Set(((try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []).compactMap(\.photoAssetID))
        var list: [PHAsset] = []
        assets.enumerateObjects { a, _, _ in if !known.contains(a.localIdentifier) { list.append(a) } }
        var out: [JournalEntry] = []
        for a in list { out.append(try await addEntry(for: a, context: context)) }
        return out
    }

    /// Imports today's photos that are not in the journal yet. Their EXIF location also
    /// becomes a location check-in, which fills gaps between the low-power samples.
    func importPhotos(on day: Date, context: ModelContext) async {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized ||
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else { return }
        let window = DayBoundary.shared.window(for: day)
        let start = window.start, end = window.end
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        let assets = PHAsset.fetchAssets(with: .image, options: options)

        let known = Set(((try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []).compactMap(\.photoAssetID))
        var toAdd: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            if !known.contains(asset.localIdentifier) { toAdd.append(asset) }
        }
        for asset in toAdd { _ = try? await addEntry(for: asset, context: context) }
    }

    private func addEntry(for asset: PHAsset, context: ModelContext) async throws -> JournalEntry {
        let thumb = await thumbnail(for: asset)
        let entry = JournalEntry(date: asset.creationDate ?? .now, kind: .photo,
                                 photoAssetID: asset.localIdentifier,
                                 thumbnail: thumb?.jpegData(compressionQuality: 0.7),
                                 latitude: asset.location?.coordinate.latitude,
                                 longitude: asset.location?.coordinate.longitude)
        context.insert(entry)
        if let loc = asset.location {
            context.insert(LocationSample(timestamp: asset.creationDate ?? .now, latitude: loc.coordinate.latitude,
                                          longitude: loc.coordinate.longitude,
                                          horizontalAccuracy: loc.horizontalAccuracy, source: "photo"))
        }
        try context.save()
        return entry
    }

    private func thumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 600, height: 600),
                                                  contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
