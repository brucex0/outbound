import Combine
import Foundation

enum SafetyDeliveryChannel: String, Codable, CaseIterable, Identifiable {
    case sms
    case push

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sms: "SMS"
        case .push: "Push"
        }
    }
}

struct SafetyContact: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var deliveryChannel: SafetyDeliveryChannel
    var deliveryAddress: String
    var isDefault: Bool
    var isEnabledForLiveShare: Bool
    let createdAt: Date

    var displayAddress: String {
        deliveryAddress.isEmpty ? deliveryChannel.title : deliveryAddress
    }
}

@MainActor
final class SafetyContactStore: ObservableObject {
    @Published private(set) var contacts: [SafetyContact] = []

    private let defaults: UserDefaults
    private let contactsKey = "safety_contacts_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        contacts = Self.loadContacts(defaults: defaults, key: contactsKey)
        normalizeDefault()
    }

    var enabledContacts: [SafetyContact] {
        contacts.filter(\.isEnabledForLiveShare)
    }

    var defaultContact: SafetyContact? {
        enabledContacts.first(where: \.isDefault) ?? enabledContacts.first
    }

    func addContact(name: String, channel: SafetyDeliveryChannel, address: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let shouldDefault = enabledContacts.isEmpty
        contacts.append(
            SafetyContact(
                id: UUID().uuidString,
                name: trimmedName,
                deliveryChannel: channel,
                deliveryAddress: trimmedAddress,
                isDefault: shouldDefault,
                isEnabledForLiveShare: true,
                createdAt: Date()
            )
        )
        normalizeDefault()
        save()
    }

    func remove(_ contact: SafetyContact) {
        contacts.removeAll { $0.id == contact.id }
        normalizeDefault()
        save()
    }

    func setDefault(_ contact: SafetyContact) {
        contacts = contacts.map { existing in
            var updated = existing
            updated.isDefault = existing.id == contact.id
            if existing.id == contact.id {
                updated.isEnabledForLiveShare = true
            }
            return updated
        }
        save()
    }

    func setEnabled(_ contact: SafetyContact, isEnabled: Bool) {
        contacts = contacts.map { existing in
            var updated = existing
            if existing.id == contact.id {
                updated.isEnabledForLiveShare = isEnabled
                if !isEnabled {
                    updated.isDefault = false
                }
            }
            return updated
        }
        normalizeDefault()
        save()
    }

    private func normalizeDefault() {
        let enabledIDs = Set(contacts.filter(\.isEnabledForLiveShare).map(\.id))
        guard !enabledIDs.isEmpty else {
            contacts = contacts.map {
                var updated = $0
                updated.isDefault = false
                return updated
            }
            return
        }

        let currentDefaultID = contacts.first { $0.isDefault && enabledIDs.contains($0.id) }?.id
            ?? contacts.first { enabledIDs.contains($0.id) }?.id
        contacts = contacts.map {
            var updated = $0
            updated.isDefault = updated.id == currentDefaultID
            return updated
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(contacts) else { return }
        defaults.set(data, forKey: contactsKey)
    }

    private static func loadContacts(defaults: UserDefaults, key: String) -> [SafetyContact] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SafetyContact].self, from: data) else {
            return []
        }
        return decoded
    }
}
