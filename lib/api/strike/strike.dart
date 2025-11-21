// lib/api/strike.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../components/get_request.dart';
import '../../components/headers.dart';
import '../../components/patch_request.dart';
import '../../components/post_request.dart';
import '../../components/test_ping.dart';
import '../../utils/safe_convert.dart';

class StrikeApi {
  final String _baseUrl;
  final String apiKey;

  StrikeApi()
      : _baseUrl = _getBaseUrlFromEnv(),
        apiKey = _getApiKeyFromEnv() {
    print('🌐 Strike Base URL: $_baseUrl');
  }

  static String _getApiKeyFromEnv() {
    return dotenv.env['STRIKE_API_KEY'] ?? '';
  }

  static String _getBaseUrlFromEnv() {
    return dotenv.env['STRIKE_BASE_URL'] ?? 'https://api.strike.me/v1';
  }

  Map<String, String> get _headers => getHeaders(useUserAgent: false, bearerToken: apiKey);

  final String _apiName = "strike";

  Future<dynamic> _get(String endpoint, {Map<String, String>? queryParams}) async {
    return getRequest(
      baseUrl: _baseUrl,
      endpoint: endpoint,
      queryParams: queryParams,
      headers: _headers,
      apiName: _apiName,
    );
  }

  Future<dynamic> _post(String endpoint, {Map<String, dynamic>? body}) async {
    return postRequest(
      baseUrl: _baseUrl,
      endpoint: endpoint,
      body: body,
      headers: _headers,
      apiName: _apiName,
    );
  }

  Future<dynamic> _patch(String endpoint, {Map<String, dynamic>? body}) async {
    return patchRequest(
      baseUrl: _baseUrl,
      endpoint: endpoint,
      body: body,
      headers: _headers,
      apiName: _apiName,
    );
  }

  Future<dynamic> _pingEndpoint({Map<String, String>? queryParams}) {
    return _get('/balances', queryParams: queryParams);
  }

  Future<bool> testPing() async {
    return testPingAPI(
      getFunc: _pingEndpoint,
      apiName: _apiName,
    );
  }

  // ===========================================================================
  // GESTION ROBUSTE DES QUOTES
  // ===========================================================================
// Dans lib/api/strike.dart - Améliorez la gestion des timeouts
  Future<void> attendreCompletionQuote(String quoteId, {Duration timeout = const Duration(seconds: 30)}) async {
    final start = DateTime.now();
    int attempts = 0;

    print('⏳ Attente completion quote $quoteId (timeout: ${timeout.inSeconds}s)');

    while (true) {
      attempts++;
      try {
        final quote = await getCurrencyExchangeQuote(quoteId);
        final state = quote?['state']?.toString();

        print('🔄 Vérification quote $quoteId (tentative $attempts) - état: $state');

        if (state == 'COMPLETED') {
          print('✅ Quote $quoteId complétée avec succès');
          return;
        }

        if (state == 'FAILED' || state == 'EXPIRED' || state == 'CANCELLED') {
          throw Exception('Quote $quoteId a échoué avec état: $state');
        }

        final elapsed = DateTime.now().difference(start);
        if (elapsed > timeout) {
          throw Exception('Timeout attente quote COMPLETED (id=$quoteId, état=$state, durée=${elapsed.inSeconds}s)');
        }

        // Attente progressive : 1s pour les premières tentatives, puis 2s
        final waitTime = attempts < 5 ? Duration(seconds: 1) : Duration(seconds: 2);
        await Future.delayed(waitTime);
      } catch (e) {
        print('❌ Erreur lors de la vérification de la quote $quoteId: $e');
        final elapsed = DateTime.now().difference(start);
        if (elapsed > timeout) {
          throw Exception('Timeout avec erreur pour quote $quoteId: $e');
        }
        await Future.delayed(Duration(seconds: 1));
      }
    }
  }
  // ===========================================================================
  // ENDPOINTS DE L'API
  // ===========================================================================

  Future<dynamic> getBalances() async => await _get('/balances');

  Future<Map<String, double>> getBtcAndEurAvailable() async {
    try {
      final balances = await getBalances() as List<dynamic>;

      final btc = balances.firstWhere(
            (b) => b['currency'] == 'BTC',
        orElse: () => {'currency': 'BTC', 'available': '0'},
      );
      final eur = balances.firstWhere(
            (b) => b['currency'] == 'EUR',
        orElse: () => {'currency': 'EUR', 'available': '0'},
      );

      return {
        'BTC': SafeConvert.toDouble(btc['available']),
        'EUR': SafeConvert.toDouble(eur['available']),
      };
    } catch (e) {
      print('❌ Erreur lors de la récupération des balances: $e');
      return {'BTC': 0.0, 'EUR': 0.0};
    }
  }

  Future<Map<String, dynamic>?> createCurrencyExchangeQuote(Map<String, dynamic> data) async {
    final body = {
      'sell': 'EUR',
      'buy': 'BTC',
      'amount': {
        'amount': data['amount']?.toString() ?? '0.01',
        'currency': 'EUR',
      },
      'feePolicy': 'INCLUSIVE',
    };

    // LOGIQUE DE RETRY AMÉLIORÉE
    Map<String, dynamic>? quoteResponse;
    int essais = 0;
    final int maxEssais = 3;

    while (essais < maxEssais) {
      try {
        essais++;
        print('🔄 Création de quote (tentative $essais/$maxEssais)');

        quoteResponse = await _post('/currency-exchange-quotes', body: body);

        if (quoteResponse != null) {
          final quoteId = quoteResponse['id']?.toString();
          final state = quoteResponse['state']?.toString();

          print('ℹ️ Quote créée - ID: $quoteId, État initial: $state');

          if (quoteId != null && state != null) {
            break;
          }
        }

        if (essais < maxEssais) {
          print('⏳ Nouvelle tentative dans 2 secondes...');
          await Future.delayed(Duration(seconds: 2));
        }
      } catch (e) {
        print('❌ Erreur création quote (tentative $essais): $e');
        if (essais < maxEssais) {
          await Future.delayed(Duration(seconds: 2));
        }
      }
    }

    if (quoteResponse == null) {
      throw Exception('Échec création devis après $maxEssais tentatives');
    }

    return quoteResponse;
  }

  Future<Map<String, dynamic>> executeCurrencyExchangeQuote(String quoteId) async {
    try {
      print('🔄 Exécution de la quote $quoteId...');
      final response = await _patch('/currency-exchange-quotes/$quoteId/execute');

      // L'API Strike peut renvoyer une réponse vide (204) pour l'exécution
      // Si c'est le cas, on considère que c'est un succès
      if (response == null || (response is Map && response.isEmpty)) {
        print('✅ Exécution de quote $quoteId acceptée (réponse vide)');
        return {'status': 'ACCEPTED', 'quoteId': quoteId};
      }

      print('✅ Réponse exécution quote: $response');
      return response;
    } catch (e) {
      print('❌ Erreur lors de l\'exécution de la quote $quoteId: $e');
      rethrow;
    }
  }

  Future<dynamic> getCurrencyExchangeQuote(String quoteId) async =>
      await _get('/currency-exchange-quotes/$quoteId');

  Future<dynamic> getInvoices() async => await _get('/invoices');

  Future<dynamic> createInvoice(Map<String, dynamic> data) async {
    final body = {
      'correlationId': data['correlationId'] ?? 'trade_${DateTime.now().millisecondsSinceEpoch}',
      'description': data['description'] ?? '',
      'amount': {
        'amount': data['amount']?.toString() ?? '0',
        'currency': data['currency'] ?? 'EUR',
      },
    };
    return await _post('/invoices', body: body);
  }

  Future<dynamic> getInvoice(String invoiceId) async => await _get('/invoices/$invoiceId');

  Future<dynamic> getRatesTicker() async => await _get('/rates/ticker');
}