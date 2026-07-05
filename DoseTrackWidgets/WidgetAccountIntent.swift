// DoseTrackWidgets/WidgetAccountIntent.swift
// Lets a caregiver configure a widget to show their own medications, or an
// overseen patient's, via the standard "Edit Widget" configuration UI.
import AppIntents
import WidgetKit

struct WidgetAccountEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static var defaultQuery = WidgetAccountQuery()

    /// `"self"` represents the signed-in user's own account; anything else is a patient userId.
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WidgetAccountQuery: EntityQuery {
    func entities(for identifiers: [WidgetAccountEntity.ID]) async throws -> [WidgetAccountEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetAccountEntity] {
        let own = WidgetAccountEntity(id: "self", name: "You")
        let patients = WidgetAccountStore.overseenPatients().compactMap { option -> WidgetAccountEntity? in
            guard let id = option.id else { return nil }
            return WidgetAccountEntity(id: id, name: option.name)
        }
        return [own] + patients
    }

    func defaultResult() async -> WidgetAccountEntity? {
        WidgetAccountEntity(id: "self", name: "You")
    }
}

struct SelectDoseAccountIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Account"
    static var description = IntentDescription("Show your own medications, or a patient you're overseeing as a caregiver.")

    // No compile-time `default:` — AppIntents only allows that for literal types. Falls back to
    // `WidgetAccountQuery.defaultResult()` ("You") when nothing has been configured yet.
    @Parameter(title: "Show")
    var account: WidgetAccountEntity

    /// `nil` = the signed-in user's own account, matching `WidgetDataProvider.context(for:)`.
    var storageAccountId: String? { account.id == "self" ? nil : account.id }
}
