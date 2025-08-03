import Foundation

public struct GraphSchema: Sendable {
    public let models: [any _KuzuGraphModel.Type]
    
    public init(_ models: [any _KuzuGraphModel.Type]) {
        self.models = models
    }
    
    public init(_ models: any _KuzuGraphModel.Type...) {
        self.models = models
    }
}