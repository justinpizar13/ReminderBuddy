import Foundation
import AuthenticationServices
import SwiftUI

/// Manages Sign in with Apple and persists the lightweight local identity.
///
/// Sign in with Apple gives us a stable, app-scoped user identifier and (only on the
/// first authorization) the person's name. We store the name in the Keychain-backed
/// user defaults suite and reuse the identifier to tag tasks/notes with who did what.
@MainActor
final class AuthManager: NSObject, ObservableObject {

    @Published private(set) var currentUser: AppUser?
    @Published var authError: String?

    private let userKey = "reminderbuddy.appuser"

    override init() {
        super.init()
        loadPersistedUser()
    }

    var isSignedIn: Bool { currentUser != nil }

    // MARK: Persistence

    private func loadPersistedUser() {
        guard let data = UserDefaults.standard.data(forKey: userKey),
              let user = try? JSONDecoder().decode(AppUser.self, from: data) else { return }
        currentUser = user
    }

    private func persist(_ user: AppUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    /// Re-validates the stored Apple credential on launch. If the user revoked access,
    /// we clear the local identity and force a fresh sign-in.
    func revalidateCredentialState() {
        guard let user = currentUser else { return }
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: user.userID) { [weak self] state, _ in
            guard state != .authorized else { return }
            Task { @MainActor in self?.signOut() }
        }
    }

    func signOut() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    // MARK: Sign in

    func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                authError = "Unexpected credential type."
                return
            }
            let userID = credential.user
            // Name is only provided on first sign-in; fall back to a saved/default name.
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let resolvedName: String
            if !fullName.isEmpty {
                resolvedName = fullName
            } else if let existing = currentUser, existing.userID == userID {
                resolvedName = existing.displayName
            } else {
                resolvedName = "Me"
            }
            persist(AppUser(userID: userID, displayName: resolvedName))
            authError = nil

        case .failure(let error):
            // User cancelling is not an error worth surfacing loudly.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            authError = error.localizedDescription
        }
    }

    /// Lets a person rename themselves locally (useful since Apple only shares the name once).
    func updateDisplayName(_ name: String) {
        guard var user = currentUser else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        user.displayName = trimmed
        persist(user)
    }
}
