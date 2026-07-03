import 'dart:math';

/// The word pool — identical to the website's draw.html WORDS list so app and
/// web rooms draw from the same set.
const List<String> kDrawWords = [
  'apple','house','car','tree','dog','cat','fish','bird','sun','moon',
  'star','cloud','rain','snow','fire','water','book','pen','phone','chair',
  'table','door','window','clock','lamp','bed','cup','plate','shoe','hat',
  'ball','kite','boat','train','plane','bus','bike','bridge','mountain','river',
  'ocean','beach','forest','flower','grass','butterfly','rainbow','thunder','lightning','wave',
  'pizza','cake','ice cream','banana','strawberry','watermelon','grapes','popcorn','cookie','bread',
  'guitar','piano','drum','microphone','headphones','camera','telescope','rocket','robot','diamond',
  'crown','sword','shield','castle','lighthouse','windmill','cactus','snowman','penguin','elephant',
  'giraffe','lion','tiger','monkey','panda','dolphin','shark','whale','octopus','crab',
  'spider','bee','snail','turtle','frog','duck','owl','fox','wolf','bear',
  'running','jumping','swimming','sleeping','eating','laughing','dancing','singing','flying','fishing',
  'superhero','wizard','pirate','astronaut','teacher','doctor','chef','firefighter','farmer','clown',
  'umbrella','glasses','watch','ring','key','lock','ladder','hammer','saw','scissors',
  'pencil','brush','crayon','balloon','candle','gift','ribbon','envelope','stamp','map',
  'compass','anchor','flag','tent','campfire','backpack','sandwich','donut','lollipop','cupcake',
  'cheese','egg','carrot','tomato','potato','corn','pepper','mushroom','onion','pumpkin',
  'lemon','cherry','peach','pineapple','coconut','mango','avocado','broccoli','pear','kiwi',
  'helicopter','submarine','tractor','ambulance','truck','scooter','skateboard','sailboat','canoe','jet',
  'volcano','desert','island','waterfall','cave','glacier','valley','canyon','meadow','swamp',
  'snake','lizard','dinosaur','dragon','unicorn','mermaid','ghost','alien','zombie','vampire',
  'kangaroo','koala','zebra','rhino','hippo','camel','deer','rabbit','squirrel','hedgehog',
  'parrot','peacock','flamingo','eagle','swan','rooster','chicken','goat','sheep','cow',
  'horse','pig','mouse','bat','ant','ladybug','dragonfly','grasshopper','caterpillar','worm',
  'jellyfish','starfish','seahorse','lobster','clam','coral','seaweed','pearl','treasure',
  'guitarist','painter','police','soldier','sailor','dancer','singer','magician','ninja','knight',
  'snowflake','tornado','hurricane','earthquake','sunrise','sunset','eclipse','comet','planet','galaxy',
  'igloo','pyramid','skyscraper','barn','church','stadium','library','museum','school','hospital',
  'toothbrush','soap','towel','mirror','comb','razor','bandage','thermometer','syringe','pill',
  'football','basketball','baseball','tennis','golf','bowling','hockey','volleyball','badminton','chess',
  'violin','trumpet','flute','saxophone','harp','accordion','tambourine','xylophone','banjo','cello',
  'waffle','pancake','noodles','burger','taco','sushi','pretzel','muffin','pie','jelly',
  'snowball','firework','swing','slide','seesaw','trampoline','sandcastle',
];

/// The drawing palette — same 12 colours as the website toolbar.
const List<int> kDrawColors = [
  0xFF000000, 0xFF808080, 0xFFFFFFFF, 0xFF8B4513, 0xFFFF0000, 0xFFFF6600,
  0xFFFFFF00, 0xFF00CC00, 0xFF00CCCC, 0xFF0066FF, 0xFF9900CC, 0xFFFF66CC,
];

/// Avatar colours (matches website AVATARS).
const List<int> _avatars = [
  0xFF7c3aed, 0xFF059669, 0xFF2563eb, 0xFFd97706, 0xFFdc2626, 0xFF7c3aed,
  0xFF0891b2, 0xFF9333ea, 0xFF16a34a, 0xFFea580c, 0xFF0284c7, 0xFFbe185d,
];

int drawAvatarColor(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h << 5) - h + c;
  }
  return _avatars[h.abs() % _avatars.length];
}

String wordToHint(String word) => word.replaceAll(RegExp(r'[a-zA-Z]'), '_');
String formatHint(String hint) => hint.split('').join(' ');

int levenshtein(String a, String b) {
  final m = a.length, n = b.length;
  final dp = List.generate(m + 1, (i) => List<int>.filled(n + 1, 0));
  for (var i = 0; i <= m; i++) {
    for (var j = 0; j <= n; j++) {
      dp[i][j] = i == 0 ? j : (j == 0 ? i : 0);
    }
  }
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      dp[i][j] = a[i - 1] == b[j - 1]
          ? dp[i - 1][j - 1]
          : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]].reduce(min);
    }
  }
  return dp[m][n];
}

/// Word picker. [exclude] holds words drawn this game plus the globally
/// recently-used words (last 30 days, shared with the website via the
/// `draw_recent_words` table), so a word that came up won't reappear for a
/// month anywhere. Falls back to the full pool only if too few remain.
class WordBag {
  static final _pool = kDrawWords.toSet().toList();

  static List<String> pick(int n, Iterable<String> exclude) {
    final ex = exclude.toSet();
    final avail = _pool.where((w) => !ex.contains(w)).toList()..shuffle();
    final picked = <String>[];
    for (final w in avail) {
      if (picked.length >= n) break;
      picked.add(w);
    }
    if (picked.length < n) {
      final extra = [..._pool]..shuffle();
      for (final w in extra) {
        if (picked.length >= n) break;
        if (!picked.contains(w)) picked.add(w);
      }
    }
    return picked;
  }
}

int _i(Object? v, [int d = 0]) => v is int ? v : int.tryParse('${v ?? ''}') ?? d;
bool _b(Object? v, [bool d = false]) => v is bool ? v : (v == null ? d : '$v' == 'true');
List<String> _sl(Object? v) => (v as List?)?.map((e) => '$e').toList() ?? const [];

/// A `draw_rooms` row.
class DrawRoom {
  final String roomCode;
  final String hostId;
  final String status; // lobby | word_pick | drawing | round_end | game_over
  final int roundsTotal;
  final int drawTime;
  final int maxPlayers;
  final bool isPrivate;
  final bool guestsAllowed;
  final String? currentDrawer;
  final List<String> drawOrder;
  final int drawIndex;
  final int roundCurrent;
  final List<String> wordChoices;
  final String? currentWord;
  final String? currentHint;
  final List<String> usedWords;
  final DateTime? phaseEndsAt;
  final bool standingsDone;

  const DrawRoom({
    required this.roomCode,
    required this.hostId,
    required this.status,
    required this.roundsTotal,
    required this.drawTime,
    required this.maxPlayers,
    required this.isPrivate,
    required this.guestsAllowed,
    required this.currentDrawer,
    required this.drawOrder,
    required this.drawIndex,
    required this.roundCurrent,
    required this.wordChoices,
    required this.currentWord,
    required this.currentHint,
    required this.usedWords,
    required this.phaseEndsAt,
    required this.standingsDone,
  });

  factory DrawRoom.fromMap(Map<String, dynamic> m) => DrawRoom(
        roomCode: '${m['room_code']}',
        hostId: '${m['host_id']}',
        status: '${m['status'] ?? 'lobby'}',
        roundsTotal: _i(m['rounds_total'], 3),
        drawTime: _i(m['draw_time'], 80),
        maxPlayers: _i(m['max_players'], 8),
        isPrivate: _b(m['is_private']),
        guestsAllowed: _b(m['guests_allowed'], true),
        currentDrawer: m['current_drawer'] as String?,
        drawOrder: _sl(m['draw_order']),
        drawIndex: _i(m['draw_index']),
        roundCurrent: _i(m['round_current'], 1),
        wordChoices: _sl(m['word_choices']),
        currentWord: m['current_word'] as String?,
        currentHint: m['current_hint'] as String?,
        usedWords: _sl(m['used_words']),
        phaseEndsAt: m['phase_ends_at'] != null ? DateTime.tryParse('${m['phase_ends_at']}') : null,
        standingsDone: _b(m['standings_done']),
      );
}

/// A `draw_players` row.
class DrawPlayer {
  final String playerId;
  final String playerName;
  final int score;
  final bool hasGuessed;
  final DateTime? leftAt;

  const DrawPlayer({
    required this.playerId,
    required this.playerName,
    required this.score,
    required this.hasGuessed,
    required this.leftAt,
  });

  bool get active => leftAt == null;

  factory DrawPlayer.fromMap(Map<String, dynamic> m) => DrawPlayer(
        playerId: '${m['player_id']}',
        playerName: '${m['player_name'] ?? ''}',
        score: _i(m['score']),
        hasGuessed: _b(m['has_guessed']),
        leftAt: m['left_at'] != null ? DateTime.tryParse('${m['left_at']}') : null,
      );
}

/// A `draw_chat` row.
class DrawChat {
  final String playerId;
  final String playerName;
  final String message;
  final bool isCorrect;
  const DrawChat({
    required this.playerId,
    required this.playerName,
    required this.message,
    required this.isCorrect,
  });

  factory DrawChat.fromMap(Map<String, dynamic> m) => DrawChat(
        playerId: '${m['player_id']}',
        playerName: '${m['player_name'] ?? ''}',
        message: '${m['message'] ?? ''}',
        isCorrect: _b(m['is_correct']),
      );
}
