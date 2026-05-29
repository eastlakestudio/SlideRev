import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:windows_app/core/subscription_service.dart';

class MockInAppPurchase implements InAppPurchase {
  bool isAvailableResult = true;
  ProductDetailsResponse productDetailsResponse = ProductDetailsResponse(productDetails: [], notFoundIDs: []);
  final StreamController<List<PurchaseDetails>> _purchaseStreamController = StreamController<List<PurchaseDetails>>.broadcast();

  @override
  Future<bool> isAvailable() async => isAvailableResult;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _purchaseStreamController.stream;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async {
    return productDetailsResponse;
  }

  void addPurchaseUpdate(List<PurchaseDetails> details) {
    _purchaseStreamController.add(details);
  }

  @override
  Future<bool> buyConsumable({required PurchaseParam purchaseParam, bool autoConsume = true}) async {
    return true;
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}

  @override
  Future<String> countryCode() async => 'US';

  @override
  T getPlatformAddition<T extends InAppPurchasePlatformAddition?>() {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SubscriptionService Tests', () {
    late SubscriptionService service;
    late MockInAppPurchase mockIap;

    setUp(() {
      mockIap = MockInAppPurchase();
      SubscriptionService.setMockInstance(mockIap);
      service = SubscriptionService();
      SharedPreferences.setMockInitialValues({});
    });

    test('Initial state is unsubscribed', () async {
      expect(service.isSubscribed, false);
      expect(service.isAvailable, false);
    });

    test('Loads cached subscription status correctly', () async {
      SharedPreferences.setMockInitialValues({'is_subscribed': true});
      await service.init();
      expect(service.isSubscribed, true);
    });

    test('Handles products not available', () async {
      mockIap.isAvailableResult = false;
      await service.init();
      expect(service.isAvailable, false);
      expect(service.errorMessage, isNotNull);
    });

    test('Initializes first launch date if not present', () async {
      await service.init();
      expect(service.isTrialActive, true);
      expect(service.trialDaysRemaining, 7);
      expect(service.hasProAccess, true);
    });

    test('Calculates trial days remaining correctly', () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 3));
      SharedPreferences.setMockInitialValues({'first_launch_date': pastDate.toIso8601String()});
      await service.init();
      expect(service.isTrialActive, true);
      expect(service.trialDaysRemaining, 4);
      expect(service.hasProAccess, true);
    });

    test('Expired trial revokes pro access if not subscribed', () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 8));
      SharedPreferences.setMockInitialValues({'first_launch_date': pastDate.toIso8601String()});
      await service.init();
      expect(service.isTrialActive, false);
      expect(service.trialDaysRemaining, 0);
      expect(service.hasProAccess, false);
    });

    test('Subscription overrides expired trial', () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 8));
      SharedPreferences.setMockInitialValues({
        'first_launch_date': pastDate.toIso8601String(),
        'is_subscribed': true,
      });
      await service.init();
      expect(service.isTrialActive, false);
      expect(service.trialDaysRemaining, 0);
      expect(service.isSubscribed, true);
      expect(service.hasProAccess, true);
    });
  });
}
