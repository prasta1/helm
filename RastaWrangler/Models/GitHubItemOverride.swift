import Foundation
import SwiftData

/// Local annotations for a GitHub issue or PR.
///
/// GitHub's public API has no due-date concept and the checkbox in the Tasks view
/// only marks items done locally (it never calls the GitHub API). This model
/// stores both pieces of local state keyed by the stable composite ID
/// "owner/repo#number" (e.g. "apple/swift#1234").
@Model final class GitHubItemOverride {
    /// Stable composite key: "owner/repo#number".
    var itemID: String
    /// User-assigned due date, stored locally since GitHub issues have none.
    var dueDate: Date?
    /// True when the user checked the item off in Helm. Does not affect GitHub.
    var isLocallyDone: Bool

    init(itemID: String) {
        self.itemID = itemID
        self.isLocallyDone = false
    }
}
