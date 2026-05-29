import Foundation
import RevenueCat
import SwiftUI

@MainActor
public class SubscriptionManager: ObservableObject {
    public static let shared = SubscriptionManager()
    
    @Published public var isSubscribed: Bool = false
    @Published public var originalAppVersion: String? = nil
    @Published public var hasFullAccess: Bool = true
    
    public let legacyThresholdVersion = "1.0.1"
    public let legacyThresholdBuild = 65
    
    // Load current version from Bundle
    public var currentAppVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    
    public var isLegacyVersion: Bool {
        return isVersionLegacy(currentAppVersion)
    }
    
    private init() {
        updateAccessStatus()
    }
    
    public func configure() {
        // Initialize RevenueCat with production Public API Key
        Purchases.configure(withAPIKey: "appl_udTmDvmHDxPBlyuEOUIPefjKdrG")
        
        // Fetch initial subscription status
        Task {
            await checkSubscriptionStatus()
        }
    }
    
    public func checkSubscriptionStatus() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            self.isSubscribed = customerInfo.entitlements["ai_slide_editor_vip"]?.isActive ?? false
            self.originalAppVersion = customerInfo.originalApplicationVersion
        } catch {
            print("⚠️ [SubscriptionManager] Failed to fetch customer info: \(error.localizedDescription)")
        }
        updateAccessStatus()
    }
    
    public func purchaseYearlySubscription() async throws -> Bool {
        let offerings = try await Purchases.shared.offerings()
        // Strictly use 'ai_slide_editor' offering for this app
        guard let package = offerings["ai_slide_editor"]?.annual else {
            throw NSError(domain: "SubscriptionManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Annual subscription package not found in 'ai_slide_editor' offering."])
        }
        
        let result = try await Purchases.shared.purchase(package: package)
        self.isSubscribed = result.customerInfo.entitlements["ai_slide_editor_vip"]?.isActive ?? false
        self.originalAppVersion = result.customerInfo.originalApplicationVersion
        updateAccessStatus()
        return self.isSubscribed
    }
    
    public func restorePurchases() async throws {
        let customerInfo = try await Purchases.shared.restorePurchases()
        self.isSubscribed = customerInfo.entitlements["ai_slide_editor_vip"]?.isActive ?? false
        self.originalAppVersion = customerInfo.originalApplicationVersion
        updateAccessStatus()
    }
    
    public func updateAccessStatus() {
        let purchasedLegacyVersion = originalAppVersion.map { isVersionLegacy($0) } ?? false
        
        if isLegacyVersion || purchasedLegacyVersion || isSubscribed {
            self.hasFullAccess = true
        } else {
            self.hasFullAccess = false
        }
    }
    
    public func isVersionLegacy(_ versionOrBuild: String) -> Bool {
        // If it's a pure integer, it represents a build number (e.g. "65")
        if let buildNumber = Int(versionOrBuild) {
            return buildNumber <= legacyThresholdBuild
        }
        
        // Otherwise, parse it as standard dot-separated version string (e.g. "1.0.1")
        let components = versionOrBuild.split(separator: ".").compactMap { Int($0) }
        let target = [1, 0, 1]
        
        for i in 0..<max(components.count, target.count) {
            let compVal = i < components.count ? components[i] : 0
            let targetVal = i < target.count ? target[i] : 0
            if compVal < targetVal {
                return true
            } else if compVal > targetVal {
                return false
            }
        }
        return true
    }
}
