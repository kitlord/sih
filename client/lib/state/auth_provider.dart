import 'package:flutter/foundation.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../graphql/client.dart';
import '../graphql/mutations.dart';

const String _tokenKey = 'hc_token';
const String _userKey = 'hc_user';

/// Holds the signed-in user's JWT + profile, persisted across page reloads
/// via shared_preferences. Login/register/logout all live here so every
/// screen shares one source of truth for "who am I".
class AuthProvider extends ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _user;
  bool _restored = false;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isAuthenticated => _token != null && _user != null;
  String? get role => _user?['role'] as String?;
  bool get restored => _restored;

  Future<void> restoreFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final username = prefs.getString(_userKey);
    if (_token != null && username != null) {
      // Enough locally-cached identity to route correctly on reload without
      // an extra round-trip; the JWT itself is still what's actually
      // checked server-side on every subsequent GraphQL call, so a stale
      // token just surfaces as an auth error on first use, not silently.
      _user = {'username': username, 'role': prefs.getString('hc_role')};
    }
    _restored = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token == null || _user == null) {
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
      await prefs.remove('hc_role');
    } else {
      await prefs.setString(_tokenKey, _token!);
      await prefs.setString(_userKey, _user!['username'] as String);
      await prefs.setString('hc_role', _user!['role'] as String);
    }
  }

  Future<void> login(GraphQLClient client, String username, String password) async {
    final result = await client.mutate(MutationOptions(
      document: gql(loginMutation),
      variables: {'username': username, 'password': password},
    ));
    if (result.hasException) {
      throw Exception(friendlyGraphQLError(result.exception));
    }
    _applyAuthPayload(result.data!['login'] as Map<String, dynamic>);
    await _persist();
  }

  Future<void> register(GraphQLClient client, String username, String email, String password) async {
    final result = await client.mutate(MutationOptions(
      document: gql(registerMutation),
      variables: {'username': username, 'email': email, 'password': password},
    ));
    if (result.hasException) {
      throw Exception(friendlyGraphQLError(result.exception));
    }
    _applyAuthPayload(result.data!['register'] as Map<String, dynamic>);
    await _persist();
  }

  void _applyAuthPayload(Map<String, dynamic> payload) {
    _token = payload['token'] as String;
    _user = Map<String, dynamic>.from(payload['user'] as Map);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    await _persist();
    notifyListeners();
  }
}
