import 'package:flutter/material.dart';
import '../core/subscription_service.dart';

class PaywallDialog extends StatefulWidget {
  const PaywallDialog({super.key});

  static void show(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Paywall",
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const Center(child: PaywallDialog());
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            )),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<PaywallDialog> createState() => _PaywallDialogState();
}

class _PaywallDialogState extends State<PaywallDialog> {
  late SubscriptionService _subscriptionService;

  @override
  void initState() {
    super.initState();
    _subscriptionService = SubscriptionService();
    _subscriptionService.addListener(_onSubscriptionChanged);
    // 强制刷新一次产品列表
    if (_subscriptionService.products.isEmpty) {
      _subscriptionService.loadProducts();
    }
  }

  @override
  void dispose() {
    _subscriptionService.removeListener(_onSubscriptionChanged);
    super.dispose();
  }

  void _onSubscriptionChanged() {
    if (mounted) {
      setState(() {});
      if (_subscriptionService.isSubscribed) {
        Navigator.of(context).pop(true); // Close dialog on success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for subscribing!'), backgroundColor: Colors.green),
        );
      } else if (_subscriptionService.errorMessage != null && !_subscriptionService.isPurchasing) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_subscriptionService.errorMessage!), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 40,
              offset: const Offset(0, 20),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            const Icon(Icons.workspace_premium, size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            const Text(
              "SlideRev Pro",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_subscriptionService.isTrialActive && !_subscriptionService.isSubscribed)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Your free trial is active (${_subscriptionService.trialDaysRemaining} days remaining).",
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                ),
              )
            else if (!_subscriptionService.isSubscribed && _subscriptionService.trialDaysRemaining == 0)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Your free trial has expired.",
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            Text(
              "Unlock unlimited exports and AI reconstruction capabilities.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 32),
            _buildFeatureList(),
            const SizedBox(height: 32),
            if (_subscriptionService.isPurchasing)
              const CircularProgressIndicator()
            else ...[
              _buildSubscribeButton(theme),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _subscriptionService.restorePurchases();
                },
                child: const Text("Restore Purchases", style: TextStyle(color: Colors.grey)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureList() {
    return Column(
      children: const [
        _FeatureItem("Unlimited PDF to PPTX Conversions"),
        SizedBox(height: 12),
        _FeatureItem("Advanced AI Inpainting & OCR"),
        SizedBox(height: 12),
        _FeatureItem("No Watermarks"),
        SizedBox(height: 12),
        _FeatureItem("Priority Support"),
      ],
    );
  }

  Widget _buildSubscribeButton(ThemeData theme) {
    String priceString = "Loading...";
    if (_subscriptionService.products.isNotEmpty) {
      priceString = _subscriptionService.products.first.price;
    } else if (!_subscriptionService.isAvailable) {
      priceString = "Unavailable";
    }

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF007AFF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        onPressed: _subscriptionService.products.isNotEmpty
            ? () {
                _subscriptionService.buyYearlySubscription();
              }
            : null,
        child: Text(
          "Subscribe Yearly for $priceString",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final String text;
  const _FeatureItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 20),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
