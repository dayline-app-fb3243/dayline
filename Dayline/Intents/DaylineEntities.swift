import AppIntents
import CoreSpotlight
import SwiftData
import Foundation

// Searchable projections of records visible in Dayline. Never index raw coordinates,
// photos, audio, friend data, or a voice note without an actual transcript.
private enum EntityIndex {
    static let name = "DaylineRecords"
    @MainActor static var context: ModelContext { ModelStore.container.mainContext }
    static func identifier<T: PersistentModel>(_ record: T) -> String {
        String(describing: record.persistentModelID.id)
    }
}

struct DaylineVisitEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Visited Place"
    static let defaultQuery = DaylineVisitQuery()
    let id: String
    @Property(title: "Place") var place: String
    @Property(title: "Arrived") var arrived: Date
    @Property(title: "Category") var category: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(place)", subtitle: "\(category)") }
    init(_ visit: Visit) {
        id = EntityIndex.identifier(visit)
        place = visit.placeName; arrived = visit.arrival; category = visit.categoryRaw
    }
}

struct DaylineVisitQuery: EntityStringQuery, IndexedEntityQuery {
    @MainActor func all() throws -> [DaylineVisitEntity] {
        try EntityIndex.context.fetch(FetchDescriptor<Visit>()).map(DaylineVisitEntity.init)
    }
    func entities(for identifiers: [String]) async throws -> [DaylineVisitEntity] {
        try await MainActor.run { try all().filter { identifiers.contains($0.id) } }
    }
    func entities(matching string: String) async throws -> [DaylineVisitEntity] {
        try await MainActor.run { try all().filter { $0.place.localizedStandardContains(string) }.prefix(30).map { $0 } }
    }
    func suggestedEntities() async throws -> [DaylineVisitEntity] {
        try await MainActor.run { Array(try all().sorted { $0.arrived > $1.arrived }.prefix(30)) }
    }
    @available(iOS 27.0, *)
    func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex(name: EntityIndex.name).indexAppEntities(try await entities(for: identifiers))
    }
    @available(iOS 27.0, *)
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex(name: EntityIndex.name).indexAppEntities(try await suggestedEntities())
    }
}

struct DaylineJournalEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Journal Entry"
    static let defaultQuery = DaylineJournalQuery()
    let id: String
    @Property(title: "Title") var title: String
    @Property(title: "Date") var date: Date
    @Property(title: "Words") var words: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
    init(_ entry: JournalEntry) {
        id = EntityIndex.identifier(entry)
        title = entry.title ?? entry.placeName ?? "Journal entry"
        date = entry.date; words = entry.text
    }
}

struct DaylineJournalQuery: EntityStringQuery, IndexedEntityQuery {
    @MainActor func all() throws -> [DaylineJournalEntity] {
        try EntityIndex.context.fetch(FetchDescriptor<JournalEntry>())
            .filter { !$0.text.isEmpty || !($0.title ?? "").isEmpty }
            .map(DaylineJournalEntity.init)
    }
    func entities(for identifiers: [String]) async throws -> [DaylineJournalEntity] {
        try await MainActor.run { try all().filter { identifiers.contains($0.id) } }
    }
    func entities(matching string: String) async throws -> [DaylineJournalEntity] {
        try await MainActor.run { Array(try all().filter { $0.title.localizedStandardContains(string) || $0.words.localizedStandardContains(string) }.prefix(30)) }
    }
    func suggestedEntities() async throws -> [DaylineJournalEntity] {
        try await MainActor.run { Array(try all().sorted { $0.date > $1.date }.prefix(30)) }
    }
    @available(iOS 27.0, *)
    func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex(name: EntityIndex.name).indexAppEntities(try await entities(for: identifiers))
    }
    @available(iOS 27.0, *)
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex(name: EntityIndex.name).indexAppEntities(try await suggestedEntities())
    }
}

struct DaylinePlanEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Plan"
    static let defaultQuery = DaylinePlanQuery()
    let id: String
    @Property(title: "Title") var title: String
    @Property(title: "Starts") var starts: Date
    @Property(title: "Ends") var ends: Date
    @Property(title: "Done") var done: Bool
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
    init(_ plan: PlanItem) {
        id = EntityIndex.identifier(plan)
        title = plan.title; starts = plan.start; ends = plan.end; done = plan.isDone
    }
}

struct DaylinePlanQuery: EntityStringQuery, IndexedEntityQuery {
    @MainActor func all() throws -> [DaylinePlanEntity] {
        try EntityIndex.context.fetch(FetchDescriptor<PlanItem>()).map(DaylinePlanEntity.init)
    }
    func entities(for identifiers: [String]) async throws -> [DaylinePlanEntity] {
        try await MainActor.run { try all().filter { identifiers.contains($0.id) } }
    }
    func entities(matching string: String) async throws -> [DaylinePlanEntity] {
        try await MainActor.run { Array(try all().filter { $0.title.localizedStandardContains(string) }.prefix(30)) }
    }
    func suggestedEntities() async throws -> [DaylinePlanEntity] {
        try await MainActor.run { Array(try all().sorted { $0.starts > $1.starts }.prefix(30)) }
    }
    @available(iOS 27.0, *)
    func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex(name: EntityIndex.name).indexAppEntities(try await entities(for: identifiers))
    }
    @available(iOS 27.0, *)
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex(name: EntityIndex.name).indexAppEntities(try await suggestedEntities())
    }
}

struct DaylinePastScoreEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Past Day Score"
    static let defaultQuery = DaylinePastScoreQuery()
    let id: String
    @Property(title: "Date") var date: Date
    @Property(title: "Score") var score: Int
    @Property(title: "Summary") var summary: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "Day score \(score)") }
    init(_ day: DayScore) {
        id = EntityIndex.identifier(day)
        date = day.day; score = day.score; summary = day.summary
    }
}

struct DaylinePastScoreQuery: EntityQuery, IndexedEntityQuery {
    @MainActor func all() throws -> [DaylinePastScoreEntity] {
        try EntityIndex.context.fetch(FetchDescriptor<DayScore>()).map(DaylinePastScoreEntity.init)
    }
    func entities(for identifiers: [String]) async throws -> [DaylinePastScoreEntity] {
        try await MainActor.run { try all().filter { identifiers.contains($0.id) } }
    }
    func suggestedEntities() async throws -> [DaylinePastScoreEntity] {
        try await MainActor.run { Array(try all().sorted { $0.date > $1.date }.prefix(30)) }
    }
    @available(iOS 27.0, *)
    func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex(name: EntityIndex.name).indexAppEntities(try await entities(for: identifiers))
    }
    @available(iOS 27.0, *)
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex(name: EntityIndex.name).indexAppEntities(try await suggestedEntities())
    }
}

@MainActor
enum DaylineSearchIndex {
    // Prototype refresh replaces the named index so deleted or edited records cannot linger.
    static func refresh(context: ModelContext) async {
        let index = CSSearchableIndex(name: EntityIndex.name)
        do {
            try await index.deleteAllSearchableItems()
            try await index.indexAppEntities(context.fetch(FetchDescriptor<Visit>()).map(DaylineVisitEntity.init))
            let journal = try context.fetch(FetchDescriptor<JournalEntry>())
                .filter { !$0.text.isEmpty || !($0.title ?? "").isEmpty }
            try await index.indexAppEntities(journal.map(DaylineJournalEntity.init))
            try await index.indexAppEntities(context.fetch(FetchDescriptor<PlanItem>()).map(DaylinePlanEntity.init))
            try await index.indexAppEntities(context.fetch(FetchDescriptor<DayScore>()).map(DaylinePastScoreEntity.init))
        } catch { NSLog("Dayline Spotlight refresh failed: %@", String(describing: error)) }
    }
    static func clear() async {
        do { try await CSSearchableIndex(name: EntityIndex.name).deleteAllSearchableItems() }
        catch { NSLog("Dayline Spotlight clear failed: %@", String(describing: error)) }
    }
}
