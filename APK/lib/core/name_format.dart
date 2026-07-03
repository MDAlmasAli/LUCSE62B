/// Turns a full legal name into the friendly "call name" we greet people by.
/// Bangladeshi names often lead with an honorific (Md / Mohammad / Mst …) that
/// nobody actually goes by — e.g. "MD Almas Ali" → "Almas", not "Md".
const _honorifics = {
  'md', 'md.', 'mohammad', 'mohammed', 'muhammad', 'mohd', 'mohd.', 'mohammod',
  'mst', 'mst.', 'most', 'most.', 'musammat', 'mosa', 'mosa.',
  'sk', 'sk.', 'sheikh', 'mr', 'mr.', 'mrs', 'mrs.', 'ms', 'ms.', 'miss',
  'dr', 'dr.', 'prof', 'prof.', 'engr', 'engr.', 'al',
};

/// First "real" given name, title-cased. Skips leading honorifics. Always
/// returns at least one token so the greeting is never blank.
String friendlyFirstName(String fullName) {
  final tokens = fullName.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return '';
  var i = 0;
  while (i < tokens.length - 1 && _honorifics.contains(tokens[i].toLowerCase())) {
    i++;
  }
  return _titleCase(tokens[i]);
}

String _titleCase(String w) {
  if (w.isEmpty) return w;
  // Leave non-Latin scripts (e.g. Bangla) untouched.
  final first = w[0];
  if (first.toLowerCase() == first.toUpperCase()) return w;
  return first.toUpperCase() + w.substring(1).toLowerCase();
}
