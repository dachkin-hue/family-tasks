import Foundation

enum FamilyRole: String, Codable, Sendable, CaseIterable {
    case parent
    case child

    var title: String {
        switch self {
        case .parent: return "Родитель"
        case .child: return "Ребёнок"
        }
    }
}

struct UserDTO: Codable, Sendable, Equatable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let email: String
    let role: FamilyRole
    /// Цвет аватара в формате "#RRGGBB", приходит с сервера. Может отсутствовать.
    let colorHex: String?

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

extension UserDTO {
    static let previewParent = UserDTO(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "Александр",
        email: "dad@example.com",
        role: .parent,
        colorHex: "#3B82F6"
    )

    static let previewPartner = UserDTO(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        name: "Мария",
        email: "mom@example.com",
        role: .parent,
        colorHex: "#EC4899"
    )

    static let previewChild = UserDTO(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        name: "Соня",
        email: "sonya@example.com",
        role: .child,
        colorHex: "#10B981"
    )
}
