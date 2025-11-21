/// Fonction générique pour tester la connectivité d'une API
/// [getFunc] : fonction GET à appeler (ex: _get ou getRequest)
/// [apiName] : nom de l'API pour les logs et la gestion d'erreurs
Future<bool> testPingAPI({
  required Future<dynamic> Function({Map<String, String>? queryParams}) getFunc,
  String apiName = 'API',
  Map<String, String>? queryParams,
}) async {
  try {
    await getFunc(queryParams: queryParams);
    return true;
  } catch (e) {
    print('❌ $apiName API ping failed: $e');
    return false;
  }
}
