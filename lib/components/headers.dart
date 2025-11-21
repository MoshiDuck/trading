// lib/api/headers.dart

/// Génère des headers HTTP standards pour les requêtes API
/// [useJson] : inclure 'Content-Type: application/json' (default true)
/// [useUserAgent] : inclure 'User-Agent: Flutter Crypto App' (default true)
/// [bearerToken] : token pour Authorization Bearer (optionnel)
Map<String, String> getHeaders({
  bool useJson = true,
  bool useUserAgent = true,
  String? bearerToken,
}) {
  final headers = <String, String>{
    'Accept': 'application/json',
  };

  if (useJson) {
    headers['Content-Type'] = 'application/json';
  }

  if (useUserAgent) {
    headers['User-Agent'] = 'Flutter Crypto App';
  }

  if (bearerToken != null && bearerToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $bearerToken';
  }

  return headers;
}
