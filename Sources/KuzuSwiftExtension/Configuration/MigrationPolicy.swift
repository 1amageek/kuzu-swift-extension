import Foundation

public enum MigrationPolicy: Sendable {
    case none
    case safeOnly
    case allowDestructive
    
    public var allowsAddingTables: Bool {
        switch self {
        case .none:
            return false
        case .safeOnly, .allowDestructive:
            return true
        }
    }
    
    public var allowsAddingColumns: Bool {
        switch self {
        case .none:
            return false
        case .safeOnly, .allowDestructive:
            return true
        }
    }
    
    public var allowsDroppingTables: Bool {
        switch self {
        case .none, .safeOnly:
            return false
        case .allowDestructive:
            return true
        }
    }
    
    public var allowsDroppingColumns: Bool {
        switch self {
        case .none, .safeOnly:
            return false
        case .allowDestructive:
            return true
        }
    }
    
    public var allowsModifyingColumns: Bool {
        switch self {
        case .none, .safeOnly:
            return false
        case .allowDestructive:
            return true
        }
    }
}