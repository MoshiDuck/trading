import 'package:http/http.dart' as http;
import 'handle_response.dart';

/// Effectue une requête GET générique vers une API.
/// [baseUrl] : L'URL de base de l'API (ex. "https://api.binance.com").
/// [endpoint] : Le chemin de l'endpoint à appeler (ex. "/api/v3/ping").
/// [queryParams] : Paramètres GET optionnels sous forme de map (ex. {"symbol": "BTCUSD"}).
/// [headers] : Headers HTTP optionnels pour la requête.
/// [apiName] : Nom de l'API utilisé pour la gestion spécifique des erreurs et logs.
Future<dynamic> getRequest({
  required String baseUrl,
  required String endpoint,
  Map<String, String>? queryParams,
  Map<String, String>? headers,
  required String apiName,
}) async {
  final uri = Uri.parse('$baseUrl$endpoint').replace(queryParameters: queryParams);

  try {
    final response = await http.get(uri, headers: headers).timeout(
      const Duration(seconds: 10),
    );

    return handleResponse(response, apiName: apiName);
  } catch (e) {
    rethrow;
  }
}
