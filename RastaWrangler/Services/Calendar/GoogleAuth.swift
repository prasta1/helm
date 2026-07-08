import Foundation
import Combine
import Security
import AuthenticationServices
import CryptoKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// OAuth 2.0 (PKCE) client for Google, shared by macOS and iOS via
/// `ASWebAuthenticationSession`.
///
/// ## Setup (one time)
/// 1. In Google Cloud Console create an OAuth **iOS** client (works for macOS
///    too) for the bundle id `com.rastawrangler.app`.
/// 2. Paste the Client ID into Settings → Google. The redirect scheme is the
///    reversed client id, which is already registered in `Info.plist`.
/// 3. Enable the Google Calendar API for the project.
@MainActor
final class GoogleAuth: NSObject, ObservableObject {

    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date

        var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
    }

    @Published private(set) var isSignedIn: Bool
    private let clientID: String
    private let keychain = KeychainStore.shared

    private let scopes = ["https://www.googleapis.com/auth/calendar.readonly"]

    init(clientID: String) {
        self.clientID = clientID
        self.isSignedIn = keychain.codable(Tokens.self, for: KeychainKey.googleTokens) != nil
        super.init()
    }

    /// The reversed-client-id redirect URI Google expects for native apps.
    private var redirectURI: String {
        let reversed = clientID
            .components(separatedBy: ".apps.googleusercontent.com").first
            .map { "com.googleusercontent.apps.\($0)" } ?? "com.rastawrangler.app"
        return "\(reversed):/oauth2redirect"
    }

    // MARK: Sign in

    func signIn() async throws {
        guard !clientID.isEmpty else { throw GoogleError.missingClientID }

        let verifier = Self.codeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]

        let callbackScheme = redirectURI.components(separatedBy: ":").first
        let callbackURL = try await authenticate(url: components.url!, scheme: callbackScheme)

        guard
            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
            let code = items.first(where: { $0.name == "code" })?.value
        else {
            throw GoogleError.noAuthCode
        }

        try await exchange(code: code, verifier: verifier)
        isSignedIn = true
    }

    func signOut() {
        keychain.delete(KeychainKey.googleTokens)
        isSignedIn = false
    }

    /// Returns a valid access token, refreshing it if necessary.
    func validAccessToken() async throws -> String {
        guard var tokens = keychain.codable(Tokens.self, for: KeychainKey.googleTokens) else {
            throw GoogleError.notSignedIn
        }
        if tokens.isExpired, let refresh = tokens.refreshToken {
            tokens = try await refreshTokens(refreshToken: refresh, previous: tokens)
            keychain.setCodable(tokens, for: KeychainKey.googleTokens)
        }
        return tokens.accessToken
    }

    // MARK: Token exchange

    private func exchange(code: String, verifier: String) async throws {
        let body = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        let response = try await tokenRequest(body: body)
        let tokens = Tokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in))
        )
        keychain.setCodable(tokens, for: KeychainKey.googleTokens)
    }

    private func refreshTokens(refreshToken: String, previous: Tokens) async throws -> Tokens {
        let body = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        let response = try await tokenRequest(body: body)
        return Tokens(
            accessToken: response.access_token,
            // Google omits the refresh token on refresh; keep the existing one.
            refreshToken: response.refresh_token ?? previous.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in))
        )
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    private func tokenRequest(body: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GoogleError.tokenExchange(String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: ASWebAuthenticationSession

    private func authenticate(url: URL, scheme: String?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? GoogleError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: GoogleError.cannotStartSession)
            }
        }
    }

    // MARK: PKCE helpers

    private static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    enum GoogleError: LocalizedError {
        case missingClientID, notSignedIn, noAuthCode, cancelled, cannotStartSession
        case tokenExchange(String)

        var errorDescription: String? {
            switch self {
            case .missingClientID: return "Add your Google OAuth Client ID in Settings first."
            case .notSignedIn: return "You're not signed in to Google."
            case .noAuthCode: return "Google didn't return an authorization code."
            case .cancelled: return "Sign-in was cancelled."
            case .cannotStartSession: return "Couldn't start the sign-in session."
            case let .tokenExchange(body): return "Token exchange failed. \(body)"
            }
        }
    }
}

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #endif
    }
}

extension Data {
    /// Base64URL without padding, per RFC 7636.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+")
        return set
    }()
}
