/// Password and passphrase generation with entropy accounting.
///
/// Pure logic with no Flutter dependency, so it is safe to run in an isolate.
library;

import 'dart:math';

double _log10(num value) => log(value) / ln10;

/// How a generated secret is composed.
enum PasswordStyle {
  random('Random characters'),
  passphrase('Wordlist passphrase'),
  pin('Numeric PIN'),
  uuidToken('UUID / token');

  const PasswordStyle(this.label);

  final String label;
}

/// The result of one generation run.
class GeneratedSecret {
  const GeneratedSecret({
    required this.value,
    required this.bitsOfEntropy,
    required this.summary,
    required this.words,
  });

  final String value;

  /// Shannon entropy of the chosen character/word space.
  final int bitsOfEntropy;
  final String summary;

  /// Split passphrase words, or the chunks of a random secret.
  final List<String> words;
}

/// The wordlist used for Diceware-style passphrases.
///
/// Common, concrete, easily spelled words rather than obscure ones, because a
/// passphrase you can retype is worth more than a slightly denser list. At
/// this size each word carries about 10.5 bits, so the default six words
/// land near 63 bits.
const _wordlist = <String>[
  'abbey', 'able', 'adapt', 'adjust', 'admire', 'adopt',
  'advance', 'advise', 'airport', 'alarm', 'alert', 'alley',
  'allow', 'amber', 'amend', 'amuse', 'analyze', 'anchor',
  'ancient', 'ankle', 'announce', 'annoy', 'answer', 'anvil',
  'apple', 'apply', 'approve', 'arch', 'argue', 'arise',
  'arrange', 'arrive', 'arrow', 'assemble', 'assess', 'assist',
  'attach', 'attack', 'attain', 'attempt', 'attend', 'attic',
  'attract', 'avenue', 'avoid', 'await', 'awake', 'backpack',
  'bacon', 'badge', 'bagel', 'bakery', 'balance', 'balloon',
  'banish', 'banjo', 'bank', 'bargain', 'barn', 'barrel',
  'basil', 'basin', 'basket', 'bathe', 'battery', 'beach',
  'beacon', 'bean', 'bear', 'beef', 'believe', 'bell',
  'belt', 'bench', 'bend', 'berry', 'bind', 'bird',
  'biscuit', 'bite', 'blanket', 'blend', 'blender', 'bless',
  'blink', 'block', 'blood', 'bloom', 'blow', 'blush',
  'boast', 'boil', 'bold', 'bolt', 'bone', 'book',
  'boot', 'bottle', 'bounce', 'bowl', 'bracelet', 'brain',
  'brake', 'branch', 'brave', 'bread', 'breathe', 'breed',
  'brew', 'brick', 'bridge', 'bright', 'bring', 'broth',
  'browse', 'brush', 'bucket', 'buckle', 'build', 'burn',
  'bury', 'butter', 'button', 'cabbage', 'cabin', 'cabinet',
  'cable', 'cake', 'call', 'calm', 'camera', 'camp',
  'campus', 'canal', 'candle', 'candy', 'canvas', 'capital',
  'care', 'carrot', 'cart', 'carve', 'cast', 'castle',
  'catch', 'cave', 'ceiling', 'celery', 'cellar', 'cello',
  'chain', 'chair', 'chalk', 'change', 'chapel', 'charge',
  'chase', 'chat', 'cheek', 'cheer', 'cheese', 'chest',
  'chew', 'chicken', 'chili', 'chill', 'chilly', 'chime',
  'chin', 'chop', 'chowder', 'church', 'city', 'claim',
  'clamp', 'clap', 'clay', 'clean', 'clear', 'clever',
  'cliff', 'climb', 'cling', 'clip', 'clock', 'close',
  'closet', 'cloth', 'cloud', 'cloudy', 'coach', 'coast',
  'coat', 'coffee', 'coil', 'coin', 'cold', 'collect',
  'college', 'color', 'comb', 'command', 'compare', 'compass',
  'compete', 'compile', 'complete', 'compose', 'compute', 'conceal',
  'concern', 'conclude', 'confess', 'confirm', 'connect', 'consider',
  'consist', 'consult', 'contain', 'continue', 'control', 'convince',
  'cook', 'cookie', 'cool', 'copy', 'coral', 'cord',
  'cork', 'corn', 'correct', 'cosmic', 'cottage', 'couch',
  'cough', 'count', 'county', 'court', 'cover', 'cracker',
  'crate', 'crawl', 'crayon', 'cream', 'create', 'crimson',
  'cross', 'crown', 'crush', 'cube', 'cucumber', 'cure',
  'curious', 'curl', 'curry', 'curtain', 'curve', 'cushion',
  'cycle', 'dagger', 'daily', 'dairy', 'damp', 'dance',
  'dare', 'dark', 'dash', 'deal', 'debate', 'decay',
  'decide', 'declare', 'decline', 'decorate', 'decrease', 'deep',
  'deer', 'defeat', 'defend', 'define', 'delay', 'delete',
  'deliver', 'demand', 'dense', 'deny', 'depart', 'depend',
  'depot', 'describe', 'desert', 'deserve', 'design', 'desire',
  'desk', 'dessert', 'destroy', 'detect', 'develop', 'devote',
  'diagnose', 'dial', 'diamond', 'diary', 'diner', 'direct',
  'disagree', 'discard', 'discover', 'discuss', 'dish', 'dislike',
  'dismiss', 'display', 'disturb', 'dive', 'divide', 'dizzy',
  'dock', 'doll', 'dolphin', 'dome', 'donate', 'donkey',
  'donut', 'door', 'dorm', 'doubt', 'dough', 'drag',
  'drain', 'draw', 'drawer', 'dream', 'dress', 'drift',
  'drill', 'drink', 'drive', 'drop', 'drown', 'drum',
  'dump', 'dungeon', 'dusty', 'eager', 'eagle', 'early',
  'earn', 'ease', 'easel', 'echo', 'edit', 'educate',
  'elbow', 'elect', 'embassy', 'embrace', 'employ', 'empty',
  'enable', 'enact', 'enclose', 'endure', 'enforce', 'engage',
  'engine', 'enjoy', 'enlarge', 'enroll', 'ensure', 'enter',
  'envelope', 'equal', 'equip', 'erase', 'escape', 'estate',
  'estimate', 'evaluate', 'examine', 'exceed', 'exchange', 'excite',
  'exclude', 'excuse', 'exercise', 'exhale', 'exhaust', 'exist',
  'expand', 'expect', 'explain', 'explode', 'explore', 'export',
  'express', 'extend', 'fabric', 'face', 'factory', 'fade',
  'faint', 'falcon', 'fall', 'fasten', 'faucet', 'favor',
  'fear', 'feast', 'feed', 'feel', 'fence', 'ferret',
  'ferry', 'fetch', 'field', 'fierce', 'fiery', 'fight',
  'file', 'fill', 'find', 'fine', 'finger', 'finish',
  'fire', 'fish', 'fist', 'flap', 'flash', 'flask',
  'flatten', 'flee', 'flick', 'float', 'flood', 'floor',
  'flour', 'flow', 'flower', 'fluffy', 'flush', 'flute',
  'foggy', 'fold', 'folder', 'follow', 'foot', 'forbid',
  'force', 'forecast', 'forest', 'forge', 'forget', 'forgive',
  'fork', 'form', 'fort', 'found', 'foyer', 'frame',
  'fresh', 'frighten', 'frog', 'frown', 'fruit', 'fuel',
  'fulfill', 'function', 'funnel', 'gadget', 'gallery', 'garage',
  'garden', 'garlic', 'gate', 'gather', 'gauge', 'gear',
  'gecko', 'generate', 'gentle', 'giant', 'ginger', 'glad',
  'glass', 'glen', 'gloomy', 'glove', 'glue', 'goat',
  'goggles', 'golden', 'govern', 'gown', 'grab', 'grain',
  'grand', 'grant', 'grape', 'grasp', 'grateful', 'gravy',
  'great', 'greet', 'grin', 'grind', 'grip', 'groan',
  'grow', 'guard', 'guess', 'guide', 'guitar', 'hall',
  'hammer', 'hand', 'handle', 'hang', 'hangar', 'hanger',
  'happen', 'happy', 'harbor', 'hard', 'hare', 'harp',
  'harsh', 'harvest', 'haven', 'hawk', 'head', 'heal',
  'heap', 'hear', 'heart', 'heat', 'heel', 'helmet',
  'help', 'herb', 'hesitate', 'hidden', 'hide', 'highway',
  'hill', 'hinge', 'hire', 'hold', 'hollow', 'honest',
  'honey', 'hook', 'horse', 'hose', 'hostel', 'hotel',
  'hound', 'house', 'hover', 'humble', 'hunt', 'hurry',
  'ideal', 'identify', 'ignore', 'imagine', 'imitate', 'impress',
  'improve', 'include', 'increase', 'indicate', 'inform', 'inhabit',
  'inherit', 'initiate', 'inject', 'injure', 'inquire', 'insert',
  'insist', 'inspect', 'inspire', 'install', 'instruct', 'insult',
  'intend', 'interact', 'invade', 'invent', 'invest', 'invite',
  'involve', 'iron', 'irritate', 'island', 'ivory', 'jade',
  'jelly', 'join', 'joke', 'jolly', 'judge', 'juice',
  'jumbo', 'jump', 'junction', 'justify', 'kangaroo', 'keep',
  'ketchup', 'kettle', 'kick', 'kill', 'kind', 'kiss',
  'kitchen', 'kite', 'knee', 'kneel', 'knife', 'knit',
  'knock', 'koala', 'label', 'ladder', 'ladybug', 'lake',
  'lamb', 'lamp', 'land', 'lane', 'lantern', 'large',
  'lash', 'lasso', 'last', 'latch', 'late', 'laugh',
  'launch', 'lawn', 'lead', 'leaf', 'lean', 'leap',
  'learn', 'leash', 'leave', 'lemon', 'lemur', 'lend',
  'lens', 'lentil', 'letter', 'lettuce', 'level', 'lever',
  'license', 'lick', 'lift', 'light', 'lighten', 'like',
  'limit', 'link', 'lion', 'list', 'listen', 'live',
  'lively', 'lizard', 'llama', 'load', 'lobby', 'locate',
  'lock', 'locker', 'lodge', 'loft', 'lofty', 'lonely',
  'long', 'look', 'loom', 'loosen', 'lose', 'loud',
  'love', 'lower', 'loyal', 'lucky', 'lung', 'lynx',
  'macaroni', 'macaw', 'magnet', 'maintain', 'mallet', 'manage',
  'mango', 'mansion', 'march', 'mark', 'market', 'marrow',
  'marvel', 'mask', 'match', 'matter', 'meadow', 'meal',
  'measure', 'meat', 'meet', 'mellow', 'melon', 'melt',
  'mend', 'mention', 'merge', 'merry', 'mighty', 'migrate',
  'mild', 'milk', 'mill', 'mind', 'mine', 'mint',
  'mirror', 'mitten', 'modest', 'modify', 'mole', 'monitor',
  'moon', 'moor', 'moose', 'moth', 'mount', 'mountain',
  'mouse', 'move', 'muffin', 'multiply', 'murmur', 'museum',
  'mushroom', 'mustard', 'nail', 'name', 'napkin', 'narrate',
  'narrow', 'neat', 'need', 'needle', 'neglect', 'nerve',
  'newt', 'nimble', 'noble', 'noisy', 'noodle', 'nose',
  'note', 'notebook', 'notice', 'number', 'nutmeg', 'oatmeal',
  'obey', 'observe', 'obtain', 'occupy', 'occur', 'ocean',
  'offend', 'offer', 'office', 'olive', 'onion', 'open',
  'operate', 'orchard', 'order', 'organ', 'organize', 'outline',
  'overcome', 'overflow', 'oyster', 'pack', 'paddle', 'pail',
  'paint', 'palace', 'palm', 'pancake', 'panda', 'papaya',
  'paper', 'paprika', 'parcel', 'park', 'parrot', 'parsley',
  'pass', 'pasta', 'paste', 'pastry', 'path', 'patient',
  'patio', 'pause', 'peaceful', 'peach', 'peanut', 'pear',
  'pearl', 'pecan', 'peel', 'pencil', 'penguin', 'pepper',
  'perceive', 'perform', 'permit', 'persist', 'persuade', 'phone',
  'piano', 'pick', 'pickle', 'picture', 'pier', 'pile',
  'pillow', 'pinch', 'pipe', 'pizza', 'place', 'plain',
  'plan', 'plank', 'plant', 'plate', 'play', 'plaza',
  'plead', 'pliers', 'plot', 'plow', 'plug', 'plum',
  'plunge', 'pocket', 'point', 'polar', 'polish', 'ponder',
  'pony', 'popcorn', 'porch', 'pork', 'portray', 'pose',
  'position', 'possess', 'post', 'potato', 'pouch', 'pour',
  'practice', 'praise', 'pray', 'preach', 'predict', 'prefer',
  'prepare', 'present', 'preserve', 'press', 'pretend', 'pretzel',
  'prevent', 'print', 'proceed', 'process', 'produce', 'program',
  'progress', 'promise', 'promote', 'prompt', 'propose', 'protect',
  'protest', 'proud', 'prove', 'provide', 'publish', 'pudding',
  'pull', 'pump', 'punch', 'purchase', 'pure', 'purse',
  'pursue', 'push', 'puzzle', 'quaint', 'qualify', 'quarrel',
  'quarry', 'question', 'queue', 'quick', 'quicken', 'quiet',
  'quilt', 'quinoa', 'quit', 'rabbit', 'race', 'radish',
  'rain', 'raise', 'raisin', 'rake', 'ramp', 'ranch',
  'rapid', 'rare', 'razor', 'reach', 'react', 'read',
  'ready', 'real', 'realize', 'reason', 'rebuild', 'recall',
  'receive', 'recite', 'record', 'recover', 'recruit', 'reduce',
  'reef', 'refer', 'reflect', 'reform', 'refresh', 'refuse',
  'regard', 'register', 'regret', 'rehearse', 'reject', 'rejoice',
  'relate', 'relax', 'release', 'relieve', 'rely', 'remain',
  'remark', 'remember', 'remind', 'remove', 'renew', 'rent',
  'repair', 'repeat', 'replace', 'reply', 'report', 'request',
  'require', 'rescue', 'research', 'resemble', 'reserve', 'reside',
  'resist', 'resolve', 'resort', 'respect', 'respond', 'rest',
  'restore', 'restrict', 'retire', 'return', 'reveal', 'reverse',
  'review', 'revise', 'reward', 'ribbon', 'rice', 'rich',
  'ride', 'rigid', 'ring', 'rinse', 'ripe', 'risk',
  'river', 'rivet', 'road', 'roam', 'roar', 'roast',
  'robin', 'robust', 'rock', 'roll', 'roof', 'root',
  'rope', 'rotate', 'rough', 'round', 'royal', 'ruby',
  'rugged', 'ruin', 'rule', 'ruler', 'rush', 'saddle',
  'safe', 'sail', 'salad', 'salmon', 'salsa', 'salt',
  'salty', 'salute', 'sample', 'sand', 'sandy', 'satchel',
  'satisfy', 'sauce', 'save', 'scale', 'scan', 'scarce',
  'scarf', 'scatter', 'schedule', 'school', 'scissor', 'scold',
  'scrape', 'scratch', 'scream', 'screw', 'scrub', 'seal',
  'search', 'seat', 'secret', 'secure', 'seed', 'seek',
  'seize', 'select', 'sell', 'send', 'sense', 'separate',
  'serene', 'serve', 'settle', 'shake', 'shape', 'share',
  'shark', 'sharp', 'sharpen', 'shatter', 'shave', 'sheep',
  'shelf', 'shelter', 'shield', 'shift', 'shin', 'shine',
  'shiny', 'shiver', 'shop', 'shore', 'short', 'shoulder',
  'shovel', 'shrew', 'shrimp', 'shrink', 'shuffle', 'sidewalk',
  'sieve', 'sigh', 'sign', 'signal', 'silent', 'simple',
  'sincere', 'sing', 'sink', 'skate', 'sketch', 'skin',
  'skip', 'skull', 'skunk', 'slam', 'sled', 'sleek',
  'sleeve', 'slender', 'slide', 'slim', 'slip', 'slipper',
  'slow', 'small', 'smart', 'smash', 'smell', 'smile',
  'smoke', 'smooth', 'snail', 'snake', 'snap', 'sneeze',
  'sniff', 'snore', 'snow', 'snowy', 'soak', 'soar',
  'socket', 'soft', 'soften', 'sole', 'solid', 'solve',
  'sort', 'sound', 'soup', 'sour', 'spade', 'spanner',
  'spare', 'spark', 'sparrow', 'speak', 'specify', 'speed',
  'spell', 'spend', 'spice', 'spicy', 'spider', 'spill',
  'spin', 'spine', 'spit', 'splash', 'split', 'spoil',
  'spoon', 'spot', 'spray', 'spread', 'sprinkle', 'sprint',
  'square', 'squeeze', 'squid', 'stab', 'stack', 'stagger',
  'stain', 'stair', 'stale', 'stall', 'stallion', 'stamp',
  'stapler', 'star', 'start', 'state', 'station', 'stay',
  'steady', 'steep', 'steer', 'step', 'stern', 'stew',
  'stick', 'sticky', 'still', 'stingray', 'stir', 'stitch',
  'stone', 'stool', 'stop', 'store', 'stork', 'storm',
  'stormy', 'strap', 'street', 'stretch', 'strike', 'string',
  'stroll', 'strong', 'struggle', 'studio', 'study', 'sturdy',
  'submit', 'subtract', 'subway', 'succeed', 'suck', 'sudden',
  'suffer', 'sugar', 'suggest', 'suitcase', 'summon', 'sunny',
  'super', 'supply', 'support', 'suppose', 'surprise', 'surround',
  'suspect', 'suspend', 'swallow', 'swan', 'swap', 'sway',
  'swear', 'sweep', 'swell', 'swift', 'swim', 'swing',
  'switch', 'sword', 'syrup', 'table', 'tackle', 'taco',
  'take', 'talk', 'tall', 'tame', 'tank', 'tape',
  'taste', 'teach', 'teapot', 'tease', 'temple', 'tempt',
  'tend', 'tender', 'tense', 'tent', 'terrace', 'test',
  'thank', 'thaw', 'theater', 'thick', 'thicken', 'thin',
  'think', 'thread', 'thrive', 'throw', 'thumb', 'thunder',
  'ticket', 'tickle', 'tidy', 'tiger', 'tile', 'time',
  'timer', 'tiny', 'tire', 'toad', 'toast', 'toil',
  'tolerate', 'tomato', 'tooth', 'torch', 'tortilla', 'toss',
  'touch', 'tough', 'tour', 'towel', 'tower', 'town',
  'trace', 'track', 'trade', 'trail', 'train', 'transfer',
  'trap', 'travel', 'tray', 'treat', 'tree', 'tremble',
  'trick', 'trim', 'trip', 'tripod', 'trot', 'trouble',
  'trout', 'trowel', 'true', 'trumpet', 'trunk', 'trust',
  'tube', 'tumble', 'tunnel', 'turkey', 'turn', 'turtle',
  'tweezers', 'twinkle', 'twist', 'type', 'umbrella', 'undergo',
  'undo', 'unfold', 'unify', 'unite', 'unlock', 'unpack',
  'update', 'upgrade', 'uphold', 'utilize', 'validate', 'valley',
  'value', 'valve', 'vanilla', 'vanish', 'vary', 'vase',
  'vast', 'vault', 'vein', 'venture', 'veranda', 'verify',
  'vest', 'viaduct', 'vibrate', 'view', 'village', 'vinegar',
  'violin', 'viper', 'visit', 'voice', 'vote', 'wade',
  'waffle', 'wagon', 'wait', 'wake', 'walk', 'wall',
  'wallet', 'walrus', 'wander', 'want', 'warm', 'warn',
  'wary', 'wash', 'waste', 'watch', 'water', 'wave',
  'weak', 'wealthy', 'weigh', 'welcome', 'whale', 'wharf',
  'wheel', 'whine', 'whip', 'whirl', 'whisper', 'whistle',
  'wide', 'wild', 'wind', 'window', 'windy', 'wink',
  'wipe', 'wire', 'wise', 'wish', 'witty', 'wobble',
  'wolf', 'wonder', 'work', 'worm', 'worry', 'wrap',
  'wreck', 'wren', 'wrench', 'wrestle', 'wriggle', 'wrist',
  'write', 'yard', 'yarn', 'yawn', 'yell', 'yield',
  'yogurt', 'young', 'zany', 'zebra', 'zipper', 'zucchini',
];

/// Character classes offered for random generation.
enum CharClass {
  lower('a-z', 'abcdefghijklmnopqrstuvwxyz'),
  upper('A-Z', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
  digits('0-9', '0123456789'),
  symbols('!@#\$%^&*()-_=+[]{};:,.<>?/', r'!@#$%^&*()-_=+[]{};:,.<>?/');

  const CharClass(this.label, this.characters);

  final String label;
  final String characters;
}

/// Parameters for one generation.
class PasswordOptions {
  const PasswordOptions({
    this.style = PasswordStyle.random,
    this.length = 20,
    this.words = 6,
    this.separator = '-',
    this.includeUpper = true,
    this.includeDigits = true,
    this.includeSymbols = false,
    this.capitalizeWords = false,
  });

  final PasswordStyle style;
  final int length;
  final int words;
  final String separator;
  final bool includeUpper;
  final bool includeDigits;
  final bool includeSymbols;
  final bool capitalizeWords;

  /// The character space implied by the selected classes.
  String get alphabet {
    final buffer = StringBuffer(CharClass.lower.characters);
    if (includeUpper) buffer.write(CharClass.upper.characters);
    if (includeDigits) buffer.write(CharClass.digits.characters);
    if (includeSymbols) buffer.write(CharClass.symbols.characters);
    return buffer.toString();
  }

  /// Number of words the passphrase style can draw from.
  static int get vocabularySize => _wordlist.length;
}

/// Generates a secret using [options] and [random].
GeneratedSecret generateSecret(PasswordOptions options, {Random? random}) {
  final rng = random ?? Random.secure();
  return switch (options.style) {
    PasswordStyle.passphrase => _passphrase(options, rng),
    PasswordStyle.pin => _pin(options, rng),
    PasswordStyle.uuidToken => _token(rng),
    PasswordStyle.random => _random(options, rng),
  };
}

GeneratedSecret _passphrase(PasswordOptions options, Random rng) {
  final count = options.words.clamp(1, 16);
  final picked = <String>[
    for (var i = 0; i < count; i++) _wordlist[rng.nextInt(_wordlist.length)],
  ];
  final words = options.capitalizeWords
      ? picked.map((w) => w[0].toUpperCase() + w.substring(1)).toList()
      : picked;
  final value = words.join(options.separator);
  final bits = (log(PasswordOptions.vocabularySize) / log(2) * count).floor();
  return GeneratedSecret(
    value: value,
    bitsOfEntropy: bits,
    summary:
        '$count words from a ${PasswordOptions.vocabularySize}-word list · $bits bits',
    words: words,
  );
}

GeneratedSecret _pin(PasswordOptions options, Random rng) {
  final length = options.length.clamp(4, 12);
  final digits = List.generate(length, (_) => rng.nextInt(10)).join();
  return GeneratedSecret(
    value: digits,
    bitsOfEntropy: (log(10) / log(2) * length).floor(),
    summary: '$length digits · ${(log(10) / log(2) * length).floor()} bits',
    words: digits.split(''),
  );
}

GeneratedSecret _token(Random rng) {
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  final hex = bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final value = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  return GeneratedSecret(
    value: value,
    // 16 random bytes.
    bitsOfEntropy: 128,
    summary: '16 random bytes formatted as a UUID · 128 bits',
    words: value.split('-'),
  );
}

GeneratedSecret _random(PasswordOptions options, Random rng) {
  final length = options.length.clamp(4, 256);
  final alphabet = options.alphabet;
  final chars = List.generate(length, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
  final bits = (log(alphabet.length) / log(2) * length).floor();
  return GeneratedSecret(
    value: chars,
    bitsOfEntropy: bits,
    summary:
        '$length characters from a ${alphabet.length}-character alphabet · $bits bits',
    words: chars.split(''),
  );
}

/// Estimates how long [bits] of entropy survives against [guessesPerSecondRate]
/// guesses per second.
///
/// The arithmetic runs entirely in log10 space: `2^bits` overflows a 64-bit
/// int once bits reaches 64, which silently produced nonsense for strong
/// secrets.
String estimateCrackTime(int bits, {double guessesPerSecondRate = 1e10}) {
  if (bits <= 0) return 'instant';
  if (guessesPerSecondRate <= 0) return 'unknown';
  // log10(seconds) = bits * log10(2) - log10(guesses per second)
  final logSeconds = bits * _log10Of2 - _log10(guessesPerSecondRate);
  if (logSeconds < 0) return 'instant';
  if (logSeconds < _log10Of60) return '${_shortNum(pow(10, logSeconds))} seconds';
  if (logSeconds < _log10Of3600) {
    return '${_shortNum(pow(10, logSeconds) / 60)} minutes';
  }
  if (logSeconds < _log10Of86400) {
    return '${_shortNum(pow(10, logSeconds) / 3600)} hours';
  }
  if (logSeconds < _log10Of2592000) {
    return '${_shortNum(pow(10, logSeconds) / 86400)} days';
  }
  if (logSeconds < _log10Of31536000) {
    return '${_shortNum(pow(10, logSeconds) / 2592000)} months';
  }
  final logYears = logSeconds - _log10Of31536000;
  if (logYears < 3) return '${_shortNum(pow(10, logYears))} years';
  if (logYears < 6) return '${_shortNum(pow(10, logYears) / 1e3)} thousand years';
  if (logYears < 9) return '${_shortNum(pow(10, logYears) / 1e6)} million years';
  if (logYears < 12) return '${_shortNum(pow(10, logYears) / 1e9)} billion years';
  return 'longer than the age of the universe';
}

/// Formats a magnitude without trailing zeros, e.g. `1.8 million`.
String _shortNum(num value) {
  if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(1)} million';
  if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(1)} thousand';
  if (value >= 100) return value.round().toString();
  return value.toStringAsFixed(1);
}

const _log10Of2 = 0.30103;
const _log10Of60 = 1.7781512503836436;
const _log10Of3600 = 3.5563025007672873;
const _log10Of86400 = 5.936483839890692;
const _log10Of2592000 = 8.114632819034791;
const _log10Of31536000 = 9.497750872672563;

/// Rough offline-guess estimate against a fast hash, in guesses per second.
String estimateOfflineCrackTime(int bits, {double hashRate = 1e11}) =>
    estimateCrackTime(bits, guessesPerSecondRate: hashRate);