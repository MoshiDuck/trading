// lib/api/bitstamp.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../components/get_request.dart';
import '../../components/headers.dart';
import '../../components/model.dart';
import '../../components/test_ping.dart';
import '../interfaces.dart';
import 'bitstamp_adapter.dart';

/// Client Bitstamp API spécialisé Bitcoin uniquement
class BitstampApi implements BitcoinPriceApi, BitcoinMarketApi {
  final String _baseUrl;

  BitstampApi()
      : _baseUrl = _getBaseUrlFromEnv() {
    print('🌐 Bitstamp Base URL: $_baseUrl');
  }

  static String _getBaseUrlFromEnv() {
    return dotenv.env['BITSTAMP_BASE_URL'] ?? 'https://www.bitstamp.net/api/v2';
  }

  final _headers = getHeaders();

  // ===========================================================================
  // GESTION DES RÉPONSES HTTP
  // ===========================================================================

  final String _apiName = "bitstamp";

  Future<dynamic> _get(String endpoint, {Map<String, String>? queryParams}) async {
    return getRequest(
      baseUrl: _baseUrl,
      endpoint: endpoint,
      queryParams: queryParams,
      headers: _headers,
      apiName: _apiName,
    );
  }

  Future<dynamic> _pingEndpoint({Map<String, String>? queryParams}) {
    return _get('/ticker/btceur/', queryParams: queryParams);
  }

  Future<bool> testPing() async {
    return testPingAPI(
      getFunc: _pingEndpoint,
      apiName: _apiName,
    );
  }

  // ===========================================================================
  // MÉTHODES UTILITAIRES POUR BITCOIN AVEC MODÈLES UNIFIÉS
  // ===========================================================================

  @override
  Future<double> getBitcoinPrice() async {
    try {
      final ticker = await getUnifiedBitcoinTicker();
      return ticker.lastPrice;
    } catch (e) {
      print('❌ Erreur lors de la récupération du prix Bitcoin: $e');
      return 0.0;
    }
  }

  /// Obtient le ticker Bitcoin unifié
  Future<UnifiedTicker> getUnifiedBitcoinTicker() async {
    try {
      final response = await _get('/ticker/btceur/');
      return BitstampAdapter.toUnifiedTicker(response);
    } catch (e) {
      print('❌ Erreur lors de la récupération du ticker Bitcoin: $e');
      return BitstampAdapter.toUnifiedTicker({});
    }
  }

  @override
  Future<Map<String, dynamic>> getBitcoinMarketData() async {
    try {
      final ticker = await getUnifiedBitcoinTicker();
      return {
        'currentPrice': ticker.lastPrice,
        'volume': ticker.volume24h,
        'high24h': ticker.high24h,
        'low24h': ticker.low24h,
        'priceChange24h': ticker.priceChange24h,
        'priceChangePercentage24h': ticker.priceChangePercent24h,
      };
    } catch (e) {
      print('❌ Erreur lors de la récupération des données de marché: $e');
      return {
        'currentPrice': 0.0,
        'volume': 0.0,
        'high24h': 0.0,
        'low24h': 0.0,
        'priceChange24h': 0.0,
        'priceChangePercentage24h': 0.0,
      };
    }
  }

  /// Obtient le order book Bitcoin unifié
  Future<UnifiedOrderBook> getUnifiedBitcoinOrderBook() async {
    try {
      final response = await _get('/order_book/btceur/');
      return BitstampAdapter.toUnifiedOrderBook(response);
    } catch (e) {
      print('❌ Erreur lors de la récupération du order book Bitcoin: $e');
      return UnifiedOrderBook(bids: [], asks: [], timestamp: DateTime.now());
    }
  }

  /// Obtient les trades récents Bitcoin unifiés
  Future<List<UnifiedTrade>> getUnifiedBitcoinTrades() async {
    try {
      final response = await _get('/transactions/btceur/');
      final List<dynamic> data = response is List ? response : [];
      return data.take(10).map((item) => BitstampAdapter.toUnifiedTrade(item)).toList();
    } catch (e) {
      print('❌ Erreur lors de la récupération des trades Bitcoin: $e');
      return [];
    }
  }

  /// Obtient les données OHLC pour Bitcoin unifiées
  Future<List<UnifiedOHLC>> getUnifiedBitcoinOHLC({int step = 3600, int limit = 24}) async {
    try {
      final response = await _get('/ohlc/btceur/', queryParams: {
        'step': step.toString(),
        'limit': limit.toString()
      });

      if (response is! Map<String, dynamic> || response['data'] == null) {
        throw Exception('Format de réponse invalide');
      }

      final data = response['data']['ohlc'] as List<dynamic>? ?? [];
      return data.map<UnifiedOHLC>((item) => BitstampAdapter.toUnifiedOHLC(item)).toList();
    } catch (e) {
      print('❌ Erreur lors de la récupération des données OHLC Bitcoin: $e');
      return [];
    }
  }

  /// Obtient les paires de trading disponibles unifiées
  Future<List<UnifiedInstrument>> getUnifiedTradingPairs() async {
    try {
      final response = await _get('/trading-pairs-info/');
      final List<dynamic> data = response is List ? response : [];
      return data.take(5).map((item) => BitstampAdapter.toUnifiedInstrument(item)).toList();
    } catch (e) {
      print('❌ Erreur lors de la récupération des paires de trading: $e');
      return [];
    }
  }

  // ===========================================================================
  // MÉTHODES DE COMPATIBILITÉ (pour éviter de casser le code existant)
  // ===========================================================================

  /// Obtient le ticker Bitcoin (ancienne méthode - dépréciée)
  @Deprecated('Utilisez getUnifiedBitcoinTicker() à la place')
  Future<Map<String, dynamic>> getBitcoinTicker() async {
    try {
      final unifiedTicker = await getUnifiedBitcoinTicker();
      return {
        'last': unifiedTicker.lastPrice,
        'high': unifiedTicker.high24h,
        'low': unifiedTicker.low24h,
        'vwap': 0.0, // Non disponible dans le modèle unifié
        'volume': unifiedTicker.volume24h,
        'bid': unifiedTicker.bid,
        'ask': unifiedTicker.ask,
        'open': unifiedTicker.open24h,
        'timestamp': unifiedTicker.timestamp.millisecondsSinceEpoch ~/ 1000,
      };
    } catch (e) {
      print('❌ Erreur lors de la récupération du ticker Bitcoin: $e');
      return {
        'last': 0.0,
        'high': 0.0,
        'low': 0.0,
        'vwap': 0.0,
        'volume': 0.0,
        'bid': 0.0,
        'ask': 0.0,
        'open': 0.0,
        'timestamp': 0,
      };
    }
  }

  // ===========================================================================
  // MÉTHODES FORMATTÉES
  // ===========================================================================

  /// Obtient le prix Bitcoin formaté
  Future<String> getFormattedBitcoinPrice() async {
    try {
      final ticker = await getUnifiedBitcoinTicker();
      return 'BTC/EUR: €${ticker.lastPrice.toStringAsFixed(2)} (${ticker.priceChangePercent24h.toStringAsFixed(2)}%)';
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  /// Obtient les données de marché formatées
  Future<String> getFormattedMarketData() async {
    try {
      final ticker = await getUnifiedBitcoinTicker();
      return 'High: €${ticker.high24h.toStringAsFixed(2)} | Low: €${ticker.low24h.toStringAsFixed(2)} | Volume: ${ticker.formattedVolume}';
    } catch (e) {
      return 'Erreur: $e';
    }
  }
}

// Exception personnalisée pour Bitstamp
class BitstampApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  BitstampApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() {
    return 'BitstampApiException: $message';
  }
}