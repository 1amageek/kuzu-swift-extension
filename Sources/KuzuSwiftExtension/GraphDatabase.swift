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
    private var migrationPolicy: MigrationPolicy = .safe
    private var isInitialized = false
    
    private init() {
        setupLifecycleHandlers()
    }
    
    /// Get the shared graph context. Always returns the same instance once initialized.
    public func context() async throws -> GraphContext {
        // Return existing context if available
        if let context = self.context {
            return context
        }
        
        // Create new context only if not initialized
        guard !isInitialized else {
            throw GraphError.contextNotAvailable(
                reason: "Database context was closed. Application restart required."
            )
        }
        
        let dbPath = Self.defaultDatabasePath()
        let configuration = GraphConfiguration(
            databasePath: dbPath,
            migrationMode: .automatic  // Default to automatic migration
        )
        
        let context = try await GraphContext(configuration: configuration)
        
        // Apply schema based on migration mode
        if !registeredModels.isEmpty {
            switch configuration.migrationMode {
            case .automatic:
                // SwiftData-style: automatically create schemas, skip existing
                try await context.createSchemasIfNotExist(for: registeredModels)
                
            case .managed(let policy):
                // Traditional: use MigrationManager with policy
                let migrationManager = MigrationManager(
                    context: context,
                    policy: policy
                )
                try await migrationManager.migrate(types: registeredModels)
                
            case .none:
                // No automatic migration
                break
            }
        }
        
        self.context = context
        self.isInitialized = true
        
        return context
    }
    
    /// Register model types for automatic schema creation.
    /// Must be called before first context() access.
    public func register(models: [any _KuzuGraphModel.Type]) {
        guard !isInitialized else {
            // Models registered after initialization won't be migrated automatically
            return
        }
        
        // Prevent duplicate registration by checking type names
        for model in models {
            let modelName = String(describing: model)
            let isAlreadyRegistered = registeredModels.contains { existingModel in
                String(describing: existingModel) == modelName
            }
            
            if !isAlreadyRegistered {
                registeredModels.append(model)
            }
        }
    }
    
    /// Configure migration policy.
    /// Must be called before first context() access.
    public func configure(migrationPolicy: MigrationPolicy) {
        guard !isInitialized else {
            // Migration policy changes after initialization have no effect
            return
        }
        self.migrationPolicy = migrationPolicy
    }
    
    // MARK: - Test Support

    #if DEBUG
    /// Create an isolated database context for testing.
    /// Each call creates a new, independent in-memory database instance.
    /// - Parameter models: Models to register with the context
    /// - Returns: A new GraphContext with automatic schema migration
    public static func createTestContext(
        models: [any _KuzuGraphModel.Type] = []
    ) async throws -> GraphContext {
        return try await container(
            for: models,
            inMemory: true,
            migrationMode: .automatic
        )
    }
    #endif
    
    /// SwiftData-style container creation
    /// Creates a new GraphContext with the specified models and configuration
    public static func container(
        for models: [any _KuzuGraphModel.Type],
        inMemory: Bool = false,
        migrationMode: GraphConfiguration.MigrationMode = .automatic
    ) async throws -> GraphContext {
        let configuration = GraphConfiguration(
            databasePath: inMemory ? ":memory:" : defaultDatabasePath(),
            migrationMode: migrationMode
        )
        
        let context = try await GraphContext(configuration: configuration)
        
        // Apply schema based on migration mode
        switch migrationMode {
        case .automatic:
            // SwiftData-style: automatically create schemas, skip existing
            try await context.createSchemasIfNotExist(for: models)
            
        case .managed(let policy):
            // Traditional: use MigrationManager with policy
            let migrationManager = MigrationManager(
                context: context,
                policy: policy
            )
            try await migrationManager.migrate(types: models)
            
        case .none:
            // No automatic migration
            break
        }
        
        return context
    }
    
    // MARK: - Private Methods
    
    /// Internal close method - only for app lifecycle
    private func close() async throws {
        if let context = self.context {
            await context.close()
            self.context = nil
            self.isInitialized = false
        }
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
        
        // Bundle IDを優先的に使用、なければプロセス名ベースのフォールバック
        let directoryName: String
        let processName = ProcessInfo.processInfo.processName
        
        if ProcessInfo.processInfo.environment["SWIFT_TESTING"] != nil ||
           processName.contains("testing") ||
           processName.hasSuffix("PackageTests") {
            // テスト環境: 一時ディレクトリを使用
            let tempDir = FileManager.default.temporaryDirectory
            let appDir = tempDir.appendingPathComponent("kuzu-tests/\(processName)")
            
            do {
                try FileManager.default.createDirectory(
                    at: appDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                // Failed to create test directory - will use temp directory fallback
            }
            
            return appDir.appendingPathComponent("graph.kuzu").path
        } else if let bundleID = Bundle.main.bundleIdentifier {
            // アプリ環境: bundleIDを使用（既存の動作を維持）
            directoryName = bundleID
        } else {
            // SPM/CLI環境: プロセス名を使用
            directoryName = "kuzu/\(processName)"
        }
        
        let appDir = appSupport.appendingPathComponent(directoryName)
        #endif
        
        // ディレクトリ作成のエラーハンドリング改善
        do {
            try FileManager.default.createDirectory(
                at: appDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            // Failed to create directory - continue anyway (directory may already exist)
        }
        
        return appDir.appendingPathComponent("graph.kuzu").path
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
        // Kuzu automatically handles flushing, no action needed
    }
}