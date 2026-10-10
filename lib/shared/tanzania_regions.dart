/// The 31 regions of Tanzania (26 mainland, 5 Zanzibar), A–Z, for region
/// pickers. Names as used by the National Bureau of Statistics.
const tanzaniaRegions = <String>[
  'Arusha',
  'Dar es Salaam',
  'Dodoma',
  'Geita',
  'Iringa',
  'Kagera',
  'Kaskazini Pemba',
  'Kaskazini Unguja',
  'Katavi',
  'Kigoma',
  'Kilimanjaro',
  'Kusini Pemba',
  'Kusini Unguja',
  'Lindi',
  'Manyara',
  'Mara',
  'Mbeya',
  'Mjini Magharibi',
  'Morogoro',
  'Mtwara',
  'Mwanza',
  'Njombe',
  'Pwani',
  'Rukwa',
  'Ruvuma',
  'Shinyanga',
  'Simiyu',
  'Singida',
  'Songwe',
  'Tabora',
  'Tanga',
];

/// The listed region matching [value] (ignoring case and extra spaces), or
/// null when it is not one of them (e.g. text typed before the list existed).
String? matchTanzaniaRegion(String? value) {
  final v = (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (v.isEmpty) return null;
  for (final r in tanzaniaRegions) {
    if (r.toLowerCase() == v) return r;
  }
  return null;
}
