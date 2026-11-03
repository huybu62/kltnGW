import Foundation

struct ClientHello: Codable {
    var device: DeviceInfo
    var identityKey: Data
    /// SHA-256 commitment to the ephemeral key revealed in `KeyReveal`.
    var ephemeralCommitment: Data
}

struct ServerHello: Codable {
    var device: DeviceInfo
    var identityKey: Data
    var ephemeralKey: Data
    var nonce: Data
    /// Responder already has the initiator's identity key on file.
    var trustsPeer: Bool
}

struct KeyReveal: Codable {
    var ephemeralKey: Data
    var nonce: Data
    /// Initiator already has the responder's identity key on file.
    var trustsPeer: Bool
}

struct Authenticate: Codable {
    var signature: Data
}

public enum HandshakeFailureReason: String, Codable, Sendable {
    case rejectedByUser
    case busy
    case incompatibleVersion
    case identityMismatch
    case authenticationFailed
    case timeout
    case internalError

    public var userMessage: String {
        switch self {
        case .rejectedByUser: return "The other device declined the connection."
        case .busy: return "The other device is already connected to someone else."
        case .incompatibleVersion: return "The other device runs an incompatible ScreenBridge version. Update both apps."
        case .identityMismatch: return "The other device's identity didn't check out."
        case .authenticationFailed: return "Security check failed. Try pairing again."
        case .timeout: return "Pairing timed out."
        case .internalError: return "The other device hit an internal error."
        }
    }
}

struct HandshakeFailure: Codable {
    var reason: HandshakeFailureReason
    var detail: String?
}
