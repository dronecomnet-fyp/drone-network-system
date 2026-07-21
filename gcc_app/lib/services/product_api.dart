/// ProductApi (M7c): fetches product specs for a unit ID from the hosted
/// product site's Supabase backend, over plain HTTPS, ONLINE ONLY (at HQ
/// during planning). The result is cached into the mission file so the
/// field stays fully offline: once a unit's specs are cached, they resolve
/// with no network.
///
/// Uses Supabase's auto-generated PostgREST endpoint with the public anon
/// key; row-level security on the project restricts the anon role to
/// reading products and units (see website/supabase/schema.sql). No secret
/// is embedded: the anon key is public by design.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../state/mission_state.dart';

class ProductApiException implements Exception {
  final String message;
  ProductApiException(this.message);
  @override
  String toString() => message;
}

class ProductApi {
  final String baseUrl; // e.g. https://xyz.supabase.co
  final String anonKey;
  final http.Client _http;

  ProductApi({required this.baseUrl, required this.anonKey, http.Client? client})
      : _http = client ?? http.Client();

  /// Look up a unit by its ID and return its product info, or throw a
  /// ProductApiException with a human message. Joins the unit to its
  /// product row (PostgREST embed) in one request.
  Future<ProductInfo> fetchUnit(String unitId) async {
    final id = unitId.trim();
    if (id.isEmpty) throw ProductApiException('Enter a unit ID first');
    if (baseUrl.isEmpty || anonKey.isEmpty) {
      throw ProductApiException(
          'Product site not configured (set the URL and anon key in Settings)');
    }

    final uri = Uri.parse(
        '$baseUrl/rest/v1/units?unit_id=eq.${Uri.encodeComponent(id)}'
        '&select=unit_id,status,products(model_no,name,specs)');
    http.Response resp;
    try {
      resp = await _http.get(uri, headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));
    } on SocketException {
      throw ProductApiException(
          'Offline: spec fetch needs internet (HQ phase). Enter specs '
          'manually or attach a cached unit.');
    } on HttpException catch (e) {
      throw ProductApiException('Network error: ${e.message}');
    } catch (e) {
      throw ProductApiException('Could not reach the product site: $e');
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw ProductApiException('Rejected by the product site: check the '
          'anon key and that RLS allows anon reads');
    }
    if (resp.statusCode != 200) {
      throw ProductApiException('Product site error ${resp.statusCode}');
    }

    final rows = jsonDecode(resp.body);
    if (rows is! List || rows.isEmpty) {
      throw ProductApiException('No unit "$id" found on the product site');
    }
    final row = rows.first as Map<String, dynamic>;
    final product = row['products'];
    if (product is! Map<String, dynamic>) {
      throw ProductApiException('Unit "$id" has no product record');
    }
    return ProductInfo(
      modelNo: (product['model_no'] ?? '') as String,
      name: (product['name'] ?? '') as String,
      specs: (product['specs'] as Map<String, dynamic>? ?? {}),
      fetchedAt: DateTime.now().toUtc().toIso8601String(),
      source: 'site',
    );
  }

  void close() => _http.close();
}
