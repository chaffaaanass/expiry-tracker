import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product_model.dart';
import '../models/purchase_order_model.dart';

/// Global singleton — use OdooService.instance everywhere.
///
/// KEY FIX: Odoo uses session cookies (session_id) to maintain state.
/// Every request after authenticate() MUST send back the cookie
/// Odoo sets in the response — otherwise Odoo treats every call as a
/// new anonymous session and returns "session expired".
class OdooService {
  OdooService._();
  static final OdooService instance = OdooService._();

  // ─── Internal state ───────────────────────────────────────────────────────

  String _baseUrl  = '';
  String _database = '';
  String _username = '';
  String _password = '';
  int?   _uid;

  /// The session_id cookie Odoo returns after authenticate().
  /// We send it back as a Cookie header on every subsequent request.
  String? _sessionId;

  bool get isConfigured    => _baseUrl.isNotEmpty && _username.isNotEmpty;
  bool get isAuthenticated => _uid != null && _sessionId != null;

  // ─── Setup ────────────────────────────────────────────────────────────────

  void configure({
    required String baseUrl,
    required String database,
    required String username,
    required String password,
  }) {
    _baseUrl  = baseUrl.replaceAll(RegExp(r'/$'), '');
    _database = database;
    _username = username;
    _password = password;
    _uid       = null;
    _sessionId = null; // force full re-auth on next call
  }

  static Future<bool> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final url  = prefs.getString('odoo_url')  ?? '';
    final db   = prefs.getString('odoo_db')   ?? '';
    final user = prefs.getString('odoo_user') ?? '';
    final pass = prefs.getString('odoo_pass') ?? '';

    if (url.isEmpty || user.isEmpty) return false;

    OdooService.instance.configure(
      baseUrl:  url,
      database: db,
      username: user,
      password: pass,
    );
    return true;
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('odoo_url',  _baseUrl);
    await prefs.setString('odoo_db',   _database);
    await prefs.setString('odoo_user', _username);
    await prefs.setString('odoo_pass', _password);
    await prefs.setBool('is_logged_in', true);
  }

  Future<void> logout() async {
    _uid       = null;
    _sessionId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
  }

  // ─── Cookie helpers ───────────────────────────────────────────────────────

  /// Extracts session_id from Set-Cookie response header.
  String? _extractSessionId(http.Response response) {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null) return null;

    // Cookie header looks like:
    // session_id=abc123xyz; HttpOnly; Path=/
    final match = RegExp(r'session_id=([^;]+)').firstMatch(setCookie);
    return match?.group(1);
  }

  /// Returns headers that include the session cookie if we have one.
  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_sessionId != null) {
      headers['Cookie'] = 'session_id=$_sessionId';
    }
    return headers;
  }

  // ─── Authentication ───────────────────────────────────────────────────────

  Future<int> authenticate() async {
    if (!isConfigured) {
      throw OdooException('OdooService non configuré.');
    }

    final response = await http
        .post(
      Uri.parse('$_baseUrl/web/session/authenticate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id':      1,
        'method':  'call',
        'params':  {
          'db':       _database,
          'login':    _username,
          'password': _password,
        },
      }),
    )
        .timeout(
      const Duration(seconds: 15),
      onTimeout: () =>
      throw OdooException('Timeout — vérifiez votre réseau'),
    );

    if (response.statusCode != 200) {
      throw OdooException('Erreur réseau: ${response.statusCode}');
    }

    // ── Extract and store the session cookie ──────────────────────────────
    final sessionId = _extractSessionId(response);
    if (sessionId != null) {
      _sessionId = sessionId;
    }

    final data = jsonDecode(response.body);

    if (data['error'] != null) {
      final msg = data['error']['data']?['message'] ?? 'Authentification échouée';
      throw OdooException(msg);
    }

    final uid = data['result']?['uid'];
    if (uid == null || uid == false) {
      throw OdooException('Identifiant ou mot de passe incorrect');
    }

    _uid = uid as int;
    return _uid!;
  }

  Future<bool> ping() async {
    try {
      await authenticate();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Generic JSON-RPC call ────────────────────────────────────────────────

  String get _rpcUrl => '$_baseUrl/web/dataset/call_kw';

  Future<dynamic> _call({
    required String model,
    required String method,
    required List<dynamic> args,
    Map<String, dynamic>? kwargs,
    bool isRetry = false,
  }) async {
    // Authenticate first if we don't have a session yet
    if (_uid == null || _sessionId == null) await authenticate();

    final response = await http
        .post(
      Uri.parse(_rpcUrl),
      // ── Send session cookie so Odoo recognises the session ──────────
      headers: _headers,
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id':      1,
        'method':  'call',
        'params':  {
          'model':  model,
          'method': method,
          'args':   args,
          'kwargs': {
            'context': {
              'lang': 'fr_FR',
              'uid':  _uid,
            },
            ...?kwargs,
          },
        },
      }),
    )
        .timeout(
      const Duration(seconds: 20),
      onTimeout: () =>
      throw OdooException('Timeout sur $model/$method'),
    );

    // Refresh cookie if Odoo rotates it
    final newSession = _extractSessionId(response);
    if (newSession != null) _sessionId = newSession;

    final data = jsonDecode(response.body);

    if (data['error'] != null) {
      final code    = data['error']['code'];
      final message = data['error']['data']?['message'] ??
          data['error']['message'] ??
          'Erreur Odoo';

      final isSessionError = code == 100 ||
          message.toLowerCase().contains('session') ||
          message.toLowerCase().contains('access denied') ||
          message.toLowerCase().contains('not logged');

      if (isSessionError && !isRetry) {
        // Full re-auth — get a fresh session cookie
        _uid       = null;
        _sessionId = null;
        await authenticate();
        return _call(
          model:    model,
          method:   method,
          args:     args,
          kwargs:   kwargs,
          isRetry: true,
        );
      }

      throw OdooException(message);
    }

    return data['result'];
  }

  // ─── Products ─────────────────────────────────────────────────────────────

  Future<List<OdooProduct>> fetchProducts() async {
    final ids = await _call(
      model:  'product.product',
      method: 'search',
      args: [
        [
          ['active', '=', true],
          ['type', 'in', ['product', 'consu']],
        ]
      ],
      kwargs: {'limit': 500},
    );

    if ((ids as List).isEmpty) return [];

    final records = await _call(
      model:  'product.product',
      method: 'read',
      args:   [ids],
      kwargs: {
        'fields': ['id', 'name', 'default_code', 'categ_id', 'uom_id'],
      },
    );

    return (records as List).map((r) => OdooProduct.fromJson(r)).toList();
  }

  // ─── Purchase Orders ──────────────────────────────────────────────────────

  Future<List<PurchaseOrder>> fetchNewPurchaseOrders({
    DateTime? sinceDate,
    List<int> excludeIds = const [],
  }) async {
    final domain = <dynamic>[
      ['state', 'in', ['purchase', 'done']],
    ];

    if (sinceDate != null) {
      domain.add([
        'date_approve',
        '>=',
        sinceDate.toIso8601String().substring(0, 19),
      ]);
    }

    final ids = await _call(
      model:  'purchase.order',
      method: 'search',
      args:   [domain],
      kwargs: {'limit': 100},
    );

    final newIds = (ids as List)
        .map((id) => id as int)
        .where((id) => !excludeIds.contains(id))
        .toList();

    if (newIds.isEmpty) return [];

    final records = await _call(
      model:  'purchase.order',
      method: 'read',
      args:   [newIds],
      kwargs: {
        'fields': [
          'id', 'name', 'partner_id',
          'date_approve', 'order_line', 'state',
        ],
      },
    );

    final orders = <PurchaseOrder>[];
    for (final record in records as List) {
      final lineIds = List<int>.from(record['order_line'] ?? []);
      final lines   = await _fetchOrderLines(lineIds);
      orders.add(PurchaseOrder.fromJson(record, lines));
    }
    return orders;
  }

  Future<List<PurchaseOrderLine>> _fetchOrderLines(List<int> ids) async {
    if (ids.isEmpty) return [];

    final records = await _call(
      model:  'purchase.order.line',
      method: 'read',
      args:   [ids],
      kwargs: {
        'fields': [
          'id', 'product_id', 'product_qty', 'qty_received', 'price_unit',
        ],
      },
    );

    return (records as List)
        .map((r) => PurchaseOrderLine.fromJson(r))
        .toList();
  }

  Future<List<PurchaseOrder>> fetchRFQs() async {
    final ids = await _call(
      model:  'purchase.order',
      method: 'search',
      args: [
        [
          ['state', 'in', ['draft', 'sent']],
        ]
      ],
    );

    if ((ids as List).isEmpty) return [];

    final records = await _call(
      model:  'purchase.order',
      method: 'read',
      args:   [ids],
      kwargs: {
        'fields': ['id', 'name', 'partner_id', 'date_order', 'state'],
      },
    );

    return (records as List)
        .map((r) => PurchaseOrder.fromJson(r, []))
        .toList();
  }
}

// ─── Exception ────────────────────────────────────────────────────────────────

class OdooException implements Exception {
  final String message;
  OdooException(this.message);

  @override
  String toString() => 'OdooException: $message';
}