import 'dart:convert';
import 'dart:ui';

enum RetouchToolType {
  healing,
  spotRemoval,
  manualEraser,
  selectiveBlur,
  aiObjectMask,
  restoreMask,
}

enum BackgroundReplacementType {
  none,
  transparent,
  solidColor,
  gradient,
  image,
}

class RetouchStroke {
  final RetouchToolType tool;
  final List<Offset> normalizedPoints;
  final double brushSize;
  final double intensity;

  const RetouchStroke({
    required this.tool,
    required this.normalizedPoints,
    this.brushSize = 0.04,
    this.intensity = 0.8,
  });

  Map<String, dynamic> toJson() => {
        'tool': tool.name,
        'points': normalizedPoints.map((p) => [p.dx, p.dy]).toList(),
        'brushSize': brushSize,
        'intensity': intensity,
      };

  factory RetouchStroke.fromJson(Map<String, dynamic> json) {
    final rawPts = (json['points'] as List<dynamic>? ?? []);
    return RetouchStroke(
      tool: RetouchToolType.values.firstWhere(
        (e) => e.name == json['tool'],
        orElse: () => RetouchToolType.healing,
      ),
      normalizedPoints: rawPts
          .map((e) => Offset(
                ((e as List)[0] as num).toDouble(),
                (e[1] as num).toDouble(),
              ))
          .toList(),
      brushSize: (json['brushSize'] as num?)?.toDouble() ?? 0.04,
      intensity: (json['intensity'] as num?)?.toDouble() ?? 0.8,
    );
  }
}

class TextLayerItem {
  final String id;
  final String text;
  final double normX;
  final double normY;
  final double fontSize;
  final int colorValue;
  final String fontFamily;
  final bool hasShadow;
  final double rotation;

  const TextLayerItem({
    required this.id,
    required this.text,
    this.normX = 0.5,
    this.normY = 0.5,
    this.fontSize = 28,
    this.colorValue = 0xFFFFFFFF,
    this.fontFamily = 'Sans',
    this.hasShadow = true,
    this.rotation = 0,
  });

  TextLayerItem copyWith({
    String? text,
    double? normX,
    double? normY,
    double? fontSize,
    int? colorValue,
    String? fontFamily,
    bool? hasShadow,
    double? rotation,
  }) {
    return TextLayerItem(
      id: id,
      text: text ?? this.text,
      normX: normX ?? this.normX,
      normY: normY ?? this.normY,
      fontSize: fontSize ?? this.fontSize,
      colorValue: colorValue ?? this.colorValue,
      fontFamily: fontFamily ?? this.fontFamily,
      hasShadow: hasShadow ?? this.hasShadow,
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'normX': normX,
        'normY': normY,
        'fontSize': fontSize,
        'colorValue': colorValue,
        'fontFamily': fontFamily,
        'hasShadow': hasShadow,
        'rotation': rotation,
      };

  factory TextLayerItem.fromJson(Map<String, dynamic> json) => TextLayerItem(
        id: json['id']?.toString() ?? 'txt',
        text: json['text']?.toString() ?? '',
        normX: (json['normX'] as num?)?.toDouble() ?? 0.5,
        normY: (json['normY'] as num?)?.toDouble() ?? 0.5,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 28,
        colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFFFFFFFF,
        fontFamily: json['fontFamily']?.toString() ?? 'Sans',
        hasShadow: json['hasShadow'] as bool? ?? true,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      );
}

class StickerLayerItem {
  final String id;
  final String symbol;
  final double normX;
  final double normY;
  final double scale;
  final double rotation;

  const StickerLayerItem({
    required this.id,
    required this.symbol,
    this.normX = 0.5,
    this.normY = 0.5,
    this.scale = 1.0,
    this.rotation = 0,
  });

  StickerLayerItem copyWith({
    double? normX,
    double? normY,
    double? scale,
    double? rotation,
  }) {
    return StickerLayerItem(
      id: id,
      symbol: symbol,
      normX: normX ?? this.normX,
      normY: normY ?? this.normY,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'symbol': symbol,
        'normX': normX,
        'normY': normY,
        'scale': scale,
        'rotation': rotation,
      };

  factory StickerLayerItem.fromJson(Map<String, dynamic> json) =>
      StickerLayerItem(
        id: json['id']?.toString() ?? 'stk',
        symbol: json['symbol']?.toString() ?? '✨',
        normX: (json['normX'] as num?)?.toDouble() ?? 0.5,
        normY: (json['normY'] as num?)?.toDouble() ?? 0.5,
        scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      );
}

class EditState {
  // Basic Adjustments (-1.0 to 1.0 unless noted)
  final double brightness;
  final double contrast;
  final double exposure;
  final double saturation;
  final double vibrance;
  final double temperature;
  final double tint;
  final double highlights;
  final double shadows;
  final double whites;
  final double blacks;

  // Advanced Adjustments
  final double hslHue; // -180 to 180
  final double hslSaturation; // -1 to 1
  final double hslLightness; // -1 to 1
  final double redGain; // -1 to 1
  final double greenGain; // -1 to 1
  final double blueGain; // -1 to 1
  final double colorBalanceWarmth; // -1 to 1
  final double curveShadows; // -0.5 to 0.5
  final double curveMidtones; // -0.5 to 0.5
  final double curveHighlights; // -0.5 to 0.5
  final double selectiveWarmShift; // -1 to 1
  final double colorGradingTint; // -1 to 1
  final double clarity; // 0 to 1
  final double sharpness; // 0 to 1
  final double noiseReduction; // 0 to 1
  final double vignette; // 0 to 1
  final double grain; // 0 to 1
  final double fade; // 0 to 1
  final double blur; // 0 to 1
  final double perspectiveX; // -0.3 to 0.3
  final double perspectiveY; // -0.3 to 0.3

  // Crop & Transform
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final String aspectRatioLabel;
  final int rotationQuarterTurns; // 0, 1, 2, 3
  final double straightenDegrees; // -15 to 15
  final bool flipHorizontal;
  final bool flipVertical;

  // Filter
  final String? filterId;
  final double filterIntensity;

  // Creative Overlays & Frames
  final List<TextLayerItem> textLayers;
  final List<StickerLayerItem> stickerLayers;
  final String frameStyle; // none, classic, polaroid, neon, film
  final double borderWidth;
  final int borderColorValue;
  final String? doubleExposurePath;
  final double doubleExposureOpacity;
  final String overlayStyle; // none, bokeh, sunflare, dust, prism

  // Retouch & AI
  final List<RetouchStroke> retouchStrokes;
  final String? aiProcessedImagePath;
  final String? aiMaskPath;
  final BackgroundReplacementType bgReplacementType;
  final int bgReplacementColor;
  final String? bgReplacementImagePath;
  final double portraitBlurIntensity;
  final double aiEdgeFeather;

  const EditState({
    this.brightness = 0,
    this.contrast = 0,
    this.exposure = 0,
    this.saturation = 0,
    this.vibrance = 0,
    this.temperature = 0,
    this.tint = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.whites = 0,
    this.blacks = 0,
    this.hslHue = 0,
    this.hslSaturation = 0,
    this.hslLightness = 0,
    this.redGain = 0,
    this.greenGain = 0,
    this.blueGain = 0,
    this.colorBalanceWarmth = 0,
    this.curveShadows = 0,
    this.curveMidtones = 0,
    this.curveHighlights = 0,
    this.selectiveWarmShift = 0,
    this.colorGradingTint = 0,
    this.clarity = 0,
    this.sharpness = 0,
    this.noiseReduction = 0,
    this.vignette = 0,
    this.grain = 0,
    this.fade = 0,
    this.blur = 0,
    this.perspectiveX = 0,
    this.perspectiveY = 0,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 1,
    this.cropBottom = 1,
    this.aspectRatioLabel = 'Free',
    this.rotationQuarterTurns = 0,
    this.straightenDegrees = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.filterId,
    this.filterIntensity = 1.0,
    this.textLayers = const [],
    this.stickerLayers = const [],
    this.frameStyle = 'none',
    this.borderWidth = 0,
    this.borderColorValue = 0xFFFFFFFF,
    this.doubleExposurePath,
    this.doubleExposureOpacity = 0.45,
    this.overlayStyle = 'none',
    this.retouchStrokes = const [],
    this.aiProcessedImagePath,
    this.aiMaskPath,
    this.bgReplacementType = BackgroundReplacementType.none,
    this.bgReplacementColor = 0xFF1E293B,
    this.bgReplacementImagePath,
    this.portraitBlurIntensity = 0,
    this.aiEdgeFeather = 0.25,
  });

  bool get hasAdjustments =>
      brightness != 0 ||
      contrast != 0 ||
      exposure != 0 ||
      saturation != 0 ||
      vibrance != 0 ||
      temperature != 0 ||
      tint != 0 ||
      highlights != 0 ||
      shadows != 0 ||
      whites != 0 ||
      blacks != 0 ||
      hslHue != 0 ||
      hslSaturation != 0 ||
      hslLightness != 0 ||
      redGain != 0 ||
      greenGain != 0 ||
      blueGain != 0 ||
      colorBalanceWarmth != 0 ||
      curveShadows != 0 ||
      curveMidtones != 0 ||
      curveHighlights != 0 ||
      selectiveWarmShift != 0 ||
      colorGradingTint != 0 ||
      clarity != 0 ||
      sharpness != 0 ||
      noiseReduction != 0 ||
      vignette != 0 ||
      grain != 0 ||
      fade != 0 ||
      blur != 0 ||
      perspectiveX != 0 ||
      perspectiveY != 0;

  bool get isModified =>
      hasAdjustments ||
      cropLeft != 0 ||
      cropTop != 0 ||
      cropRight != 1 ||
      cropBottom != 1 ||
      rotationQuarterTurns != 0 ||
      straightenDegrees != 0 ||
      flipHorizontal ||
      flipVertical ||
      filterId != null ||
      textLayers.isNotEmpty ||
      stickerLayers.isNotEmpty ||
      frameStyle != 'none' ||
      borderWidth > 0 ||
      doubleExposurePath != null ||
      overlayStyle != 'none' ||
      retouchStrokes.isNotEmpty ||
      aiProcessedImagePath != null ||
      bgReplacementType != BackgroundReplacementType.none ||
      portraitBlurIntensity > 0;

  EditState copyWith({
    double? brightness,
    double? contrast,
    double? exposure,
    double? saturation,
    double? vibrance,
    double? temperature,
    double? tint,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    double? hslHue,
    double? hslSaturation,
    double? hslLightness,
    double? redGain,
    double? greenGain,
    double? blueGain,
    double? colorBalanceWarmth,
    double? curveShadows,
    double? curveMidtones,
    double? curveHighlights,
    double? selectiveWarmShift,
    double? colorGradingTint,
    double? clarity,
    double? sharpness,
    double? noiseReduction,
    double? vignette,
    double? grain,
    double? fade,
    double? blur,
    double? perspectiveX,
    double? perspectiveY,
    double? cropLeft,
    double? cropTop,
    double? cropRight,
    double? cropBottom,
    String? aspectRatioLabel,
    int? rotationQuarterTurns,
    double? straightenDegrees,
    bool? flipHorizontal,
    bool? flipVertical,
    String? filterId,
    bool clearFilter = false,
    double? filterIntensity,
    List<TextLayerItem>? textLayers,
    List<StickerLayerItem>? stickerLayers,
    String? frameStyle,
    double? borderWidth,
    int? borderColorValue,
    String? doubleExposurePath,
    bool clearDoubleExposure = false,
    double? doubleExposureOpacity,
    String? overlayStyle,
    List<RetouchStroke>? retouchStrokes,
    String? aiProcessedImagePath,
    bool clearAiProcessed = false,
    String? aiMaskPath,
    BackgroundReplacementType? bgReplacementType,
    int? bgReplacementColor,
    String? bgReplacementImagePath,
    double? portraitBlurIntensity,
    double? aiEdgeFeather,
  }) {
    return EditState(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      exposure: exposure ?? this.exposure,
      saturation: saturation ?? this.saturation,
      vibrance: vibrance ?? this.vibrance,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      whites: whites ?? this.whites,
      blacks: blacks ?? this.blacks,
      hslHue: hslHue ?? this.hslHue,
      hslSaturation: hslSaturation ?? this.hslSaturation,
      hslLightness: hslLightness ?? this.hslLightness,
      redGain: redGain ?? this.redGain,
      greenGain: greenGain ?? this.greenGain,
      blueGain: blueGain ?? this.blueGain,
      colorBalanceWarmth: colorBalanceWarmth ?? this.colorBalanceWarmth,
      curveShadows: curveShadows ?? this.curveShadows,
      curveMidtones: curveMidtones ?? this.curveMidtones,
      curveHighlights: curveHighlights ?? this.curveHighlights,
      selectiveWarmShift: selectiveWarmShift ?? this.selectiveWarmShift,
      colorGradingTint: colorGradingTint ?? this.colorGradingTint,
      clarity: clarity ?? this.clarity,
      sharpness: sharpness ?? this.sharpness,
      noiseReduction: noiseReduction ?? this.noiseReduction,
      vignette: vignette ?? this.vignette,
      grain: grain ?? this.grain,
      fade: fade ?? this.fade,
      blur: blur ?? this.blur,
      perspectiveX: perspectiveX ?? this.perspectiveX,
      perspectiveY: perspectiveY ?? this.perspectiveY,
      cropLeft: cropLeft ?? this.cropLeft,
      cropTop: cropTop ?? this.cropTop,
      cropRight: cropRight ?? this.cropRight,
      cropBottom: cropBottom ?? this.cropBottom,
      aspectRatioLabel: aspectRatioLabel ?? this.aspectRatioLabel,
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
      straightenDegrees: straightenDegrees ?? this.straightenDegrees,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      filterId: clearFilter ? null : (filterId ?? this.filterId),
      filterIntensity: filterIntensity ?? this.filterIntensity,
      textLayers: textLayers ?? this.textLayers,
      stickerLayers: stickerLayers ?? this.stickerLayers,
      frameStyle: frameStyle ?? this.frameStyle,
      borderWidth: borderWidth ?? this.borderWidth,
      borderColorValue: borderColorValue ?? this.borderColorValue,
      doubleExposurePath: clearDoubleExposure
          ? null
          : (doubleExposurePath ?? this.doubleExposurePath),
      doubleExposureOpacity:
          doubleExposureOpacity ?? this.doubleExposureOpacity,
      overlayStyle: overlayStyle ?? this.overlayStyle,
      retouchStrokes: retouchStrokes ?? this.retouchStrokes,
      aiProcessedImagePath: clearAiProcessed
          ? null
          : (aiProcessedImagePath ?? this.aiProcessedImagePath),
      aiMaskPath: aiMaskPath ?? this.aiMaskPath,
      bgReplacementType: bgReplacementType ?? this.bgReplacementType,
      bgReplacementColor: bgReplacementColor ?? this.bgReplacementColor,
      bgReplacementImagePath:
          bgReplacementImagePath ?? this.bgReplacementImagePath,
      portraitBlurIntensity:
          portraitBlurIntensity ?? this.portraitBlurIntensity,
      aiEdgeFeather: aiEdgeFeather ?? this.aiEdgeFeather,
    );
  }

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'contrast': contrast,
        'exposure': exposure,
        'saturation': saturation,
        'vibrance': vibrance,
        'temperature': temperature,
        'tint': tint,
        'highlights': highlights,
        'shadows': shadows,
        'whites': whites,
        'blacks': blacks,
        'hslHue': hslHue,
        'hslSaturation': hslSaturation,
        'hslLightness': hslLightness,
        'redGain': redGain,
        'greenGain': greenGain,
        'blueGain': blueGain,
        'colorBalanceWarmth': colorBalanceWarmth,
        'curveShadows': curveShadows,
        'curveMidtones': curveMidtones,
        'curveHighlights': curveHighlights,
        'selectiveWarmShift': selectiveWarmShift,
        'colorGradingTint': colorGradingTint,
        'clarity': clarity,
        'sharpness': sharpness,
        'noiseReduction': noiseReduction,
        'vignette': vignette,
        'grain': grain,
        'fade': fade,
        'blur': blur,
        'perspectiveX': perspectiveX,
        'perspectiveY': perspectiveY,
        'cropLeft': cropLeft,
        'cropTop': cropTop,
        'cropRight': cropRight,
        'cropBottom': cropBottom,
        'aspectRatioLabel': aspectRatioLabel,
        'rotationQuarterTurns': rotationQuarterTurns,
        'straightenDegrees': straightenDegrees,
        'flipHorizontal': flipHorizontal,
        'flipVertical': flipVertical,
        'filterId': filterId,
        'filterIntensity': filterIntensity,
        'textLayers': textLayers.map((e) => e.toJson()).toList(),
        'stickerLayers': stickerLayers.map((e) => e.toJson()).toList(),
        'frameStyle': frameStyle,
        'borderWidth': borderWidth,
        'borderColorValue': borderColorValue,
        'doubleExposurePath': doubleExposurePath,
        'doubleExposureOpacity': doubleExposureOpacity,
        'overlayStyle': overlayStyle,
        'retouchStrokes': retouchStrokes.map((e) => e.toJson()).toList(),
        'aiProcessedImagePath': aiProcessedImagePath,
        'aiMaskPath': aiMaskPath,
        'bgReplacementType': bgReplacementType.name,
        'bgReplacementColor': bgReplacementColor,
        'bgReplacementImagePath': bgReplacementImagePath,
        'portraitBlurIntensity': portraitBlurIntensity,
        'aiEdgeFeather': aiEdgeFeather,
      };

  String toJsonString() => jsonEncode(toJson());

  factory EditState.fromJsonString(String raw) =>
      EditState.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  factory EditState.fromJson(Map<String, dynamic> json) {
    double d(String k, [double def = 0]) =>
        (json[k] as num?)?.toDouble() ?? def;
    return EditState(
      brightness: d('brightness'),
      contrast: d('contrast'),
      exposure: d('exposure'),
      saturation: d('saturation'),
      vibrance: d('vibrance'),
      temperature: d('temperature'),
      tint: d('tint'),
      highlights: d('highlights'),
      shadows: d('shadows'),
      whites: d('whites'),
      blacks: d('blacks'),
      hslHue: d('hslHue'),
      hslSaturation: d('hslSaturation'),
      hslLightness: d('hslLightness'),
      redGain: d('redGain'),
      greenGain: d('greenGain'),
      blueGain: d('blueGain'),
      colorBalanceWarmth: d('colorBalanceWarmth'),
      curveShadows: d('curveShadows'),
      curveMidtones: d('curveMidtones'),
      curveHighlights: d('curveHighlights'),
      selectiveWarmShift: d('selectiveWarmShift'),
      colorGradingTint: d('colorGradingTint'),
      clarity: d('clarity'),
      sharpness: d('sharpness'),
      noiseReduction: d('noiseReduction'),
      vignette: d('vignette'),
      grain: d('grain'),
      fade: d('fade'),
      blur: d('blur'),
      perspectiveX: d('perspectiveX'),
      perspectiveY: d('perspectiveY'),
      cropLeft: d('cropLeft', 0),
      cropTop: d('cropTop', 0),
      cropRight: d('cropRight', 1),
      cropBottom: d('cropBottom', 1),
      aspectRatioLabel: json['aspectRatioLabel']?.toString() ?? 'Free',
      rotationQuarterTurns: (json['rotationQuarterTurns'] as num?)?.toInt() ?? 0,
      straightenDegrees: d('straightenDegrees'),
      flipHorizontal: json['flipHorizontal'] as bool? ?? false,
      flipVertical: json['flipVertical'] as bool? ?? false,
      filterId: json['filterId']?.toString(),
      filterIntensity: d('filterIntensity', 1.0),
      textLayers: (json['textLayers'] as List<dynamic>? ?? [])
          .map((e) => TextLayerItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      stickerLayers: (json['stickerLayers'] as List<dynamic>? ?? [])
          .map((e) => StickerLayerItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      frameStyle: json['frameStyle']?.toString() ?? 'none',
      borderWidth: d('borderWidth'),
      borderColorValue: (json['borderColorValue'] as num?)?.toInt() ?? 0xFFFFFFFF,
      doubleExposurePath: json['doubleExposurePath']?.toString(),
      doubleExposureOpacity: d('doubleExposureOpacity', 0.45),
      overlayStyle: json['overlayStyle']?.toString() ?? 'none',
      retouchStrokes: (json['retouchStrokes'] as List<dynamic>? ?? [])
          .map((e) => RetouchStroke.fromJson(e as Map<String, dynamic>))
          .toList(),
      aiProcessedImagePath: json['aiProcessedImagePath']?.toString(),
      aiMaskPath: json['aiMaskPath']?.toString(),
      bgReplacementType: BackgroundReplacementType.values.firstWhere(
        (e) => e.name == json['bgReplacementType'],
        orElse: () => BackgroundReplacementType.none,
      ),
      bgReplacementColor:
          (json['bgReplacementColor'] as num?)?.toInt() ?? 0xFF1E293B,
      bgReplacementImagePath: json['bgReplacementImagePath']?.toString(),
      portraitBlurIntensity: d('portraitBlurIntensity'),
      aiEdgeFeather: d('aiEdgeFeather', 0.25),
    );
  }
}
