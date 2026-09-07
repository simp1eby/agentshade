import ServiceManagement

public enum LoginItemToggleIntent: Equatable {
    case enable
    case disable
    case showApprovalInstructions
}

public enum LoginItemStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval

    public var toggleIntent: LoginItemToggleIntent {
        switch self {
        case .disabled: return .enable
        case .enabled: return .disable
        case .requiresApproval: return .showApprovalInstructions
        }
    }
}

public final class LoginItemController {
    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound, .notRegistered:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}
