import Foundation
import Contacts
import Combine

class ContactsManager: ObservableObject {
    static let shared = ContactsManager()
    private let store = CNContactStore()
    @Published var authorized = false

    init() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        authorized = (status == .authorized)
        if status == .notDetermined { requestAccess() }
    }

    func requestAccess() {
        store.requestAccess(for: .contacts) { granted, _ in
            DispatchQueue.main.async { self.authorized = granted }
        }
    }

    func search(_ query: String, limit: Int = 8) -> [CNContact] {
        guard !query.isEmpty else { return [] }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
                    CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
                    CNContactThumbnailImageDataKey] as [CNKeyDescriptor]
        let results = (try? store.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: query),
            keysToFetch: keys
        )) ?? []
        return Array(results.prefix(limit))
    }

    func find(_ name: String) -> CNContact? {
        guard authorized, !name.isEmpty else { return nil }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
                    CNContactIdentifierKey] as [CNKeyDescriptor]
        let results = (try? store.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: name),
            keysToFetch: keys
        )) ?? []
        let exact = results.first { displayName($0).lowercased() == name.lowercased() }
        return exact ?? results.first
    }

    func displayName(_ c: CNContact) -> String {
        let full = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty
            ? c.emailAddresses.first.map { String($0.value) } ?? "Unknown"
            : full
    }

    func slug(_ c: CNContact) -> String {
        displayName(c)
            .components(separatedBy: .whitespaces)
            .map { $0.capitalized }
            .joined()
    }
}
