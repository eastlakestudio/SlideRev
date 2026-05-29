import SwiftUI
import RevenueCat

struct SubscriptionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var subManager = SubscriptionManager.shared
    @State private var isProcessing = false
    @State private var message: String? = nil
    
    var body: some View {
        VStack(spacing: 24) {
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
                    .font(.system(size: 60))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .orange.opacity(0.3), radius: 10)
                
                Text("Unlock SlideRev Premium")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Convert flat PDFs, images, and citations into fully editable PPTX presentations.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            
            VStack(spacing: 16) {
                // Subscription Card
                VStack(spacing: 8) {
                    Text("Yearly Premium Membership")
                        .font(.headline)
                    Text("Auto-renewable. Cancel anytime.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Standard EULA applies")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.05))
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
                        Text("Subscribe Yearly")
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
                
                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    Text("Privacy Policy")
                        .font(.caption)
                        .underline()
                }
            }
            .padding(.bottom, 24)
        }
        .frame(width: 500, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
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
