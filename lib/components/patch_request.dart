// Dans le fichier patch_request.dart - Améliorez la gestion des réponses
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'handle_response.dart';

/// Fonction PATCH générique avec meilleure gestion des réponses vides
Future<dynamic> patchRequest({
  required String baseUrl,
  required String endpoint,
  Map<String, dynamic>? body,
  Map<String, String>? headers,
  required String apiName,
}) async {
  final uri = Uri.parse('$baseUrl$endpoint');

  print('🔄 PATCH Request: $uri');
  if (body != null) {
    print('📦 Body: $body');
  }

  try {
    final response = await http
        .patch(
      uri,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    )
        .timeout(const Duration(seconds: 15));

    print('📨 PATCH Response: ${response.statusCode} - ${response.body}');

    // Gestion spéciale pour les réponses vides (204 No Content)
    if (response.statusCode == 204) {
      print('ℹ️ Réponse 204 (No Content) - considérée comme succès');
      return {};
    }

    return handleResponse(response, apiName: apiName);
  } catch (e) {
    print('❌ Erreur PATCH $apiName: $e');
    rethrow;
  }
}