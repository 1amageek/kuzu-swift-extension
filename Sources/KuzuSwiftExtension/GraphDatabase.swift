import Foundation
import Kuzu
#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// SwiftData-style singleton database manager with automatic lifecycle
@MainActor
public final class GraphDatabase {
    public static let shared = GraphDatabase()
    
    private var context: GraphContext?
    private var registeredModels: [any _KuzuGraphModel.Type] = []
    
    private init() {
        setupLifecycleHandlers()
    }
    
    /// Get or create the default graph context with automatic path resolution
    public func context() async throws -> GraphContext {
        if let context = self.context {
            return context
        }
        
        let configuration = GraphConfiguration(
            databasePath: Self.defaultDatabasePath()
        )
        
        let context = try await GraphContext(configuration: configuration)
        
        // Auto-create schema if database is new
        if Self.isDatabaseNew(at: configuration.databasePath) {
            try await context.createSchemaForRegisteredModels(registeredModels)
        }
        
        self.context = context
        
        return context
    }
    
    /// Register model types for automatic schema creation
    public func register(models: [any _KuzuGraphModel.Type]) {
        registeredModels.append(contentsOf: models)
    }
    
    /// Close the database (called automatically on app termination)
    public func close() async throws {
        if let context = self.context {
            await context.close()
        }
        self.context = nil
    }
    
    // MARK: - Private Helpers
    
    private static func defaultDatabasePath() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent(".kuzu")
        #else
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let bundleID = Bundle.main.bundleIdentifier ?? "com.app.kuzu"
        let appDir = appSupport.appendingPathComponent(bundleID)
        #endif
        
        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: appDir,
            withIntermediateDirectories: true
        )
        
        return appDir.appendingPathComponent("graph.kuzu").path
    }
    
    private static func isDatabaseNew(at path: String) -> Bool {
        !FileManager.default.fileExists(atPath: path)
    }
    
    private func setupLifecycleHandlers() {
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        #elseif os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        #endif
    }
    
    @objc private func applicationWillTerminate() {
        Task { @MainActor in
            try? await close()
        }
    }
    
    @objc private func applicationWillResignActive() {
        Task { @MainActor in
            try? await flush()
        }
    }
    
    /// Flush any pending operations to disk
    public func flush() async throws {
        // Kuzu automatically flushes on connection close, 
        // but we can ensure data integrity by recreating the connection
        if let _ = self.context {
            // No explicit flush needed - Kuzu handles this internally
            // This method exists for API completeness and future enhancements
        }
    }
}

// MARK: - Auto-discovery of GraphNode types
extension GraphContext {
    func createSchemaForRegisteredModels(_ models: [any _KuzuGraphModel.Type]) async throws {
        guard !models.isEmpty else { return }
        try await createSchema(for: models)
    }
}