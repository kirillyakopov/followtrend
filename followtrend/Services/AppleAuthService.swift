//
//  AppleAuthService.swift
//  followtrend
//
//  Native iOS Sign In with Apple using AuthenticationServices.
//
//  ── SETUP REQUIRED (Apple Developer Portal) ────────────────────────────
//  1. In Xcode → Target → Signing & Capabilities → "+ Capability" → "Sign In with Apple"
//  2. In your Apple Developer account (developer.apple.com):
//     - Register an App ID with "Sign In with Apple" capability enabled
//     - Your APPLE_TEAM_ID is found in the top-right of the developer portal
//     - Your APPLE_CLIENT_ID is your app's Bundle Identifier (e.g. com.yourname.followtrend)
//  3. For server-side token verification (optional, for backend use):
//     APPLE_TEAM_ID   = your 10-char team ID
//     APPLE_CLIENT_ID = your Bundle ID
//     APPLE_KEY_ID    = the key ID from the Services Key you create
//     APPLE_PRIVATE_KEY = the .p8 private key file contents
//  ───────────────────────────────────────────────────────────────────────

import Foundation
import Combine
import AuthenticationServices

// MARK: - Auth State

enum AppleAuthState: Equatable {
    case signedOut
    case signedIn(userID: String, fullName: String?, email: String?)
}

// MARK: - Apple Auth Service

final class AppleAuthService: NSObject, ObservableObject {

    static let shared = AppleAuthService()

    @Published var authState: AppleAuthState = .signedOut

    private let userIDKey    = "apple_user_id"
    private let userNameKey  = "apple_user_name"
    private let userEmailKey = "apple_user_email"

    private override init() {
        super.init()
        // Restore previous sign-in state
        if let storedID = UserDefaults.standard.string(forKey: userIDKey) {
            let name  = UserDefaults.standard.string(forKey: userNameKey)
            let email = UserDefaults.standard.string(forKey: userEmailKey)
            // Verify credential is still valid with Apple
            let provider = ASAuthorizationAppleIDProvider()
            provider.getCredentialState(forUserID: storedID) { [weak self] state, _ in
                DispatchQueue.main.async {
                    if state == .authorized {
                        self?.authState = .signedIn(userID: storedID, fullName: name, email: email)
                    } else {
                        self?.clearSession()
                    }
                }
            }
        }
    }

    // MARK: - Sign In

    func signIn() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - Sign Out

    func signOut() {
        clearSession()
    }

    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: userIDKey)
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        DispatchQueue.main.async { self.authState = .signedOut }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleAuthService: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }

        let userID   = credential.user
        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty()
        let email = credential.email

        UserDefaults.standard.set(userID, forKey: userIDKey)
        if let fn = fullName { UserDefaults.standard.set(fn, forKey: userNameKey) }
        if let em = email    { UserDefaults.standard.set(em, forKey: userEmailKey) }

        DispatchQueue.main.async {
            self.authState = .signedIn(userID: userID, fullName: fullName, email: email)
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        // User cancelled or error — stay signed out silently
        print("[AppleAuth] Sign in failed: \(error.localizedDescription)")
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleAuthService: ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            fatalError("No window scene found for ASAuthorizationController")
        }
        return scene.windows.first { $0.isKeyWindow } ?? UIWindow(windowScene: scene)
    }
}

// MARK: - String helper

private extension String {
    func nilIfEmpty() -> String? { isEmpty ? nil : self }
}
