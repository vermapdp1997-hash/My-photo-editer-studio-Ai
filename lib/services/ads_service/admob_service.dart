import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdMobService {
  AdMobService._();
  static final AdMobService instance = AdMobService._();

  static String get bannerUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-3940256099942544/2934735716';

  static String get interstitialUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-3940256099942544/4411468910';

  static String get rewardedUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-3940256099942544/1712485313';

  final ValueNotifier<bool> initializedNotifier = ValueNotifier<bool>(false);
  bool get isInitialized => initializedNotifier.value;

  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  DateTime? _lastInterstitialShownAt;

  Future<void> initialize() async {
    if (initializedNotifier.value) return;
    try {
      await MobileAds.instance.initialize();
      initializedNotifier.value = true;
      preloadInterstitial();
      preloadRewarded();
    } catch (_) {
      // App works 100% offline even when Ads SDK cannot initialize
    }
  }

  void preloadInterstitial() {
    if (!isInitialized) return;
    try {
      InterstitialAd.load(
        adUnitId: interstitialUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => _interstitialAd = ad,
          onAdFailedToLoad: (_) => _interstitialAd = null,
        ),
      );
    } catch (_) {}
  }

  void preloadRewarded() {
    if (!isInitialized) return;
    try {
      RewardedAd.load(
        adUnitId: rewardedUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) => _rewardedAd = ad,
          onAdFailedToLoad: (_) => _rewardedAd = null,
        ),
      );
    } catch (_) {}
  }

  Future<void> showPostExportInterstitialIfReady() async {
    final ad = _interstitialAd;
    if (ad == null) {
      preloadInterstitial();
      return;
    }

    final now = DateTime.now();
    if (_lastInterstitialShownAt != null &&
        now.difference(_lastInterstitialShownAt!) < const Duration(seconds: 90)) {
      return;
    }

    _lastInterstitialShownAt = now;
    _interstitialAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        preloadInterstitial();
      },
    );
    await ad.show();
  }

  Future<bool> showOptionalRewardedAd() async {
    final ad = _rewardedAd;
    if (ad == null) {
      preloadRewarded();
      return false;
    }
    bool rewarded = false;
    _rewardedAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        preloadRewarded();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        preloadRewarded();
      },
    );
    await ad.show(
      onUserEarnedReward: (_, _) {
        rewarded = true;
      },
    );
    return rewarded;
  }
}

class SafeBannerAdWidget extends StatefulWidget {
  const SafeBannerAdWidget({super.key});

  @override
  State<SafeBannerAdWidget> createState() => _SafeBannerAdWidgetState();
}

class _SafeBannerAdWidgetState extends State<SafeBannerAdWidget> {
  BannerAd? _bannerAd;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (AdMobService.instance.isInitialized) {
      _loadBanner();
    } else {
      AdMobService.instance.initializedNotifier.addListener(_onAdMobReady);
    }
  }

  void _onAdMobReady() {
    if (AdMobService.instance.isInitialized && mounted && _bannerAd == null) {
      AdMobService.instance.initializedNotifier.removeListener(_onAdMobReady);
      _loadBanner();
    }
  }

  void _loadBanner() {
    try {
      final ad = BannerAd(
        adUnitId: AdMobService.bannerUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted) setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, _) {
            ad.dispose();
            if (mounted) {
              setState(() {
                _bannerAd = null;
                _loaded = false;
              });
            }
          },
        ),
      );
      _bannerAd = ad;
      ad.load();
    } catch (_) {}
  }

  @override
  void dispose() {
    AdMobService.instance.initializedNotifier.removeListener(_onAdMobReady);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _bannerAd == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
