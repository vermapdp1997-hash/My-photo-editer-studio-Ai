import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../data/models/edit_state.dart';

class TfliteTensorUtils {
  TfliteTensorUtils._();

  static img.Image rasterizeMask(
    int width,
    int height,
    List<RetouchStroke> strokes,
  ) {
    final mask = img.Image(width: width, height: height, numChannels: 4);
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));
    for (final s in strokes) {
      final r = math.max(3, (s.brushSize * math.min(width, height)).round());
      final r2 = r * r;
      for (final pt in s.normalizedPoints) {
        final cx = (pt.dx * width).round();
        final cy = (pt.dy * height).round();
        for (int dy = -r; dy <= r; dy++) {
          final py = cy + dy;
          if (py < 0 || py >= height) continue;
          for (int dx = -r; dx <= r; dx++) {
            final px = cx + dx;
            if (px >= 0 && px < width && dx * dx + dy * dy <= r2) {
              mask.setPixelRgba(px, py, 255, 255, 255, 255);
            }
          }
        }
      }
    }
    return mask;
  }

  static ByteBuffer imageToTensorBuffer(
    img.Image image,
    Tensor tensor, {
    required bool isNchw,
  }) {
    final h = image.height;
    final w = image.width;
    final count = h * w * 3;
    final scale = tensor.params.scale == 0 ? 1.0 : tensor.params.scale;
    final zp = tensor.params.zeroPoint;

    if (tensor.type == TensorType.uint8) {
      final list = Uint8List(count);
      int i = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          if (!isNchw) {
            list[i++] = p.r.round().clamp(0, 255);
            list[i++] = p.g.round().clamp(0, 255);
            list[i++] = p.b.round().clamp(0, 255);
          } else {
            final hw = h * w;
            final pos = y * w + x;
            list[pos] = p.r.round().clamp(0, 255);
            list[hw + pos] = p.g.round().clamp(0, 255);
            list[2 * hw + pos] = p.b.round().clamp(0, 255);
          }
        }
      }
      return list.buffer;
    } else if (tensor.type == TensorType.int8) {
      final list = Int8List(count);
      int i = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = image.getPixel(x, y);
          list[i++] = (((p.r / 255.0) / scale) + zp).round().clamp(-128, 127);
          list[i++] = (((p.g / 255.0) / scale) + zp).round().clamp(-128, 127);
          list[i++] = (((p.b / 255.0) / scale) + zp).round().clamp(-128, 127);
        }
      }
      return list.buffer;
    }

    final list = Float32List(count);
    int i = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        if (!isNchw) {
          list[i++] = p.r / 255.0;
          list[i++] = p.g / 255.0;
          list[i++] = p.b / 255.0;
        } else {
          final hw = h * w;
          final pos = y * w + x;
          list[pos] = p.r / 255.0;
          list[hw + pos] = p.g / 255.0;
          list[2 * hw + pos] = p.b / 255.0;
        }
      }
    }
    return list.buffer;
  }

  static ByteBuffer maskToTensorBuffer(img.Image mask, Tensor tensor) {
    final h = mask.height;
    final w = mask.width;
    if (tensor.type == TensorType.uint8) {
      final list = Uint8List(h * w);
      int i = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          list[i++] = mask.getPixel(x, y).r.round().clamp(0, 255);
        }
      }
      return list.buffer;
    }
    final list = Float32List(h * w);
    int i = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        list[i++] = mask.getPixel(x, y).r > 127 ? 1.0 : 0.0;
      }
    }
    return list.buffer;
  }

  static ByteBuffer allocateOutputBuffer(Tensor tensor) {
    final n = tensor.shape.fold<int>(1, (a, b) => a * b);
    if (tensor.type == TensorType.uint8) return Uint8List(n).buffer;
    if (tensor.type == TensorType.int8) return Int8List(n).buffer;
    return Float32List(n).buffer;
  }

  static img.Image tensorBufferToImage(
    ByteBuffer buffer,
    Tensor tensor, {
    required int width,
    required int height,
    required bool isNchw,
  }) {
    final out = img.Image(width: width, height: height, numChannels: 4);
    final scale = tensor.params.scale == 0 ? 1.0 : tensor.params.scale;
    final zp = tensor.params.zeroPoint;
    double read(int idx) {
      if (tensor.type == TensorType.uint8) {
        return buffer.asUint8List()[idx].toDouble();
      } else if (tensor.type == TensorType.int8) {
        return (buffer.asInt8List()[idx] - zp) * scale * 255.0;
      }
      final v = buffer.asFloat32List()[idx];
      return v <= 1.5 ? v * 255.0 : v;
    }

    final hw = width * height;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pos = y * width + x;
        final r = read(isNchw ? pos : pos * 3);
        final g = read(isNchw ? hw + pos : pos * 3 + 1);
        final b = read(isNchw ? 2 * hw + pos : pos * 3 + 2);
        out.setPixelRgba(
          x,
          y,
          r.round().clamp(0, 255),
          g.round().clamp(0, 255),
          b.round().clamp(0, 255),
          255,
        );
      }
    }
    return out;
  }
}
