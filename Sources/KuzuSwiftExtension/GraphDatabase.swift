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
    private var migrationPolicy: MigrationPolicy = .safeOnly
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
            databasePath: dbPath
        )
        
        let context = try await GraphContext(configuration: configuration)
        
        // Apply schema for registered models using MigrationManager
        if !registeredModels.isEmpty {
            let migrationManager = MigrationManager(
                context: context,
                policy: migrationPolicy
            )
            try await migrationManager.migrate(types: registeredModels)
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
        registeredModels.append(contentsOf: models)
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
    
    /// Create an isolated database context for testing.
    /// Each call creates a new, independent database instance.
    public static func createTestContext(
        name: String = UUID().uuidString,
        models: [any _KuzuGraphModel.Type] = [],
        migrationPolicy: MigrationPolicy = .safeOnly
    ) async throws -> GraphContext {
        // Use in-memory database for tests to avoid file system issues
        let configuration = GraphConfiguration(databasePath: ":memory:")
        let context = try await GraphContext(configuration: configuration)
        
        // Apply schema if models provided
        if !models.isEmpty {
            let migrationManager = MigrationManager(
                context: context,
                policy: migrationPolicy
            )
            try await migrationManager.migrate(types: models)
        }
        
        return context
    }
    
    // MARK: - Private Methods
    
    /// Internal close method - only for app lifecycle
    private func close() async throws {
        if let context = self.context {
            await context.close()
        }
        // Do NOT reset context or isInitialized
        // This prevents accidental re-initialization
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
        
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
           processName.contains("xctest") || 
           processName.contains("testing") {
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