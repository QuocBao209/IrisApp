import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Dart port of lung-ROI iris unwrap (Android-safe, no Python).
class IrisSegmenterDart {
  IrisSegmenterDart({this.outputSize = 400});

  final int outputSize;

  /// Returns (full iris crop JPEG bytes, lung ROI BMP bytes).
  ({Uint8List irisJpeg, Uint8List roiBmp}) process(
    Uint8List imageBytes, {
    required String eyeSide,
  }) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw Exception('Không đọc được ảnh đầu vào.');
    }

    final src = img.bakeOrientation(decoded);
    final gray = img.grayscale(src);
    final enhanced = _enhanceGray(gray);

    final pupil = _detectPupil(enhanced);
    var irisR = (_detectIrisRadius(enhanced, pupil) * 1.03).round();
    final rInner = math.max(2, (pupil.r * 1.10).round());
    // Đảm bảo ROI lấy trong vòng mống mắt, không nhảy ra nền.
    if (irisR <= rInner + 4) {
      irisR = (pupil.r * 2.8).round().clamp(rInner + 8, math.min(src.width, src.height) ~/ 2);
    }

    debugPrint(
      '[Segmentation] pupil=(${pupil.x},${pupil.y} r=${pupil.r}) '
      'rInner=$rInner irisR=$irisR eye=$eyeSide',
    );

    final roi = _unwrapLungRoi(
      src,
      pupil.x,
      pupil.y,
      rInner,
      irisR,
      eyeSide,
    );

    final irisCrop = _cropIris(src, pupil.x, pupil.y, irisR);

    // Quality 100 — giữ tối đa chi tiết sau cắt/unwrap
    final irisJpeg = Uint8List.fromList(img.encodeJpg(irisCrop, quality: 100));
    final roiBmp = Uint8List.fromList(img.encodeJpg(roi, quality: 100));
    return (irisJpeg: irisJpeg, roiBmp: roiBmp);
  }

  img.Image _enhanceGray(img.Image gray) {
    final blurred = img.gaussianBlur(gray, radius: 2);
    final out = img.Image.from(blurred);
    int minV = 255;
    int maxV = 0;
    for (final p in out) {
      final v = p.r.toInt();
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final range = math.max(1, maxV - minV);
    for (final p in out) {
      final v = (((p.r - minV) * 255) / range).round().clamp(0, 255);
      p.r = v;
      p.g = v;
      p.b = v;
    }
    return out;
  }

  ({int x, int y, int r}) _detectPupil(img.Image gray) {
    final w = gray.width;
    final h = gray.height;
    final margin = (w * 0.12).round();
    final x0 = margin;
    final y0 = margin;
    final x1 = w - margin;
    final y1 = h - margin;
    final minDim = math.min(w, h);
    final maxPupilR = (minDim * 0.22).round();
    final minPupilR = math.max(4, (minDim * 0.02).round());

    final samples = <int>[];
    for (int y = y0; y < y1; y += 2) {
      for (int x = x0; x < x1; x += 2) {
        samples.add(gray.getPixel(x, y).r.toInt());
      }
    }
    samples.sort();
    if (samples.isEmpty) {
      return (x: w ~/ 2, y: h ~/ 2, r: minDim ~/ 10);
    }

    // Thử ngưỡng chặt dần (2% → 5% → 8%) để chỉ lấy đồng tử, không lấy cả iris.
    for (final pct in [0.02, 0.035, 0.05, 0.08]) {
      final thr = samples[(samples.length * pct).floor().clamp(0, samples.length - 1)];
      final candidate = _bestDarkBlob(
        gray,
        x0: x0,
        y0: y0,
        x1: x1,
        y1: y1,
        thr: thr,
        minPupilR: minPupilR,
        maxPupilR: maxPupilR,
      );
      if (candidate != null) return candidate;
    }

    return (x: w ~/ 2, y: h ~/ 2, r: minDim ~/ 10);
  }

  /// Tìm blob tối gần tâm nhất, đủ tròn, bán kính hợp lý (giống contour+circularity Python).
  ({int x, int y, int r})? _bestDarkBlob(
    img.Image gray, {
    required int x0,
    required int y0,
    required int x1,
    required int y1,
    required int thr,
    required int minPupilR,
    required int maxPupilR,
  }) {
    final w = gray.width;
    final h = gray.height;
    final rw = x1 - x0;
    final rh = y1 - y0;
    if (rw <= 0 || rh <= 0) return null;

    final visited = List<bool>.filled(rw * rh, false);
    final imgCx = w / 2.0;
    final imgCy = h / 2.0;

    double bestScore = -1;
    ({int x, int y, int r})? best;

    for (int y = y0; y < y1; y++) {
      for (int x = x0; x < x1; x++) {
        final li = (y - y0) * rw + (x - x0);
        if (visited[li]) continue;
        if (gray.getPixel(x, y).r.toInt() > thr) {
          visited[li] = true;
          continue;
        }

        // Flood-fill component
        final qx = <int>[x];
        final qy = <int>[y];
        visited[li] = true;
        double sumX = 0, sumY = 0;
        var count = 0;
        var minX = x, maxX = x, minY = y, maxY = y;

        while (qx.isNotEmpty) {
          final cx = qx.removeLast();
          final cy = qy.removeLast();
          sumX += cx;
          sumY += cy;
          count++;
          if (cx < minX) minX = cx;
          if (cx > maxX) maxX = cx;
          if (cy < minY) minY = cy;
          if (cy > maxY) maxY = cy;

          for (final d in const [
            [-1, 0],
            [1, 0],
            [0, -1],
            [0, 1],
          ]) {
            final nx = cx + d[0];
            final ny = cy + d[1];
            if (nx < x0 || ny < y0 || nx >= x1 || ny >= y1) continue;
            final ni = (ny - y0) * rw + (nx - x0);
            if (visited[ni]) continue;
            visited[ni] = true;
            if (gray.getPixel(nx, ny).r.toInt() <= thr) {
              qx.add(nx);
              qy.add(ny);
            }
          }
        }

        if (count < 40) continue;

        final cx = sumX / count;
        final cy = sumY / count;
        final rBox = (((maxX - minX) + (maxY - minY)) / 4.0);
        if (rBox < minPupilR || rBox > maxPupilR) continue;

        // Circularity ≈ area / (π r²); bbox radius gần enclosing circle.
        final circularity = count / (math.pi * rBox * rBox + 1e-6);
        if (circularity < 0.45) continue;

        final dist = math.sqrt(
          (cx - imgCx) * (cx - imgCx) + (cy - imgCy) * (cy - imgCy),
        );
        // Ưu tiên blob tròn + gần tâm ảnh.
        final score = circularity * 2.0 - (dist / minDimSafe(w, h));
        if (score > bestScore) {
          bestScore = score;
          best = (x: cx.round(), y: cy.round(), r: math.max(minPupilR, rBox.round()));
        }
      }
    }
    return best;
  }

  double minDimSafe(int w, int h) => math.max(1.0, math.min(w, h).toDouble());

  int _detectIrisRadius(img.Image gray, ({int x, int y, int r}) pupil) {
    final w = gray.width;
    final h = gray.height;
    final maxR = (pupil.r * 4.0).round();
    final rStart = (pupil.r * 1.2).round();
    final radii = <double>[];

    for (int i = 0; i < 360; i += 2) {
      final theta = i * math.pi / 180.0;
      final dx = math.cos(theta);
      final dy = math.sin(theta);
      int? prev;
      var maxGrad = 0;
      var bestR = -1;

      for (int r = rStart; r < maxR; r++) {
        final x = (pupil.x + r * dx).round();
        final y = (pupil.y + r * dy).round();
        if (x < 0 || y < 0 || x >= w || y >= h) break;
        final val = gray.getPixel(x, y).r.toInt();
        if (prev != null) {
          final grad = val - prev;
          if (grad > maxGrad) {
            maxGrad = grad;
            bestR = r;
          }
        }
        prev = val;
      }

      // Prefer horizontal sectors (less eyelid noise).
      final use = i < 50 || i > 310 || (i > 130 && i < 230);
      if (bestR > 0 && use) {
        radii.add(bestR.toDouble());
      }
    }

    if (radii.length < 6) {
      return (pupil.r * 2.5).round();
    }
    radii.sort();
    return radii[radii.length ~/ 2].round();
  }

  img.Image _unwrapLungRoi(
    img.Image src,
    int px,
    int py,
    int rInner,
    int rOuter,
    String eyeSide,
  ) {
    final startAngle = eyeSide == 'right' ? 150.0 : -30.0;
    final endAngle = eyeSide == 'right' ? 210.0 : 30.0;
    const w = 256;
    const h = 128;
    final out = img.Image(width: w, height: h);

    for (int yi = 0; yi < h; yi++) {
      final r = rInner + (rOuter - rInner) * (yi / (h - 1));
      for (int xi = 0; xi < w; xi++) {
        final t = startAngle + (endAngle - startAngle) * (xi / (w - 1));
        final rad = t * math.pi / 180.0;
        final x = px + r * math.cos(rad);
        final y = py + r * math.sin(rad);
        final sampled = _sampleBilinear(src, x, y);
        out.setPixelRgba(xi, yi, sampled.$1, sampled.$2, sampled.$3, 255);
      }
    }
    return out;
  }

  /// Lấy pixel nội suy bilinear — sắc hơn nearest-neighbor khi unwrap.
  (int, int, int) _sampleBilinear(img.Image src, double x, double y) {
    if (x < 0 || y < 0 || x >= src.width - 1 || y >= src.height - 1) {
      final ix = x.round().clamp(0, src.width - 1);
      final iy = y.round().clamp(0, src.height - 1);
      if (x < 0 || y < 0 || x >= src.width || y >= src.height) {
        return (0, 0, 0);
      }
      final p = src.getPixel(ix, iy);
      return (p.r.toInt(), p.g.toInt(), p.b.toInt());
    }

    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = x0 + 1;
    final y1 = y0 + 1;
    final fx = x - x0;
    final fy = y - y0;

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    int mix(num a, num b, num c, num d) {
      final top = a * (1 - fx) + b * fx;
      final bot = c * (1 - fx) + d * fx;
      return (top * (1 - fy) + bot * fy).round().clamp(0, 255);
    }

    return (
      mix(p00.r, p10.r, p01.r, p11.r),
      mix(p00.g, p10.g, p01.g, p11.g),
      mix(p00.b, p10.b, p01.b, p11.b),
    );
  }

  img.Image _cropIris(img.Image src, int px, int py, int irisR) {
    final x0 = math.max(0, px - irisR);
    final y0 = math.max(0, py - irisR);
    final x1 = math.min(src.width, px + irisR);
    final y1 = math.min(src.height, py + irisR);
    final crop = img.copyCrop(
      src,
      x: x0,
      y: y0,
      width: math.max(1, x1 - x0),
      height: math.max(1, y1 - y0),
    );
    return img.copyResize(
      crop,
      width: outputSize,
      height: outputSize,
      interpolation: img.Interpolation.cubic,
    );
  }
}
