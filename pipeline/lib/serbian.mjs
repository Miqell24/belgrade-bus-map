// Serbian street names for the second line of every street label.
//
// Serbia is officially digraphic and OSM reflects that: Belgrade's ways carry
// `name` in Cyrillic and `name:sr-Latn` alongside it (100 % of the sampled
// central streets). So unlike Sofia — where the Latin line had to be produced
// by a transliterator — the Latin reading here is READ, not computed, and the
// map shows exactly what the city's own sign posts show.
//
// The transliterator below is only the fallback for the few ways OSM leaves
// untagged. Serbian Cyrillic → Latin is one of the rare scripts where that is
// completely safe: the mapping is a bijection, 30 letters to 30, with three
// digraphs (љ→lj, њ→nj, џ→dž) and no context rules, no exceptions, no loan-word
// list. (The reverse direction is the ambiguous one — "nadživeti" would fold
// to џ — which is another reason nothing here ever goes Latin → Cyrillic.)

const SR_LETTER = {
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', ђ: 'đ', е: 'e', ж: 'ž', з: 'z',
  и: 'i', ј: 'j', к: 'k', л: 'l', љ: 'lj', м: 'm', н: 'n', њ: 'nj', о: 'o',
  п: 'p', р: 'r', с: 's', т: 't', ћ: 'ć', у: 'u', ф: 'f', х: 'h', ц: 'c',
  ч: 'č', џ: 'dž', ш: 'š',
};

// Capitals: Љ/Њ/Џ are title-cased (Lj) inside a word and upper-cased (LJ) in an
// all-caps run — "ЉУБА" is LJUBA, "Љубљанска" is Ljubljanska.
const upper = (latin, allCaps) =>
  latin.length > 1 && !allCaps
    ? latin[0].toUpperCase() + latin.slice(1)
    : latin.toUpperCase();

const isCyr = (ch) => ch >= 'Ѐ' && ch <= 'ӿ';

export function latinize(name) {
  if (!name || ![...name].some(isCyr)) return '';
  const chars = [...name];
  let out = '';
  for (let i = 0; i < chars.length; i++) {
    const ch = chars[i];
    const low = ch.toLowerCase();
    const mapped = SR_LETTER[low];
    if (!mapped) { out += ch; continue; }
    if (ch === low) { out += mapped; continue; }
    // a capital followed by another capital (or ending the word) is part of an
    // all-caps run
    const next = chars[i + 1];
    out += upper(mapped, !next || (next === next.toUpperCase() && isCyr(next)));
  }
  return out;
}

// name → name:sr-Latn, harvested from the extracts the pipeline already reads.
// Keyed on the exact Cyrillic string, so a street mapped as several ways
// resolves once and identically along its whole course.
export function buildLatinDict(docs) {
  const dict = new Map();
  for (const doc of docs) {
    for (const el of doc.elements || []) {
      const t = el.tags;
      if (!t) continue;
      const cyr = t.name;
      const lat = t['name:sr-Latn'];
      if (!cyr || !lat || cyr === lat) continue;
      if (!dict.has(cyr)) dict.set(cyr, lat);
    }
  }
  return dict;
}

// The Latin line for one name: OSM's own tag first, transliteration second,
// nothing at all when the name is already Latin (many suburban roads are).
export function latinLine(name, dict) {
  const tagged = dict.get(name);
  if (tagged) return tagged;
  const tr = latinize(name);
  return tr && tr !== name ? tr : '';
}
