import Foundation

/// Lifecycle of one AgentSpace (plan §26).
///
/// The ordering matters: the UI's whole job is to move a Space from `created`
/// toward `running`, and every state that is not `running` is one the agent
/// must be told about rather than worked around.
public enum SpaceState: String, Codable, Sendable, CaseIterable {
    /// The macOS user exists; nothing has been installed yet.
    case created
    /// The platform user exists but has never had a GUI login, so there is no
    /// Aqua session. Nothing can be driven from here.
    case needsLogin
    /// Logged in and the worker is up, but a required TCC grant is missing.
    case needsPermission
    /// Logged in, worker up, grants present, worker idle. Ready to accept work.
    case ready
    /// Worker is executing something right now.
    case running
    /// The user exists but no worker is listening.
    case offline
    /// The Space's session is the physical console. Input is refused until
    /// the human switches away; see `SessionGuard`.
    case console
    /// Something is wrong that the user has to resolve.
    case error

    /// Is it safe to send input to this Space right now?
    ///
    /// This is the single predicate the whole input path keys off. `console`
    /// is the important one: it is *not* an error, it is a hard refusal.
    public var acceptsInput: Bool {
        switch self {
        case .ready, .running: return true
        case .created, .needsLogin, .needsPermission, .offline, .console, .error:
            return false
        }
    }

    /// Human-facing label, used by the CLI and the dashboard.
    public var displayName: String {
        switch self {
        case .created: return "Created"
        case .needsLogin: return "Needs Login"
        case .needsPermission: return "Needs Permission"
        case .ready: return "Ready"
        case .running: return "Running"
        case .offline: return "Offline"
        case .console: return "On Console"
        case .error: return "Error"
        }
    }

    /// The state to *show*, which is not always the state that was stored
    /// (plan §39). Pure so the GUI, the CLI and tests all derive it the same
    /// way — a disagreement here is exactly the "components disagree" bug
    /// class this project keeps finding.
    ///
    /// The `hasGraphicalSession` discriminator resolves the §39 question: a
    /// worker that went down because **nobody is logged in** must show
    /// `needsLogin` (the fix is a fast user switch, not a retry), while a
    /// worker that died under a live session shows `offline`. `nil` means the
    /// lookup could not be performed; the pre-existing `offline` behaviour is
    /// kept rather than guessed at.
    public static func effective(
        stored: SpaceState,
        workerOnline: Bool,
        sessionVerdict: String?,
        permissionProblem: AgentSpaceErrorCode?,
        hasGraphicalSession: Bool?
    ) -> SpaceState {
        if let permissionProblem {
            if permissionProblem == .accessibilityDenied || permissionProblem == .screenRecordingDenied {
                return .needsPermission
            }
        }
        if sessionVerdict == "isConsole" { return .console }
        if !workerOnline, stored == .ready || stored == .running {
            switch hasGraphicalSession {
            case .some(true): return .offline
            case .some(false): return .needsLogin
            case nil: return .offline
            }
        }
        return stored
    }
}

/// Which TCC grants the agent session has (plan §19).
public struct PermissionState: Codable, Equatable, Sendable {
    public var screenRecording: Bool
    public var accessibility: Bool

    public init(screenRecording: Bool = false, accessibility: Bool = false) {
        self.screenRecording = screenRecording
        self.accessibility = accessibility
    }

    public var allGranted: Bool { screenRecording && accessibility }

    /// What is still missing, in the order the setup flow should ask for it.
    public var missing: [String] {
        var out: [String] = []
        if !accessibility { out.append("Accessibility") }
        if !screenRecording { out.append("Screen Recording") }
        return out
    }
}

/// A directory handed to the agent session (plan §25).
///
/// Read-only is the default on purpose: an agent that can silently rewrite the
/// folder you are working in is the failure mode this type exists to prevent.
public struct SharedFolder: Codable, Equatable, Sendable, Identifiable {
    public enum Access: String, Codable, Sendable, CaseIterable {
        case readOnly = "readOnly"
        case readWrite = "readWrite"

        public var displayName: String {
            switch self {
            case .readOnly: return "Read Only"
            case .readWrite: return "Read & Write"
            }
        }
    }

    /// Absolute path on the host, as the *main user* sees it.
    public var path: String
    public var access: Access

    public var id: String { path }

    public init(path: String, access: Access = .readOnly) {
        self.path = path
        self.access = access
    }
}

/// Where the agent is allowed to write code (plan §24).
///
/// A Git worktree is preferred over a plain shared folder because it removes
/// the "agent and human editing the same working tree" class of bug entirely:
/// separate directory, separate branch, shared object store.
public enum Workspace: Codable, Equatable, Sendable {
    case none
    /// A `git worktree` cut from `repository` onto `branch`, living at `path`
    /// inside the Space's own home.
    case gitWorktree(repository: String, branch: String, path: String)
    /// The agent uses shared folders only.
    case sharedFolders

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .gitWorktree(let repo, let branch, _): return "Git Worktree — \(branch) @ \(repo)"
        case .sharedFolders: return "Shared Folder"
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, repository, branch, path }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "gitWorktree":
            self = .gitWorktree(
                repository: try c.decode(String.self, forKey: .repository),
                branch: try c.decode(String.self, forKey: .branch),
                path: try c.decode(String.self, forKey: .path))
        case "sharedFolders":
            self = .sharedFolders
        default:
            self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode("none", forKey: .kind)
        case .gitWorktree(let repository, let branch, let path):
            try c.encode("gitWorktree", forKey: .kind)
            try c.encode(repository, forKey: .repository)
            try c.encode(branch, forKey: .branch)
            try c.encode(path, forKey: .path)
        case .sharedFolders:
            try c.encode("sharedFolders", forKey: .kind)
        }
    }
}

/// The persisted record for one Space (plan §26).
public struct AgentSpace: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// The platform account this Space drives, e.g. `_agentspace_a37f91`.
    public var username: String
    public var uid: uid_t
    public var state: SpaceState
    public var createdAt: Date
    public var lastStartedAt: Date?
    public var workspace: Workspace
    public var sharedFolders: [SharedFolder]
    public var permissions: PermissionState
    public var autoStartWorker: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        username: String,
        uid: uid_t,
        state: SpaceState = .created,
        createdAt: Date = Date(),
        lastStartedAt: Date? = nil,
        workspace: Workspace = .none,
        sharedFolders: [SharedFolder] = [],
        permissions: PermissionState = PermissionState(),
        autoStartWorker: Bool = true
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.uid = uid
        self.state = state
        self.createdAt = createdAt
        self.lastStartedAt = lastStartedAt
        self.workspace = workspace
        self.sharedFolders = sharedFolders
        self.permissions = permissions
        self.autoStartWorker = autoStartWorker
    }
}

/// Live resource numbers for a Space, aggregated **by uid** (plan §30).
///
/// Deliberately not "allocated" figures: a Space is not a VM, so the honest
/// thing to show is what its processes are actually using.
public struct ResourceUsage: Codable, Equatable, Sendable {
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var processCount: Int
    /// Allocated bytes in the Space's home. Only meaningful when `diskMeasured`.
    public var diskBytes: UInt64
    /// Whether the home directory was actually walked. Distinct from
    /// `diskBytes == 0`, which is what an *empty* home legitimately measures —
    /// conflating the two would let the UI claim a Space uses no disk because
    /// nobody looked (plan §30).
    public var diskMeasured: Bool
    /// True when the walk hit its budget, making `diskBytes` a lower bound.
    public var diskTruncated: Bool

    public init(
        cpuPercent: Double = 0,
        memoryBytes: UInt64 = 0,
        processCount: Int = 0,
        diskBytes: UInt64 = 0,
        diskMeasured: Bool = false,
        diskTruncated: Bool = false
    ) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processCount = processCount
        self.diskBytes = diskBytes
        self.diskMeasured = diskMeasured
        self.diskTruncated = diskTruncated
    }

    public var memoryDisplay: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    public var diskDisplay: String {
        guard diskMeasured else { return "not measured" }
        let text = ByteCountFormatter.string(fromByteCount: Int64(diskBytes), countStyle: .file)
        return diskTruncated ? "at least \(text)" : text
    }
}
