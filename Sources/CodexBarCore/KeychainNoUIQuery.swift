import Foundation

#if os(macOS)
import LocalAuthentication
import Security

enum KeychainNoUIQuery {
    static func apply(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        // NOTE: We rely on LAContext.interactionNotAllowed to suppress Keychain UI so operations return
        // errSecInteractionNotAllowed instead of prompting.
    }
}
#endif
