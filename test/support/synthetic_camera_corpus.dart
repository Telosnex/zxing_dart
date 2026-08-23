import 'dart:math' as math;
import 'dart:typed_data';

import 'package:zxing_dart/zxing_dart.dart';

/// Version the recipes—not generated pixels—so a failure can always be
/// reproduced as `v1/<case id>` on every backend.
const syntheticCorpusVersion = 1;
const _frameWidth = 360;
const _frameHeight = 280;
const _quietModules = 4;

const syntheticPairingPayload =
    'tnx2:'
    'VGhpc0lzQU5vbmNlMTIzNDU2Nzg5MGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6'
    'QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo0OTg3NjU0MzIxMA';

enum SyntheticExpectation { decodes, notFound }

final class SyntheticFrame {
  const SyntheticFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.pixelFormat,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int rowStride;
  final BarcodePixelFormat pixelFormat;
}

final class SyntheticCameraCase {
  const SyntheticCameraCase({
    required this.id,
    required this.tags,
    required this.frame,
    required this.expectation,
    required this.expectedText,
    required this.symbolCenterX,
    required this.symbolCenterY,
  });

  /// Stable repro ID, including the corpus recipe version.
  final String id;
  final Set<String> tags;
  final SyntheticFrame frame;
  final SyntheticExpectation expectation;
  final String? expectedText;
  final double symbolCenterX;
  final double symbolCenterY;
}

final class _Point {
  const _Point(this.x, this.y);
  final double x;
  final double y;

  _Point operator +(_Point other) => _Point(x + other.x, y + other.y);
  _Point operator -(_Point other) => _Point(x - other.x, y - other.y);
  _Point scale(double value) => _Point(x * value, y * value);
}

final class _Glare {
  const _Glare(this.x, this.y, this.radius, this.strength);
  final double x;
  final double y;
  final double radius;
  final double strength;
}

final class _Occlusion {
  const _Occlusion(this.x, this.y, this.width, this.height, this.luminance);
  final int x;
  final int y;
  final int width;
  final int height;
  final int luminance;
}

final class _Recipe {
  const _Recipe({
    required this.id,
    required this.tags,
    required this.quad,
    this.black = 18,
    this.white = 238,
    this.background = 225,
    this.gradientX = 0,
    this.gradientY = 0,
    this.vignette = 0,
    this.noise = 0,
    this.blurRadius = 0,
    this.motionBlur = 0,
    this.moireAmplitude = 0,
    this.moirePeriod = 7,
    this.glare,
    this.occlusion,
    this.pixelFormat = BarcodePixelFormat.luminance8,
    this.rowPadding = 13,
    this.seed = 1,
    this.expectation = SyntheticExpectation.decodes,
  });

  final String id;
  final Set<String> tags;
  final List<_Point> quad;
  final int black;
  final int white;
  final int background;
  final int gradientX;
  final int gradientY;
  final int vignette;
  final int noise;
  final int blurRadius;
  final int motionBlur;
  final int moireAmplitude;
  final int moirePeriod;
  final _Glare? glare;
  final _Occlusion? occlusion;
  final BarcodePixelFormat pixelFormat;
  final int rowPadding;
  final int seed;
  final SyntheticExpectation expectation;
}

/// Builds a deterministic camera-like torture corpus from a module matrix.
///
/// No image codec, canvas, random global state, or checked-in raster goldens are
/// involved. The renderer inverse-projects the ideal symbol through a homography
/// and then applies sensor/optics defects in luminance space. Every recipe is
/// stable and independently reproducible by ID.
List<SyntheticCameraCase> buildSyntheticCameraCorpus(
  BarcodeMatrix matrix, {
  String expectedText = syntheticPairingPayload,
}) => [
  for (final recipe in _recipes()) _renderRecipe(matrix, expectedText, recipe),
];

/// Smaller hard-transform profile for alternate encoders/ECC configurations.
/// It omits redundant angles to keep browser parity fast.
List<SyntheticCameraCase> buildHardTransformCorpus(
  BarcodeMatrix matrix, {
  required String expectedText,
}) {
  const selected = {
    'clean',
    'rotate-33',
    'rotate-137',
    'perspective-left',
    'perspective-oblique',
    'distance-165',
    'blur-1',
    'low-contrast-noise',
    'glare-edge',
    'compound-3',
  };
  return [
    for (final recipe in _recipes())
      if (selected.contains(recipe.id))
        _renderRecipe(matrix, expectedText, recipe),
  ];
}

SyntheticCameraCase _renderRecipe(
  BarcodeMatrix matrix,
  String expectedText,
  _Recipe recipe,
) {
  var luminance = _projectSymbol(matrix, recipe);
  if (recipe.blurRadius > 0) {
    luminance = _boxBlur(
      luminance,
      _frameWidth,
      _frameHeight,
      recipe.blurRadius,
    );
  }
  if (recipe.motionBlur > 0) {
    luminance = _horizontalMotionBlur(
      luminance,
      _frameWidth,
      _frameHeight,
      recipe.motionBlur,
    );
  }
  if (recipe.occlusion case final occlusion?) {
    _fillRect(luminance, _frameWidth, _frameHeight, occlusion);
  }
  final frame = _packFrame(luminance, recipe);
  final center = recipe.quad
      .fold(const _Point(0, 0), (sum, point) => sum + point)
      .scale(0.25);
  return SyntheticCameraCase(
    id: 'v$syntheticCorpusVersion/${recipe.id}',
    tags: Set.unmodifiable(recipe.tags),
    frame: frame,
    expectation: recipe.expectation,
    expectedText: recipe.expectation == SyntheticExpectation.decodes
        ? expectedText
        : null,
    symbolCenterX: center.x,
    symbolCenterY: center.y,
  );
}

List<_Recipe> _recipes() {
  final recipes = <_Recipe>[
    _Recipe(
      id: 'clean',
      tags: const {'baseline'},
      quad: _rotatedQuad(180, 140, 220, 0),
    ),
    for (final angle in const [15, 33, 61, 92, 137, 180, 227, 270, 319])
      _Recipe(
        id: 'rotate-$angle',
        tags: const {'rotation'},
        quad: _rotatedQuad(180, 140, 230, angle.toDouble()),
        seed: angle,
      ),
    const _Recipe(
      id: 'perspective-left',
      tags: {'perspective'},
      quad: [
        _Point(75, 40),
        _Point(290, 50),
        _Point(285, 245),
        _Point(65, 235),
      ],
    ),
    const _Recipe(
      id: 'perspective-right',
      tags: {'perspective'},
      quad: [
        _Point(70, 50),
        _Point(290, 40),
        _Point(295, 235),
        _Point(80, 245),
      ],
    ),
    const _Recipe(
      id: 'perspective-oblique',
      tags: {'perspective', 'rotation'},
      quad: [
        _Point(105, 30),
        _Point(310, 113),
        _Point(241, 257),
        _Point(50, 185),
      ],
    ),
    for (final size in const [205, 185, 165])
      _Recipe(
        id: 'distance-$size',
        tags: const {'distance', 'resolution'},
        quad: _rotatedQuad(180, 140, size.toDouble(), 7),
        noise: 0,
        seed: size,
      ),
    _Recipe(
      id: 'blur-1',
      tags: const {'defocus'},
      quad: _rotatedQuad(180, 140, 220, -8),
      blurRadius: 1,
    ),
    _Recipe(
      id: 'blur-2',
      tags: const {'defocus'},
      quad: _rotatedQuad(180, 140, 235, 11),
      blurRadius: 2,
    ),
    _Recipe(
      id: 'motion-blur',
      tags: const {'motion-blur'},
      quad: _rotatedQuad(180, 140, 225, -17),
      motionBlur: 5,
    ),
    _Recipe(
      id: 'low-contrast-noise',
      tags: const {'contrast', 'sensor-noise'},
      quad: _rotatedQuad(180, 140, 220, 5),
      black: 73,
      white: 181,
      background: 188,
      noise: 9,
      seed: 0x1c0ffee,
    ),
    _Recipe(
      id: 'underexposed',
      tags: const {'exposure'},
      quad: _rotatedQuad(180, 140, 220, -12),
      black: 3,
      white: 92,
      background: 100,
      noise: 5,
      gradientX: -12,
      seed: 0x0badf00d,
    ),
    _Recipe(
      id: 'uneven-lighting',
      tags: const {'lighting', 'vignette'},
      quad: _rotatedQuad(180, 140, 225, 21),
      gradientX: 58,
      gradientY: -35,
      vignette: 40,
      noise: 4,
      seed: 0x51a7,
    ),
    _Recipe(
      id: 'glare-edge',
      tags: const {'glare'},
      quad: _rotatedQuad(180, 140, 225, -5),
      glare: const _Glare(0.36, 0.38, 42, 0.72),
      noise: 3,
      seed: 0x61a2e,
    ),
    _Recipe(
      id: 'glare-corner',
      tags: const {'glare', 'perspective'},
      quad: const [
        _Point(70, 58),
        _Point(300, 73),
        _Point(274, 245),
        _Point(62, 220),
      ],
      glare: const _Glare(0.69, 0.67, 27, 0.55),
      gradientX: 12,
    ),
    _Recipe(
      id: 'moire',
      tags: const {'moire', 'display-capture'},
      quad: _rotatedQuad(180, 140, 218, 3),
      moireAmplitude: 19,
      moirePeriod: 6,
      noise: 3,
      seed: 0x0a01ce,
    ),
    _Recipe(
      id: 'rgba-padded',
      tags: const {'rgba', 'row-stride'},
      quad: _rotatedQuad(180, 140, 210, 24),
      pixelFormat: BarcodePixelFormat.rgba8888,
      rowPadding: 29,
      noise: 3,
      seed: 0x0a6ba,
    ),
    _Recipe(
      id: 'bgra-padded',
      tags: const {'bgra', 'row-stride'},
      quad: _rotatedQuad(180, 140, 210, -24),
      pixelFormat: BarcodePixelFormat.bgra8888,
      rowPadding: 31,
      gradientY: 20,
    ),
  ];

  // Seeded compounds cover interactions that hand-picked one-axis tests miss.
  for (var index = 0; index < 10; index++) {
    final random = _XorShift32(0x74584d00 + index * 7919);
    final angle = random.nextDouble() * 70 - 35;
    final size = 190 + random.nextDouble() * 42;
    final quad = _rotatedQuad(180, 140, size, angle);
    final perspective = 8 + random.nextDouble() * 16;
    quad[0] = quad[0] + _Point(random.signed(perspective), random.signed(8));
    quad[1] = quad[1] + _Point(random.signed(8), random.signed(perspective));
    quad[2] = quad[2] + _Point(random.signed(perspective), random.signed(8));
    quad[3] = quad[3] + _Point(random.signed(8), random.signed(perspective));
    recipes.add(
      _Recipe(
        id: 'compound-$index',
        tags: const {'compound', 'perspective', 'sensor-noise', 'lighting'},
        quad: quad,
        black: 18 + random.nextInt(38),
        white: 205 + random.nextInt(36),
        background: 210 + random.nextInt(28),
        gradientX: random.nextInt(47) - 23,
        gradientY: random.nextInt(47) - 23,
        vignette: random.nextInt(24),
        noise: 3 + random.nextInt(7),
        blurRadius: index == 3 || index == 8 ? 1 : 0,
        moireAmplitude: index == 5 ? 11 : 0,
        glare: index == 3 ? const _Glare(0.66, 0.35, 29, 0.55) : null,
        seed: 0x74584d00 + index * 7919,
      ),
    );
  }

  recipes.addAll([
    const _Recipe(
      id: 'negative-blank',
      tags: {'negative'},
      quad: [
        _Point(80, 40),
        _Point(280, 40),
        _Point(280, 240),
        _Point(80, 240),
      ],
      black: 255,
      white: 255,
      background: 255,
      expectation: SyntheticExpectation.notFound,
    ),
    const _Recipe(
      id: 'negative-noise',
      tags: {'negative', 'sensor-noise'},
      quad: [
        _Point(80, 40),
        _Point(280, 40),
        _Point(280, 240),
        _Point(80, 240),
      ],
      black: 127,
      white: 127,
      background: 127,
      noise: 127,
      seed: 0x243f6a88,
      expectation: SyntheticExpectation.notFound,
    ),
    _Recipe(
      id: 'negative-destroyed-finder',
      tags: const {'negative', 'occlusion'},
      quad: _rotatedQuad(180, 140, 220, 0),
      occlusion: const _Occlusion(130, 90, 100, 100, 255),
      expectation: SyntheticExpectation.notFound,
    ),
  ]);
  return recipes;
}

List<_Point> _rotatedQuad(
  double centerX,
  double centerY,
  double size,
  double degrees,
) {
  final radians = degrees * math.pi / 180;
  final cosine = math.cos(radians);
  final sine = math.sin(radians);
  final half = size / 2;
  return [
    for (final point in const [
      _Point(-1, -1),
      _Point(1, -1),
      _Point(1, 1),
      _Point(-1, 1),
    ])
      _Point(
        centerX + (point.x * cosine - point.y * sine) * half,
        centerY + (point.x * sine + point.y * cosine) * half,
      ),
  ];
}

Uint8List _projectSymbol(BarcodeMatrix matrix, _Recipe recipe) {
  const width = _frameWidth;
  const height = _frameHeight;
  final output = Uint8List(width * height);
  final inverse = _inverseHomography(recipe.quad);
  final totalModules = matrix.width + _quietModules * 2;
  final random = _XorShift32(recipe.seed);
  final glare = recipe.glare;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var darkSamples = 0;
      var insideSamples = 0;
      // Four fixed subpixel samples provide deterministic edge antialiasing and
      // model the integration area of a camera photosite.
      for (final offset in const [
        _Point(0.25, 0.25),
        _Point(0.75, 0.25),
        _Point(0.25, 0.75),
        _Point(0.75, 0.75),
      ]) {
        final uv = _mapInverse(inverse, x + offset.x, y + offset.y);
        if (uv == null) continue;
        insideSamples++;
        final moduleX = (uv.x * totalModules).floor() - _quietModules;
        final moduleY = (uv.y * totalModules).floor() - _quietModules;
        if (moduleX >= 0 &&
            moduleX < matrix.width &&
            moduleY >= 0 &&
            moduleY < matrix.height &&
            matrix.isDark(moduleX, moduleY)) {
          darkSamples++;
        }
      }

      var value =
          (recipe.black * darkSamples +
              recipe.white * (insideSamples - darkSamples) +
              recipe.background * (4 - insideSamples)) /
          4;

      // Illumination is applied after compositing so it crosses symbol and
      // background continuously, as a real shadow/exposure gradient would.
      value +=
          recipe.gradientX * (x / math.max(1, width - 1) - 0.5) +
          recipe.gradientY * (y / math.max(1, height - 1) - 0.5);

      if (recipe.vignette != 0) {
        final dx = (x - width / 2) / (width / 2);
        final dy = (y - height / 2) / (height / 2);
        value -= recipe.vignette * math.min(1, (dx * dx + dy * dy) / 2);
      }
      if (recipe.moireAmplitude != 0) {
        value +=
            recipe.moireAmplitude *
            math.sin((x + y * 0.37) * 2 * math.pi / recipe.moirePeriod);
      }
      if (glare != null) {
        final glareX = glare.x * width;
        final glareY = glare.y * height;
        final distance = math.sqrt(
          (x - glareX) * (x - glareX) + (y - glareY) * (y - glareY),
        );
        if (distance < glare.radius) {
          final falloff = 1 - distance / glare.radius;
          final blend = glare.strength * falloff * falloff;
          value = value * (1 - blend) + 255 * blend;
        }
      }
      if (recipe.noise != 0) {
        value += random.signed(recipe.noise.toDouble());
      }
      output[y * width + x] = value.round().clamp(0, 255);
    }
  }
  return output;
}

/// Returns inverse matrix taking frame x/y to source u/v.
List<double> _inverseHomography(List<_Point> quad) {
  final p0 = quad[0];
  final p1 = quad[1];
  final p2 = quad[2];
  final p3 = quad[3];
  final dx1 = p1.x - p2.x;
  final dx2 = p3.x - p2.x;
  final dx3 = p0.x - p1.x + p2.x - p3.x;
  final dy1 = p1.y - p2.y;
  final dy2 = p3.y - p2.y;
  final dy3 = p0.y - p1.y + p2.y - p3.y;

  double g;
  double h;
  final denominator = dx1 * dy2 - dx2 * dy1;
  if (dx3.abs() < 1e-12 && dy3.abs() < 1e-12) {
    g = 0;
    h = 0;
  } else {
    g = (dx3 * dy2 - dx2 * dy3) / denominator;
    h = (dx1 * dy3 - dx3 * dy1) / denominator;
  }
  final a = p1.x - p0.x + g * p1.x;
  final b = p3.x - p0.x + h * p3.x;
  final c = p0.x;
  final d = p1.y - p0.y + g * p1.y;
  final e = p3.y - p0.y + h * p3.y;
  final f = p0.y;

  final determinant = a * (e - f * h) - b * (d - f * g) + c * (d * h - e * g);
  return [
    (e - f * h) / determinant,
    (c * h - b) / determinant,
    (b * f - c * e) / determinant,
    (f * g - d) / determinant,
    (a - c * g) / determinant,
    (c * d - a * f) / determinant,
    (d * h - e * g) / determinant,
    (b * g - a * h) / determinant,
    (a * e - b * d) / determinant,
  ];
}

_Point? _mapInverse(List<double> matrix, double x, double y) {
  final denominator = matrix[6] * x + matrix[7] * y + matrix[8];
  if (denominator.abs() < 1e-12) return null;
  final u = (matrix[0] * x + matrix[1] * y + matrix[2]) / denominator;
  final v = (matrix[3] * x + matrix[4] * y + matrix[5]) / denominator;
  if (u < 0 || u >= 1 || v < 0 || v >= 1) return null;
  return _Point(u, v);
}

Uint8List _boxBlur(Uint8List source, int width, int height, int radius) {
  final horizontal = Uint8List(source.length);
  final output = Uint8List(source.length);
  final diameter = radius * 2 + 1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var dx = -radius; dx <= radius; dx++) {
        sum += source[y * width + (x + dx).clamp(0, width - 1)];
      }
      horizontal[y * width + x] = (sum + diameter ~/ 2) ~/ diameter;
    }
  }
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var dy = -radius; dy <= radius; dy++) {
        sum += horizontal[(y + dy).clamp(0, height - 1) * width + x];
      }
      output[y * width + x] = (sum + diameter ~/ 2) ~/ diameter;
    }
  }
  return output;
}

Uint8List _horizontalMotionBlur(
  Uint8List source,
  int width,
  int height,
  int length,
) {
  final output = Uint8List(source.length);
  final half = length ~/ 2;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var dx = -half; dx <= half; dx++) {
        sum += source[y * width + (x + dx).clamp(0, width - 1)];
      }
      output[y * width + x] = (sum + length ~/ 2) ~/ length;
    }
  }
  return output;
}

void _fillRect(Uint8List pixels, int width, int height, _Occlusion rectangle) {
  final left = rectangle.x.clamp(0, width);
  final top = rectangle.y.clamp(0, height);
  final right = (rectangle.x + rectangle.width).clamp(0, width);
  final bottom = (rectangle.y + rectangle.height).clamp(0, height);
  for (var y = top; y < bottom; y++) {
    pixels.fillRange(y * width + left, y * width + right, rectangle.luminance);
  }
}

SyntheticFrame _packFrame(Uint8List luminance, _Recipe recipe) {
  final bytesPerPixel = recipe.pixelFormat.bytesPerPixel;
  const width = _frameWidth;
  const height = _frameHeight;
  final rowBytes = width * bytesPerPixel;
  final rowStride = rowBytes + recipe.rowPadding;
  final output = Uint8List(rowStride * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = luminance[y * width + x];
      final offset = y * rowStride + x * bytesPerPixel;
      if (bytesPerPixel == 1) {
        output[offset] = value;
      } else {
        output
          ..[offset] = value
          ..[offset + 1] = value
          ..[offset + 2] = value
          ..[offset + 3] = 255;
      }
    }
    for (var offset = rowBytes; offset < rowStride; offset++) {
      output[y * rowStride + offset] = (y * 131 + offset * 17) & 0xff;
    }
  }
  return SyntheticFrame(
    bytes: output,
    width: width,
    height: height,
    rowStride: rowStride,
    pixelFormat: recipe.pixelFormat,
  );
}

final class _XorShift32 {
  _XorShift32(int seed) : _state = seed & 0xffffffff;

  int _state;

  int nextUint32() {
    var value = _state;
    value ^= value << 13;
    value ^= value >>> 17;
    value ^= value << 5;
    return _state = value & 0xffffffff;
  }

  double nextDouble() => nextUint32() / 0x100000000;
  int nextInt(int maximum) => (nextDouble() * maximum).floor();
  double signed(double magnitude) => (nextDouble() * 2 - 1) * magnitude;
}
