import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// Minimal Keychain wrapper for one generic-password item.
struct Keychain {
    let service: String
    private let account = "oauth-tokens"

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    func write(_ data: Data) {
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete(base as CFDictionary)
    }
}

enum AuthError: LocalizedError {
    case notConnected
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to Dropbox."
        case .cancelled: return "Sign-in cancelled."
        case .failed(let message): return message
        }
    }
}

/// OAuth 2 code flow with PKCE via `ASWebAuthenticationSession`. Short-lived access tokens are refreshed
/// with a long-lived refresh token; both live in the Keychain. Scopes are the minimum the app needs.
@MainActor
final class DropboxAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiry: Date
    }

    static let scopes = ["files.content.read", "files.content.write", "files.metadata.read"]

    private let config: DropboxConfig
    private let keychain = Keychain(service: "Notation.Dropbox")
    private var tokens: Tokens?
    private var session: ASWebAuthenticationSession?

    var hasCredentials: Bool { tokens != nil }

    init(config: DropboxConfig) {
        self.config = config
        super.init()
        if let data = keychain.read() {
            tokens = try? JSONDecoder().decode(Tokens.self, from: data)
        }
    }

    func connect() async throws {
        let verifier = Self.randomString(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = Self.randomString(length: 24)

        var components = URLComponents(string: "https://www.dropbox.com/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.appKey),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "token_access_type", value: "offline"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: config.callbackScheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.failed("Sign-in failed."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: AuthError.failed("Couldn't open the Dropbox sign-in page."))
            }
        }
        session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw AuthError.failed(value("error_description") ?? error)
        }
        guard value("state") == state, let code = value("code") else {
            throw AuthError.failed("Dropbox sign-in returned an unexpected response.")
        }

        let response = try await requestToken([
            "code": code,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
            "client_id": config.appKey,
            "redirect_uri": config.redirectURI,
        ])
        guard let refresh = response.refresh_token else {
            throw AuthError.failed("Dropbox did not return a refresh token.")
        }
        store(Tokens(accessToken: response.access_token, refreshToken: refresh, expiry: Date().addingTimeInterval(TimeInterval(response.expires_in))))
    }

    func validAccessToken() async throws -> String {
        guard let current = tokens else { throw AuthError.notConnected }
        if current.expiry.timeIntervalSinceNow > 60 { return current.accessToken }
        do {
            let response = try await requestToken([
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "client_id": config.appKey,
            ])
            let updated = Tokens(
                accessToken: response.access_token,
                refreshToken: response.refresh_token ?? current.refreshToken,
                expiry: Date().addingTimeInterval(TimeInterval(response.expires_in))
            )
            store(updated)
            return updated.accessToken
        } catch let error as TokenError where error.revoked {
            disconnect()
            throw AuthError.notConnected
        }
    }

    func disconnect() {
        tokens = nil
        keychain.delete()
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    // MARK: - Token endpoint

    private struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var expires_in: Int
    }

    private struct TokenError: Error {
        var revoked: Bool
    }

    private func store(_ new: Tokens) {
        tokens = new
        if let data = try? JSONEncoder().encode(new) { keychain.write(data) }
    }

    private func requestToken(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(form).utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let text = String(decoding: data, as: UTF8.self)
            if status == 400, text.contains("invalid_grant") { throw TokenError(revoked: true) }
            throw AuthError.failed("Dropbox sign-in failed (HTTP \(status)).")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func formEncode(_ form: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return form
            .map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }

    private static func randomString(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(generator.next(upperBound: UInt(alphabet.count)))] })
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
