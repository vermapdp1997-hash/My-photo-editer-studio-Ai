import 'dart:math' as math;

enum FilterCategory {
  natural('Natural'),
  portrait('Portrait'),
  cinematic('Cinematic'),
  vintage('Vintage'),
  blackAndWhite('Black & White'),
  warm('Warm'),
  cool('Cool'),
  landscape('Landscape'),
  professional('Professional'),
  socialMedia('Social Media');

  final String label;
  const FilterCategory(this.label);
}

class FilterPreset {
  final String id;
  final String name;
  final FilterCategory category;
  final double exposure;
  final double contrast;
  final double saturation;
  final double warmth;
  final double tint;
  final double fade;
  final double redScale;
  final double greenScale;
  final double blueScale;
  final bool monochrome;
  final double sepia;
  final double vignette;

  const FilterPreset({
    required this.id,
    required this.name,
    required this.category,
    this.exposure = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
    this.tint = 0,
    this.fade = 0,
    this.redScale = 1,
    this.greenScale = 1,
    this.blueScale = 1,
    this.monochrome = false,
    this.sepia = 0,
    this.vignette = 0,
  });
}

class FilterCatalog {
  FilterCatalog._();

  static final List<FilterPreset> all = _buildCatalog();

  static FilterPreset? byId(String? id) {
    if (id == null) return null;
    for (final f in all) {
      if (f.id == id) return f;
    }
    return null;
  }

  static List<FilterPreset> byCategory(FilterCategory category) {
    return all.where((f) => f.category == category).toList();
  }

  static List<FilterPreset> _buildCatalog() {
    final list = <FilterPreset>[];

    const specs = <(FilterCategory, List<String>)>[
      (
        FilterCategory.natural,
        [
          'Pure Daylight', 'Morning Dew', 'Soft Breeze', 'True Tone',
          'Clean Crisp', 'Garden Leaf', 'Meadow Mist', 'Clear Air',
          'Open Sky', 'Silk Light', 'Fresh Bloom',
        ]
      ),
      (
        FilterCategory.portrait,
        [
          'Porcelain Skin', 'Studio Soft', 'Peach Glow', 'Velvet Face',
          'Golden Portrait', 'Rosewood', 'Honey Bronze', 'Ivory Shade',
          'Natural Beauty', 'Editorial Skin', 'Warm Studio',
        ]
      ),
      (
        FilterCategory.cinematic,
        [
          'Teal & Orange', 'Anamorphic', 'Blockbuster', 'Noir Blue',
          'Dune Amber', 'Blade Dusk', 'Cinema 35mm', 'Neo Tokyo',
          'Moody Slate', 'Action Contrast', 'Silver Screen',
        ]
      ),
      (
        FilterCategory.vintage,
        [
          'Kodak 1974', 'Retro Fade', 'Polaroid 600', 'Faded Sepia',
          'Analog Tape', 'Old Postcard', 'Rustic Grain', 'Dusty Film',
          'Classic 80s', 'Creamy Print', 'Antique Brass',
        ]
      ),
      (
        FilterCategory.blackAndWhite,
        [
          'Silver Gelatin', 'High Contrast BW', 'Soft Charcoal', 'Noir Shadow',
          'Leica Mono', 'Infrared Mono', 'Platinum Print', 'Ink Wash',
          'Newspaper', 'Crisp Gray', 'Moonlight BW',
        ]
      ),
      (
        FilterCategory.warm,
        [
          'Sunset Gold', 'Amber Ember', 'Sahara Heat', 'Toasted Caramel',
          'Autumn Spice', 'Campfire', 'Mango Sun', 'Warm Linen',
          'Copper Glow', 'Terracotta', 'Golden Hour',
        ]
      ),
      (
        FilterCategory.cool,
        [
          'Arctic Ice', 'Ocean Breeze', 'Nordic Mist', 'Cobalt Dusk',
          'Mint Frost', 'Winter Sky', 'Glacier Blue', 'Steel Cool',
          'Deep Lagoon', 'Twilight Teal', 'Frostbite',
        ]
      ),
      (
        FilterCategory.landscape,
        [
          'Alpine Peak', 'Emerald Valley', 'Vivid Horizon', 'Forest Deep',
          'Coastal Blue', 'Canyon Rock', 'Sunrise Ridge', 'Lush Jungle',
          'Desert Mirage', 'Waterfall', 'Highland',
        ]
      ),
      (
        FilterCategory.professional,
        [
          'Neutral Raw', 'Commercial Pop', 'Crisp Catalog', 'Matte Pro',
          'Fashion Lab', 'Archival Tone', 'Studio Balance', 'Print Ready',
          'Dynamic Range', 'Color Grade A', 'Color Grade B',
        ]
      ),
      (
        FilterCategory.socialMedia,
        [
          'Insta Vibe', 'Reel Boost', 'Pastel Dream', 'Urban Street',
          'Cafe Aesthetic', 'Travel Diary', 'Neon Pop', 'Boho Chic',
          'Minimal Feed', 'Summer Story', 'Night Out',
        ]
      ),
    ];

    int globalIndex = 0;
    for (final (category, names) in specs) {
      for (int i = 0; i < names.length; i++) {
        globalIndex++;
        final t = i / (names.length - 1);
        final phase = globalIndex * 0.6180339;

        double exp = 0;
        double con = 0;
        double sat = 0;
        double warm = 0;
        double tint = 0;
        double fade = 0;
        double rS = 1, gS = 1, bS = 1;
        bool mono = false;
        double sepia = 0;
        double vig = 0;

        switch (category) {
          case FilterCategory.natural:
            exp = 0.03 + 0.08 * math.sin(phase);
            con = 0.05 + 0.10 * t;
            sat = 0.06 + 0.14 * (1 - t * 0.5);
            warm = 0.04 * math.cos(phase);
            gS = 1.0 + 0.04 * t;
          case FilterCategory.portrait:
            exp = 0.08 + 0.07 * t;
            con = -0.04 + 0.12 * t;
            sat = -0.05 + 0.15 * math.sin(phase);
            warm = 0.10 + 0.12 * t;
            tint = 0.04 + 0.06 * math.cos(phase);
            fade = 0.04 + 0.08 * (1 - t);
            rS = 1.04 + 0.04 * t;
          case FilterCategory.cinematic:
            exp = -0.05 + 0.06 * math.cos(phase);
            con = 0.18 + 0.22 * t;
            sat = -0.10 + 0.18 * t;
            warm = -0.12 + 0.26 * math.sin(phase);
            tint = -0.08 + 0.12 * t;
            rS = 1.08 - 0.06 * t;
            bS = 1.06 + 0.10 * (1 - t);
            vig = 0.22 + 0.18 * t;
          case FilterCategory.vintage:
            exp = 0.02 + 0.08 * math.sin(phase);
            con = -0.08 + 0.14 * t;
            sat = -0.25 + 0.15 * t;
            warm = 0.15 + 0.18 * t;
            fade = 0.18 + 0.22 * t;
            sepia = 0.20 + 0.35 * (1 - t * 0.4);
            vig = 0.15 + 0.20 * t;
          case FilterCategory.blackAndWhite:
            mono = true;
            exp = -0.06 + 0.16 * t;
            con = 0.12 + 0.40 * t;
            fade = i % 3 == 0 ? 0.14 : 0.0;
            rS = 0.90 + 0.25 * math.sin(phase);
            bS = 0.90 + 0.25 * math.cos(phase);
            vig = 0.10 + 0.25 * t;
          case FilterCategory.warm:
            exp = 0.04 + 0.08 * t;
            con = 0.06 + 0.12 * math.sin(phase);
            sat = 0.12 + 0.18 * t;
            warm = 0.22 + 0.32 * t;
            rS = 1.08 + 0.08 * t;
            bS = 0.92 - 0.08 * t;
          case FilterCategory.cool:
            exp = 0.02 + 0.07 * math.cos(phase);
            con = 0.08 + 0.14 * t;
            sat = 0.04 + 0.16 * t;
            warm = -0.22 - 0.30 * t;
            tint = -0.05 + 0.08 * math.sin(phase);
            bS = 1.08 + 0.09 * t;
            rS = 0.92 - 0.06 * t;
          case FilterCategory.landscape:
            exp = 0.03 + 0.08 * math.sin(phase);
            con = 0.15 + 0.18 * t;
            sat = 0.24 + 0.26 * t;
            warm = -0.08 + 0.20 * t;
            gS = 1.04 + 0.07 * (1 - t);
            bS = 1.05 + 0.08 * t;
          case FilterCategory.professional:
            exp = 0.02 + 0.06 * t;
            con = 0.12 + 0.16 * t;
            sat = 0.02 + 0.10 * math.cos(phase);
            fade = i % 2 == 0 ? 0.08 : 0.0;
            warm = -0.05 + 0.12 * t;
            vig = 0.08 * t;
          case FilterCategory.socialMedia:
            exp = 0.06 + 0.10 * math.sin(phase);
            con = 0.10 + 0.20 * t;
            sat = 0.15 + 0.25 * (1 - t * 0.3);
            warm = 0.08 * math.cos(phase);
            tint = 0.06 + 0.10 * math.sin(phase);
            fade = 0.06 + 0.12 * t;
        }

        list.add(
          FilterPreset(
            id: 'flt_${category.name}_$i',
            name: names[i],
            category: category,
            exposure: double.parse(exp.toStringAsFixed(3)),
            contrast: double.parse(con.toStringAsFixed(3)),
            saturation: double.parse(sat.toStringAsFixed(3)),
            warmth: double.parse(warm.toStringAsFixed(3)),
            tint: double.parse(tint.toStringAsFixed(3)),
            fade: double.parse(fade.toStringAsFixed(3)),
            redScale: double.parse(rS.toStringAsFixed(3)),
            greenScale: double.parse(gS.toStringAsFixed(3)),
            blueScale: double.parse(bS.toStringAsFixed(3)),
            monochrome: mono,
            sepia: double.parse(sepia.toStringAsFixed(3)),
            vignette: double.parse(vig.toStringAsFixed(3)),
          ),
        );
      }
    }
    return List.unmodifiable(list);
  }
}
