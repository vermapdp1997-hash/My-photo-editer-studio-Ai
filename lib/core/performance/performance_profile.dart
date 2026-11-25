import 'dart:io';

enum PerformanceMode {
  auto,
  low,
  balanced,
  high,
}

class PerformanceConfig {
  final PerformanceMode resolvedMode;
  final int previewMaxDimension;
  final int aiInputMaxDimension;
  final int interpreterThreads;
  final bool allowGpuDelegate;

  const PerformanceConfig({
    required this.resolvedMode,
    required this.previewMaxDimension,
    required this.aiInputMaxDimension,
    required this.interpreterThreads,
    required this.allowGpuDelegate,
  });

  String get label {
    switch (resolvedMode) {
      case PerformanceMode.low:
        return 'Low Memory Mode';
      case PerformanceMode.balanced:
        return 'Balanced Mode';
      case PerformanceMode.high:
        return 'High Performance Mode';
      case PerformanceMode.auto:
        return 'Auto';
    }
  }

  static PerformanceConfig resolve(PerformanceMode requested) {
    final PerformanceMode effective;
    if (requested != PerformanceMode.auto) {
      effective = requested;
    } else {
      final cores = Platform.numberOfProcessors;
      if (cores <= 4) {
        effective = PerformanceMode.low;
      } else if (cores <= 6) {
        effective = PerformanceMode.balanced;
      } else {
        effective = PerformanceMode.high;
      }
    }

    switch (effective) {
      case PerformanceMode.low:
        return const PerformanceConfig(
          resolvedMode: PerformanceMode.low,
          previewMaxDimension: 720,
          aiInputMaxDimension: 512,
          interpreterThreads: 2,
          allowGpuDelegate: false,
        );
      case PerformanceMode.balanced:
        return const PerformanceConfig(
          resolvedMode: PerformanceMode.balanced,
          previewMaxDimension: 1080,
          aiInputMaxDimension: 768,
          interpreterThreads: 4,
          allowGpuDelegate: false,
        );
      case PerformanceMode.high:
      case PerformanceMode.auto:
        return const PerformanceConfig(
          resolvedMode: PerformanceMode.high,
          previewMaxDimension: 1440,
          aiInputMaxDimension: 1024,
          interpreterThreads: 4,
          allowGpuDelegate: true,
        );
    }
  }
}
