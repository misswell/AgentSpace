import Foundation

public enum SoftwareUpdateError: Error, Equatable {
    case invalidRelease
    case missingVerifiedArchive
    case invalidResponse
    case digestMismatch
    case invalidApplication
    case versionMismatch
    case invalidSignature
    case wrongDeveloperTeam
    case identityMismatch
    case gatekeeperRejected
    case archiveMountFailed
    case installationUnavailable(String)
    case updaterHelperMissing
    case commandFailed(String)
}

/// A failure reduced to the one thing the UI can say about it.
///
/// The raw values are message identities, not text: the GUI renders each one
/// through its own localized `Text`, so an untranslated update error is caught
/// by `LocalizationTests` like any other string.
public struct SoftwareUpdateFailure: Equatable {
    public enum Message: String {
        case release
        case integrity
        case verification
        case location
        case helper
        case network
        case command
    }

    public let message: Message
    public let detail: String?

    public init(_ error: Error) {
        guard let error = error as? SoftwareUpdateError else {
            message = .network
            detail = error.localizedDescription
            return
        }
        switch error {
        case .invalidRelease, .missingVerifiedArchive, .invalidResponse:
            message = .release
            detail = nil
        case .digestMismatch:
            message = .integrity
            detail = nil
        case .invalidApplication, .versionMismatch, .invalidSignature, .wrongDeveloperTeam,
             .identityMismatch, .gatekeeperRejected, .archiveMountFailed:
            message = .verification
            detail = nil
        case .installationUnavailable(let reason):
            message = .location
            detail = reason
        case .updaterHelperMissing:
            message = .helper
            detail = nil
        case .commandFailed(let output):
            message = .command
            detail = output
        }
    }
}

public enum SoftwareUpdateState: Equatable {
    public enum Activity: String {
        case checking
        case downloading
        case installing
    }

    case idle
    case checking
    case upToDate
    case available(SoftwareRelease)
    case downloading(SoftwareRelease)
    case installing(SoftwareRelease)
    case failed(SoftwareUpdateFailure)

    public var activity: Activity? {
        switch self {
        case .checking: return .checking
        case .downloading: return .downloading
        case .installing: return .installing
        default: return nil
        }
    }

    public var isBusy: Bool { activity != nil }

    public var availableRelease: SoftwareRelease? {
        switch self {
        case .available(let release), .downloading(let release), .installing(let release):
            return release
        default: return nil
        }
    }
}
