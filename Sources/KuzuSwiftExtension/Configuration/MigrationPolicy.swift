import Foundation

public enum MigrationPolicy: Sendable {
    case safeOnly
    case allowDestructive
}