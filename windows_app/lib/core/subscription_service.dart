import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger.dart';

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._internal();

  factory SubscriptionService() {
    return _instance;
  }

  @visibleForTesting
  static void setMockInstance(InAppPurchase mockInAppPurchase) {
    _instance._inAppPurchaseMock = mockInAppPurchase;
  }

  SubscriptionService._internal();

  InAppPurchase? _inAppPurchaseMock;
  InAppPurchase get _inAppPurchase => _inAppPurchaseMock ?? InAppPurchase.instance;
  
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  bool _isAvailable = false;
  bool _isSubscribed = false;
  bool _isPurchasing = false;
  DateTime? _firstLaunchDate;
  
  List<ProductDetails> _products = [];
  String? _errorMessage;

  static const String _yearlySubscriptionId = 'com.eastlakestudio.sliderev.yearly';
  static const String _prefIsSubscribedKey = 'is_subscribed';
  static const String _prefFirstLaunchKey = 'first_launch_date';

  bool get isSubscribed => _isSubscribed;
  
  // Trial logic
  bool get isTrialActive {
    if (_firstLaunchDate == null) return false;
    final now = DateTime.now();
    final difference = now.difference(_firstLaunchDate!);
    return difference.inDays < 7;
  }

  int get trialDaysRemaining {
    if (_firstLaunchDate == null) return 0;
    final now = DateTime.now();
    final difference = now.difference(_firstLaunchDate!);
    final remaining = 7 - difference.inDays;
    return remaining > 0 ? remaining : 0;
  }

  bool get hasProAccess => _isSubscribed || isTrialActive;

  bool get isAvailable => _isAvailable;
  bool get isPurchasing => _isPurchasing;
  List<ProductDetails> get products => _products;
  String? get errorMessage => _errorMessage;

  Future<void> init() async {
    _isAvailable = await _inAppPurchase.isAvailable();
    if (!_isAvailable) {
      AppLogger.w('Subscription', 'In-App Purchases are not available.');
      _errorMessage = 'In-App Purchases are not available on this device.';
      notifyListeners();
      return;
    }

    // Load cached status immediately
    await _loadCachedSubscriptionStatus();

    final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      AppLogger.e('Subscription', 'Purchase stream error: $error');
    });

    await loadProducts();
  }

  Future<void> loadProducts() async {
    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails({_yearlySubscriptionId});
    
    if (response.notFoundIDs.isNotEmpty) {
      AppLogger.w('Subscription', 'Products not found: ${response.notFoundIDs}');
    }

    if (response.error != null) {
      AppLogger.e('Subscription', 'Error loading products: ${response.error!.message}');
      _errorMessage = response.error!.message;
    }

    _products = response.productDetails;
    notifyListeners();
  }

  Future<void> _loadCachedSubscriptionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _isSubscribed = prefs.getBool(_prefIsSubscribedKey) ?? false;
    
    // Check first launch date for trial
    final firstLaunchStr = prefs.getString(_prefFirstLaunchKey);
    if (firstLaunchStr == null) {
      _firstLaunchDate = DateTime.now();
      await prefs.setString(_prefFirstLaunchKey, _firstLaunchDate!.toIso8601String());
    } else {
      _firstLaunchDate = DateTime.tryParse(firstLaunchStr);
    }
    
    notifyListeners();
  }

  Future<void> _setSubscribed(bool status) async {
    _isSubscribed = status;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefIsSubscribedKey, status);
    notifyListeners();
  }

  void buyYearlySubscription() {
    if (_products.isEmpty) {
      AppLogger.w('Subscription', 'No products available to buy.');
      return;
    }
    _isPurchasing = true;
    notifyListeners();
    
    final ProductDetails productDetails = _products.firstWhere((element) => element.id == _yearlySubscriptionId);
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
    
    // Using buyNonConsumable since subscriptions are non-consumable for standard integration without server verification
    _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  void restorePurchases() {
    _isPurchasing = true;
    notifyListeners();
    _inAppPurchase.restorePurchases();
  }

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _isPurchasing = true;
        notifyListeners();
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          AppLogger.e('Subscription', 'Purchase error: ${purchaseDetails.error}');
          _errorMessage = purchaseDetails.error?.message;
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          bool valid = await _verifyPurchase(purchaseDetails);
          if (valid) {
            await _setSubscribed(true);
            AppLogger.d('Subscription', 'Successfully purchased/restored subscription.');
          } else {
            AppLogger.w('Subscription', 'Purchase verification failed.');
          }
        }
        
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
        
        _isPurchasing = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    // In a real app, you would send purchaseDetails.verificationData to your server.
    // For this implementation, we assume if it got this far from Apple, it's valid locally.
    return true;
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
