// lib/api/bitfinex.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../components/get_request.dart';
import '../../components/headers.dart';
import '../../components/model.dart';
import '../../components/test_ping.dart';
import '../../utils/safe_convert.dart';
import '../interfaces.dart';
import 'bitfinex_adapter.dart';

/// Client Bitfinex API spécialisé Bitcoin uniquement
class BitfinexApi implements BitcoinPriceApi, BitcoinMarketApi {
  final String _baseUrl;

  BitfinexApi()
      : _baseUrl = _getBaseUrlFromEnv() {
    print('🌐 Bitfinex Base URL: $_baseUrl');
  }

  static String _getBaseUrlFromEnv() {
    return dotenv.env['BITFINEX_BASE_URL'] ?? 'https://api-pub.bitfinex.com/v2';
  }

  final _headers = getHeaders();

  // ===========================================================================
  // GESTION DES RÉPONSES HTTP
  // ===========================================================================

  final String _apiName = "bitfinex";

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
    return _get('/platform/status', queryParams: queryParams);
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
      final response = await _get('/ticker/tBTCEUR');
      if (response is! List || response.isEmpty) throw Exception('Format de réponse invalide');

      return BitfinexAdapter.toUnifiedTicker(response);
    } catch (e) {
      print('❌ Erreur lors de la récupération du ticker Bitcoin: $e');
      return BitfinexAdapter.toUnifiedTicker([]);
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
  Future<UnifiedOrderBook> getUnifiedBitcoinOrderBook({String precision = 'P0', int len = 25}) async {
    try {
      final response = await _get('/book/tBTCEUR/$precision', queryParams: {
        'len': len.toString()
      });
      if (response is! List) throw Exception('Format de réponse invalide');

      return BitfinexAdapter.toUnifiedOrderBook(response);
    } catch (e) {
      print('❌ Erreur lors de la récupération du order book Bitcoin: $e');
      return UnifiedOrderBook(bids: [], asks: [], timestamp: DateTime.now());
    }
  }

  /// Obtient les trades récents Bitcoin unifiés
  Future<List<UnifiedTrade>> getUnifiedBitcoinTrades({int limit = 10}) async {
    try {
      final response = await _get('/trades/tBTCEUR/hist', queryParams: {
        'limit': limit.toString()
      });
      if (response is! List) throw Exception('Format de réponse invalide');

      return response.map((item) => BitfinexAdapter.toUnifiedTrade(item)).toList();
    } catch (e) {
      print('❌ Erreur lors de la récupération des trades Bitcoin: $e');
      return [];
    }
  }

  /// Obtient les données OHLC pour Bitcoin unifiées
  Future<List<UnifiedOHLC>> getUnifiedBitcoinOHLC({String timeframe = '1m', int limit = 24}) async {
    try {
      final response = await _get('/candles/trade:${timeframe}:tBTCEUR/hist', queryParams: {
        'limit': limit.toString()
      });
      if (response is! List) throw Exception('Format de réponse invalide');

      return response.map((item) => BitfinexAdapter.toUnifiedOHLC(item)).toList();
    } catch (e) {
      print('❌ Erreur lors de la récupération des données OHLC Bitcoin: $e');
      return [];
    }
  }

  /// Obtient les paires de trading disponibles
  Future<List<String>> getTradingPairs() async {
    try {
      final response = await _get('/conf/pub:list:pair:exchange');
      if (response is! List || response.isEmpty) throw Exception('Format de réponse invalide');

      final pairs = List<String>.from(response[0]);
      return pairs.where((pair) => pair.contains('BTC')).take(5).toList();
    } catch (e) {
      print('❌ Erreur lors de la récupération des paires de trading: $e');
      return [];
    }
  }

  /// Obtient les statistiques de trading
  Future<Map<String, dynamic>> getBitcoinStats({String timeframe = '1m'}) async {
    try {
      final response = await _get('/stats1/tBTCEUR.${timeframe}:1m:tBTCEUR/last');
      if (response is! List || response.isEmpty) throw Exception('Format de réponse invalide');

      return {
        'value': SafeConvert.toDouble(response[0]),
        'period': SafeConvert.toInt(response[1]),
      };
    } catch (e) {
      print('❌ Erreur lors de la récupération des statistiques Bitcoin: $e');
      return {'value': 0.0, 'period': 0};
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
        'lastPrice': unifiedTicker.lastPrice,
        'bid': unifiedTicker.bid,
        'ask': unifiedTicker.ask,
        'high': unifiedTicker.high24h,
        'low': unifiedTicker.low24h,
        'volume': unifiedTicker.volume24h,
        'dailyChange': unifiedTicker.priceChange24h,
        'dailyChangePercent': unifiedTicker.priceChangePercent24h / 100,
      };
    } catch (e) {
      print('❌ Erreur lors de la récupération du ticker Bitcoin: $e');
      return {
        'lastPrice': 0.0,
        'bid': 0.0,
        'ask': 0.0,
        'high': 0.0,
        'low': 0.0,
        'volume': 0.0,
        'dailyChange': 0.0,
        'dailyChangePercent': 0.0,
      };
    }
  }

  /// Obtient le order book Bitcoin (ancienne méthode - dépréciée)
  @Deprecated('Utilisez getUnifiedBitcoinOrderBook() à la place')
  Future<Map<String, dynamic>> getBitcoinOrderBook({String precision = 'P0', int len = 25}) async {
    try {
      final unifiedOrderBook = await getUnifiedBitcoinOrderBook(precision: precision, len: len);
      return {
        'bids': unifiedOrderBook.bids.map((entry) => [entry.price.toString(), entry.quantity.toString()]).toList(),
        'asks': unifiedOrderBook.asks.map((entry) => [entry.price.toString(), entry.quantity.toString()]).toList(),
      };
    } catch (e) {
      print('❌ Erreur lors de la récupération du order book Bitcoin: $e');
      return {'bids': [], 'asks': []};
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
      return '24h High: €${ticker.high24h.toStringAsFixed(2)} | 24h Low: €${ticker.low24h.toStringAsFixed(2)} | 24h Vol: ${ticker.formattedVolume}';
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  /// Obtient les données du order book formatées
  Future<String> getFormattedOrderBook() async {
    try {
      final orderBook = await getUnifiedBitcoinOrderBook(len: 10);
      return 'Bids: ${orderBook.bids.length} | Asks: ${orderBook.asks.length} | Spread: €${orderBook.spread.toStringAsFixed(2)}';
    } catch (e) {
      return 'Erreur: $e';
    }
  }
}

// Exception personnalisée pour Bitfinex
class BitfinexApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  BitfinexApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() {
    return 'BitfinexApiException: $message';
  }
}