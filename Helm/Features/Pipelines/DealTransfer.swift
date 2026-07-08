import Foundation
import UniformTypeIdentifiers
import CoreTransferable

/// Lightweight payload used for drag-and-drop of deals between stage columns.
struct DealTransfer: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .helmDeal)
    }
}

extension UTType {
    static let helmDeal = UTType(exportedAs: "com.helm.deal")
}
