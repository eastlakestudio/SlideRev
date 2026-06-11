import SwiftUI
import RevenueCat

struct SubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var subManager = SubscriptionManager.shared
    @State private var isProcessing = false
    @State private var message: String? = nil
    
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            
            VStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .orange.opacity(0.3), radius: 8)
                
                Text("Unlock SlideRev Premium")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                
                Text("Convert flat PDFs, images, and citations into fully editable PPTX presentations.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            
            VStack(spacing: 12) {
                // Subscription Card
                VStack(spacing: 12) {
                    if subManager.isLoadingPackage {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 8)
                    } else if let package = subManager.yearlyPackage {
                        VStack(spacing: 6) {
                            Text(package.storeProduct.localizedTitle)
                                .font(.headline)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(package.storeProduct.localizedPriceString)
                                    .font(.system(size: 24, weight: .bold))
                                Text("/ year")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(package.storeProduct.localizedDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    } else {
                        VStack(spacing: 4) {
                            Text("Yearly Premium Membership")
                                .font(.headline)
                            Text("Auto-renewable. Cancel anytime.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                        .background(Color.accentColor.opacity(0.04))
                )
                
                if let msg = message {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                Button(action: purchase) {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .frame(height: 20)
                    } else {
                        Text(subManager.yearlyPackage.map { "Subscribe Yearly - \($0.storeProduct.localizedPriceString)" } ?? "Subscribe Yearly")
                            .font(.headline)
                    }
                }
                .disabled(isProcessing)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
                
                Button("Restore Purchases") {
                    restore()
                }
                .disabled(isProcessing)
                .buttonStyle(.link)
            }
            .padding(.horizontal, 32)
            
            // Standard Auto-Renewable Subscription Legal Terms
            VStack(spacing: 4) {
                Text("Subscription Terms:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period. You can manage and cancel your subscriptions in your App Store Account Settings after purchase.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .frame(maxWidth: 420)
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // EULA & Privacy Policy Footer
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    Text("Terms of Use (EULA)")
                        .font(.caption)
                        .underline()
                }
                
                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link(destination: URL(string: "https://eastlakestudio.github.io/SlideRev/privacy.html")!) {
                    Text("Privacy Policy")
                        .font(.caption)
                        .underline()
                }
            }
            .padding(.bottom, 24)
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await subManager.loadYearlyPackage()
        }
        .onAppear {
            Purchases.shared.trackCustomPaywallImpression(CustomPaywallImpressionParams(paywallId: "ai_slide_editor_paywall"))
        }
    }
    
    private func purchase() {
        isProcessing = true
        message = nil
        Task {
            do {
                let success = try await subManager.purchaseYearlySubscription()
                isProcessing = false
                if success {
                    dismiss()
                } else {
                    message = "Purchase was not completed."
                }
            } catch {
                isProcessing = false
                message = error.localizedDescription
            }
        }
    }
    
    private func restore() {
        isProcessing = true
        message = nil
        Task {
            do {
                try await subManager.restorePurchases()
                isProcessing = false
                if subManager.isSubscribed {
                    dismiss()
                } else {
                    message = "No active subscription found to restore."
                }
            } catch {
                isProcessing = false
                message = error.localizedDescription
            }
        }
    }
}
