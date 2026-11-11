// The character catalog and renderer the app runs in a hidden WKWebView.
// DiceBear has no Swift library, so the app calls these functions and gets PNGs back.
// Keep @dicebear at the same version as the backend (place-rating-api), which validates the same options.
import { createAvatar } from '@dicebear/core';
import {
  adventurer, avataaars, bigEars, bigSmile, croodles, dylan, lorelei,
  micah, miniavs, notionists, openPeeps, personas, pixelArt, toonHead,
} from '@dicebear/collection';

const STYLES = {
  avataaars, personas, micah, adventurer, bigSmile, openPeeps, lorelei,
  notionists, bigEars, croodles, dylan, miniavs, pixelArt, toonHead,
};

// Options that describe the picture rather than the person. The server refuses them too.
const SKIP = new Set([
  'seed', 'flip', 'rotate', 'scale', 'radius', 'size', 'translateX', 'translateY', 'clip',
  'randomizeIds', 'backgroundColor', 'backgroundType', 'backgroundRotation', 'clothingGraphic',
  // Avataaars' "style" only adds a coloured circle behind the character; the app draws its own
  'style',
]);
const HAIR_KEY = { avataaars: 'top', openPeeps: 'head' };
const hats = ['hat', 'winterHat1', 'winterHat02', 'winterHat03', 'winterHat04'];

// Hairstyles per gender for the styles whose option names say what they are.
// Styles that only number their hairstyles show all of them for both.
const SPLIT = {
  avataaars: {
    male: ['none', 'shortFlat', 'shortRound', 'shortWaved', 'shortCurly', 'sides', 'theCaesar', 'theCaesarAndSidePart', 'shaggy', 'shaggyMullet', 'shavedSides', 'frizzle', 'fro', 'dreads01', 'dreads02', 'turban', ...hats],
    female: ['straight01', 'straight02', 'straightAndStrand', 'longButNotTooLong', 'bigHair', 'miaWallace', 'curvy', 'curly', 'bob', 'bun', 'frida', 'fro', 'froBand', 'dreads', 'shavedSides', 'hijab', ...hats],
  },
  personas: {
    male: ['none', 'shortCombover', 'shortComboverChops', 'buzzcut', 'fade', 'bald', 'balding', 'mohawk', 'curlyHighTop', 'sideShave', 'curly', 'cap', 'beanie'],
    female: ['long', 'extraLong', 'bobCut', 'bobBangs', 'pigtails', 'curlyBun', 'straightBun', 'bunUndercut', 'curly', 'sideShave', 'cap', 'beanie'],
  },
  micah: {
    male: ['none', 'fonze', 'mrT', 'dougFunny', 'mrClean', 'dannyPhantom', 'turban', 'full'],
    female: ['full', 'pixie', 'dannyPhantom', 'dougFunny'],
  },
  adventurer: {
    male: (v) => v === 'none' || v.startsWith('short'),
    female: (v) => v.startsWith('long'),
  },
  bigSmile: {
    male: ['shortHair', 'mohawk', 'bowlCutHair', 'shavedHead', 'halfShavedHead', 'curlyShortHair', 'froBun'],
    female: ['wavyBob', 'curlyBob', 'straightHair', 'braids', 'bunHair', 'froBun', 'bangs', 'halfShavedHead', 'curlyShortHair'],
  },
  openPeeps: {
    male: ['short1', 'short2', 'short3', 'short4', 'short5', 'pomp', 'flatTop', 'flatTopLong', 'mohawk', 'mohawk2', 'shaved1', 'shaved2', 'shaved3', 'noHair1', 'noHair2', 'noHair3', 'grayShort', 'afro', 'cornrows', 'cornrows2', 'dreads1', 'dreads2', 'twists', 'twists2', 'medium1', 'medium2', 'medium3', 'turban', 'hatBeanie', 'hatHip', 'bear'],
    female: ['long', 'longAfro', 'longBangs', 'longCurly', 'mediumStraight', 'mediumBangs', 'mediumBangs2', 'mediumBangs3', 'bangs', 'bangs2', 'bun', 'bun2', 'buns', 'bantuKnots', 'grayBun', 'grayMedium', 'afro', 'twists', 'twists2', 'cornrows', 'cornrows2', 'dreads1', 'dreads2', 'hijab', 'hatBeanie', 'hatHip', 'bear'],
  },
};
const FACIAL = /^(facialHair|beard)(Color)?$/;
const MUSTACHE = /mustache|moustache/i;
const BLACKABLE = /(hair|beard|facialHair|brows|eyebrows)Color$/i;
const BLACK = '111111';

const hairKey = (style) => HAIR_KEY[style] ?? 'hair';

const NAMES = {
  avataaars: 'Avataaars', personas: 'Personas', micah: 'Micah', adventurer: 'Adventurer', bigSmile: 'Big Smile',
  openPeeps: 'Open Peeps', lorelei: 'Lorelei', notionists: 'Notionists', bigEars: 'Big Ears', croodles: 'Croodles',
  dylan: 'Dylan', miniavs: 'Miniavs', pixelArt: 'Pixel Art', toonHead: 'Toon Head',
};

// The order parts appear on the character screen; anything not listed comes after, in schema order.
const ORDER = [
  'top', 'hair', 'head', 'hairColor', 'skinColor', 'baseColor', 'eyes', 'eyesColor', 'eyebrows', 'brows',
  'eyebrowsColor', 'mouth', 'lips', 'face', 'nose', 'facialHair', 'beard', 'facialHairColor', 'clothing',
  'clothes', 'body', 'shirt', 'clothesColor', 'clothingColor', 'shirtColor', 'hatColor', 'glasses',
  'glassesColor', 'accessories', 'accessoriesColor', 'earrings', 'earringsColor', 'earringColor',
];
const rank = (name) => (ORDER.includes(name) ? ORDER.indexOf(name) : ORDER.length);

// Colour options whose name does not match the part they colour.
const COLOR_OF = {
  hairColor: ['top', 'hair', 'head'], hatColor: ['top'], clothesColor: ['clothing'], clothingColor: ['clothing'],
  shirtColor: ['shirt'], eyeShadowColor: ['eyes'], headContrastColor: ['head'],
};

/**
 * Every option goes on the page of the part it belongs with: `hairColor` with the hair,
 * `glassesColor` with the glasses. Anything else gets a page of its own (skin colour, for one).
 */
function pageOf(name, names) {
  for (const part of COLOR_OF[name] ?? []) if (names.includes(part)) return part;
  if (name.endsWith('Color')) {
    const base = name.slice(0, -'Color'.length);
    for (const part of [base, `${base}s`]) if (names.includes(part)) return part;
  }
  return name;
}

// Expressions a random starting character avoids. They can all still be chosen by hand.
const GLOOMY = /vomit|scream|cry|dizzy|angry|sad|concerned|frown|grimace|disbelief|rage|fear|monster|eyeRoll|hectic|contempt|suspicious|tired|pacifier|serious|unimpressed|awkward/i;

function properties(style) {
  return STYLES[style].schema.properties;
}

/** The option groups a person can choose from, for a style and gender. */
function groups(style, gender) {
  const P = properties(style);
  const split = SPLIT[style];
  const out = [];
  for (const [name, p] of Object.entries(P)) {
    if (SKIP.has(name) || name.endsWith('Probability') || p.type !== 'array') continue;
    const items = p.items ?? {};
    const optional = P[`${name}Probability`] !== undefined;
    let kind;
    let values;
    if (items.enum) {
      kind = 'enum';
      values = (optional ? ['none'] : []).concat(items.enum);
    } else if (items.pattern && Array.isArray(p.default)) {
      kind = 'color';
      values = (BLACKABLE.test(name) && !p.default.includes(BLACK) ? [BLACK] : []).concat(p.default);
    } else {
      continue;
    }
    if (gender === 'female') {
      if (FACIAL.test(name)) continue;
      if (kind === 'enum') values = values.filter((v) => !MUSTACHE.test(v));
    }
    if (name === hairKey(style) && split) {
      const rule = split[gender];
      values = typeof rule === 'function'
        ? values.filter(rule)
        : rule.filter((v) => values.includes(v)); // in the list's order: plain hairstyles before hats
    }
    // a part with a single look is not a choice
    if (values.length > 1) out.push({ name, kind, values });
  }
  const names = out.map((g) => g.name);
  for (const g of out) g.page = pageOf(g.name, names);
  // pages in ORDER; on a page, the part itself before its colours
  return out.sort((a, b) => rank(a.page) - rank(b.page) || (a.page === b.page && (a.name === a.page ? -1 : b.name === b.page ? 1 : 0)) || 0);
}

/** Fills in or fixes every option so it is valid for the style and gender. */
function normalise(style, gender, options) {
  const result = {};
  for (const g of groups(style, gender)) {
    const current = options?.[g.name];
    if (current !== undefined && g.values.includes(current)) {
      result[g.name] = current;
    } else {
      // optional parts start switched off, except hair
      const firstReal = g.values.find((v) => v !== 'none') ?? g.values[0];
      result[g.name] = g.values[0] === 'none' && !FACIAL.test(g.name) && g.name !== hairKey(style) ? 'none' : firstReal;
      if (FACIAL.test(g.name)) result[g.name] = 'none';
    }
  }
  if (gender === 'female') for (const name of Object.keys(properties(style))) if (FACIAL.test(name)) result[name] = 'none';
  return result;
}

const pick = (values) => values[Math.floor(Math.random() * values.length)];

/** A pleasant random character: friendly expressions, and optional extras only now and then. */
function random(style, gender) {
  const result = {};
  for (const g of groups(style, gender)) {
    const real = g.values.filter((v) => v !== 'none');
    const cheerful = g.kind === 'enum' ? real.filter((v) => !GLOOMY.test(v)) : real;
    const optional = g.values[0] === 'none' && g.name !== hairKey(style);
    result[g.name] = optional && Math.random() < 0.65 ? 'none' : pick(cheerful.length ? cheerful : real);
  }
  return normalise(style, gender, result);
}

/** Our `{ option: value }` map → the options DiceBear's createAvatar takes. */
function diceBearOptions(style, options) {
  const P = properties(style);
  const o = { seed: 'stoop' };
  if (P.style) o.style = ['default'];
  for (const name of Object.keys(P)) {
    if (name.endsWith('Probability')) o[name] = 0; // nothing optional appears unless chosen
  }
  for (const [name, value] of Object.entries(options ?? {})) {
    if (!P[name]) continue;
    if (value === 'none') {
      o[`${name}Probability`] = 0;
    } else {
      o[name] = [value];
      if (P[`${name}Probability`]) o[`${name}Probability`] = 100;
    }
  }
  return o;
}

function svg(style, options) {
  return createAvatar(STYLES[style], diceBearOptions(style, options)).toString();
}

/** Draws the character into a square PNG of `pixels` and returns it as base64. */
async function png(style, options, pixels) {
  const image = new Image();
  image.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg(style, options))}`;
  await image.decode();
  const canvas = document.createElement('canvas');
  canvas.width = pixels;
  canvas.height = pixels;
  // a CPU-backed canvas: the GPU-backed one never hands its pixels back while the web view is off screen
  canvas.getContext('2d', { willReadFrequently: true }).drawImage(image, 0, 0, pixels, pixels);
  return canvas.toDataURL('image/png').slice('data:image/png;base64,'.length);
}

function catalog() {
  return Object.entries(STYLES).map(([id, s]) => ({
    id,
    title: NAMES[id] ?? s.meta?.title ?? id,
    creator: s.meta?.creator ?? '',
    license: s.meta?.license?.name ?? '',
    sortedByGender: Boolean(SPLIT[id]),
  }));
}

const api = { catalog, groups, normalise, random, svg, png };

/**
 * Called by the app with evaluateJavaScript. The answer comes back as a message, because the
 * Swift API that awaits JavaScript promises needs a WebKit library iOS 18 does not have.
 */
async function run(id, method, args) {
  const reply = (body) => window.webkit.messageHandlers.stoop.postMessage({ id, ...body });
  try {
    reply({ result: JSON.stringify((await api[method](...args)) ?? null) });
  } catch (error) {
    reply({ error: String(error) });
  }
}

window.StoopAvatars = { ...api, run };
