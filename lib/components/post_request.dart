import 'dart:convert';
import 'package:http/http.dart' as http;
import 'handle_response.dart';

/// Fonction POST générique
/// [baseUrl] : URL de base
/// [endpoint] : endpoint à appeler
/// [body] : corps JSON optionnel
/// [headers] : headers optionnels
/// [apiName] : nom de l'API pour les logs et la gestion des erreurs
Future<dynamic> postRequest({
  required String baseUrl,
  required String endpoint,
  Map<String, dynamic>? body,
  Map<String, String>? headers,
  required String apiName,
}) async {
  final uri = Uri.parse('$baseUrl$endpoint');

  try {
    final response = await http
        .post(
      uri,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    )
        .timeout(const Duration(seconds: 10));

    return handleResponse(response, apiName: apiName);
  } catch (e) {
    rethrow;
  }
}
