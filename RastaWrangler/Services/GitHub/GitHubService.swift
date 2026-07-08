import Foundation

/// A lightweight value type representing a GitHub issue or pull request.
/// Views never see GitHub's raw API types.
struct GitHubItem: Identifiable, Hashable {
    /// Stable composite key: "owner/repo#number".
    let id: String
    let number: Int
    /// "owner/repo" slug, e.g. "apple/swift".
    let repoSlug: String
    let title: String
    let body: String
    let htmlURL: URL
    /// True when the GitHub payload includes a "pull_request" key.
    let isPR: Bool
    let createdAt: Date
    let labels: [String]
}

/// Fetches open issues and PRs from public GitHub repos via the REST API.
///
/// No authentication is required for public repos; the unauthenticated rate
/// limit of 60 requests/hour is more than enough for personal use. All repos
/// are fetched concurrently via `withTaskGroup`.
struct GitHubService {
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Fetches all open issues and PRs for the given list of "owner/repo" slugs,
    /// running each request concurrently. Repos that fail to fetch are silently
    /// dropped; use the returned `errors` set to surface warnings.
    func fetchItems(for repos: [String]) async -> (items: [GitHubItem], errors: Set<String>) {
        await withTaskGroup(of: (String, [GitHubItem])?.self) { group in
            for repo in repos {
                group.addTask {
                    let items = await self.fetch(repo: repo)
                    return items.map { (repo, $0) } != nil ? (repo, items) : nil
                }
            }
            var all: [GitHubItem] = []
            var errors: Set<String> = []
            for await result in group {
                if let (repo, items) = result {
                    if items.isEmpty && !repos.contains(repo) {
                        errors.insert(repo)
                    }
                    all.append(contentsOf: items)
                }
            }
            return (all, errors)
        }
    }

    /// Fetches open issues/PRs for a single repo. Returns an empty array on
    /// any network or decoding error so the caller always gets a value.
    func fetch(repo: String) async -> [GitHubItem] {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/issues?state=open&per_page=100") else {
            return []
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        guard let (data, _) = try? await session.data(for: request),
              let payloads = try? decoder.decode([GitHubIssuePayload].self, from: data) else {
            return []
        }

        return payloads.map { p in
            GitHubItem(
                id: "\(repo)#\(p.number)",
                number: p.number,
                repoSlug: repo,
                title: p.title,
                body: p.body ?? "",
                htmlURL: p.htmlUrl,
                isPR: p.pullRequest != nil,
                createdAt: p.createdAt,
                labels: p.labels.map(\.name)
            )
        }
    }
}

// MARK: - Private decoding types

private struct GitHubIssuePayload: Decodable {
    let number: Int
    let title: String
    let body: String?
    let htmlUrl: URL
    let createdAt: Date
    let labels: [LabelPayload]
    let pullRequest: EmptyPayload?

    struct LabelPayload: Decodable { let name: String }
    struct EmptyPayload: Decodable {}
}
