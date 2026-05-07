
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which URLs the user has already opened, so the editor can render
/// visited links in a different colour (purple vs. blue).
///
/// Backed by [SharedPreferences].  Falls back silently to an in-memory set
/// when the platform does not support persistence (e.g. unit tests).
///
/// ## Setup
/// Call [LinkVisitStore.instance.init()] once during app start-up (e.g. in
/// `main()` after `WidgetsFlutterBinding.ensureInitialized()`).  The widget
/// works without this call — links just won't survive app restarts until
/// init() has been awaited at least once.
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await LinkVisitStore.instance.init();
///   runApp(const MyApp());
/// }
/// ```
class LinkVisitStore {
  LinkVisitStore._();

  static const String _kPrefKey = 'intrst_rte_visited_links_v1';
  static const int _kMaxStored = 500; // cap to avoid unbounded growth

  static final LinkVisitStore instance = LinkVisitStore._();

  SharedPreferences? _prefs;
  final Set<String> _visited = {};
  bool _initialised = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Loads persisted data.  Safe to call multiple times.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      final saved = _prefs!.getStringList(_kPrefKey) ?? <String>[];
      _visited.addAll(saved);
    } catch (_) {
      // In-memory fallback — visits won't persist across restarts but the
      // editor still functions correctly within a session.
    }
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  /// Returns `true` if [url] (after normalisation) has been marked visited.
  bool hasVisited(String url) => _visited.contains(_key(url));

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Records [url] as visited and persists the change.
  Future<void> markVisited(String url) async {
    if (_visited.add(_key(url))) {
      await _persist();
    }
  }

  /// Removes [url] from the visited set.
  Future<void> unmarkVisited(String url) async {
    if (_visited.remove(_key(url))) {
      await _persist();
    }
  }

  /// Clears all visited data (useful for logout / account switch).
  Future<void> clear() async {
    _visited.clear();
    await _prefs?.remove(_kPrefKey);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Canonical key: lower-cased, trimmed URL.
  String _key(String url) => url.trim().toLowerCase();

  Future<void> _persist() async {
    if (_prefs == null) return;
    final list = _visited.toList();
    // Trim to cap if needed.
    final trimmed = list.length > _kMaxStored
        ? list.sublist(list.length - _kMaxStored)
        : list;
    await _prefs!.setStringList(_kPrefKey, trimmed);
  }
}