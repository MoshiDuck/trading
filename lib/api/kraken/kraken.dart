// lib/api/kraken.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../components/get_request.dart';
import '../../components/headers.dart';
import '../../components/model.dart';
import '../../components/test_ping.dart';
import '../../utils/safe_convert.dart';
import '../interfaces.dart';
import 'kraken_adapter.dart';

/// Client Kraken API spécialisé Bitcoin uniquement avec modèles unifiés
class KrakenApi implements BitcoinPriceApi, BitcoinMarketApi {
  final String _baseUrl;

  KrakenApi()
      : _baseUrl = _getBaseUrlFromEnv() {
    print('🌐 Kraken Base URL: $_baseUrl');
  }

  static String _getBaseUrlFromEnv() {
    return dotenv.env['KRAKEN_BASE_URL'] ?? 'https://api.kraken.com/0/public';
  }

  final _headers = getHeaders();

  // ===========================================================================
  // GESTION DES RÉPONSES HTTP
  // ===========================================================================

  final String _apiName = "kraken";

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
    return _get('/Time', queryParams: queryParams);
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

  /// Obtient le ticker Bitcoin unifié
  Future<UnifiedTicker> getUnifiedBitcoinTicker() async {
    try {
      final response = await _get('/Ticker', queryParams: {'pair': 'XBTEUR'});
      final pairData = response['result']?['XXBTZEUR'];
      if (pairData == null) throw Exception('Paire XBTEUR non trouvée');

      return KrakenAdapter.toUnifiedTicker(pairData);
    } catch (e) {
      print('❌ Erreur lors de la récupération du ticker Bitcoin: $e');
      return UnifiedTicker(
        symbol: 'XBTEUR',
        lastPrice: 0.0,
        bid: 0.0,
        ask: 0.0,
        high24h: 0.0,
        low24h: 0.0,
        volume24h: 0.0,
        priceChange24h: 0.0,
        priceChangePercent24h: 0.0,
        open24h: 0.0,
        timestamp: DateTime.now(),
      );
    }
  }

  /// Obtient le order book Bitcoin unifié
  Future<UnifiedOrderBook> getUnifiedBitcoinOrderBook({int limit = 10}) async {
    try {
      final response = await _get('/Depth', queryParams: {
        'pair': 'XBTEUR',
        'count': limit.toString()
      });
      final pairData = response['result']?['XXBTZEUR'];
      if (pairData == null) throw Exception('Paire XBTEUR non trouvée');

      return KrakenAdapter.toUnifiedOrderBook(pairData);
    } catch (e) {
      print('❌ Erreur lors de la récupération du order book Bitcoin: $e');
      return UnifiedOrderBook(
        bids: [],
        asks: [],
        timestamp: DateTime.now(),
      );
    }
  }

  /// Obtient les trades Bitcoin unifiés
  Future<List<UnifiedTrade>> getUnifiedBitcoinTrades({int limit = 10}) async {
    try {
      final response = await _get('/Trades', queryParams: {
        'pair': 'XBTEUR',
        'count': limit.toString()
      });

      final List<dynamic> trades = response['result']?['XXBTZEUR'] ?? [];

      return trades.map<UnifiedTrade>((trade) {
        return KrakenAdapter.toUnifiedTrade(trade);
      }).toList();
    } catch (e) {
      print('❌ Erreur lors de la récupération des trades Bitcoin: $e');
      return [];
    }
  }

  /// Obtient l'heure du serveur Kraken
  Future<dynamic> getServerTime() async {
    return await _get('/Time');
  }

  // ===========================================================================
  // MÉTHODES DE FORMATAGE
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
      return '24h Range: €${ticker.low24h.toStringAsFixed(2)} - €${ticker.high24h.toStringAsFixed(2)} | Volume: ${ticker.formattedVolume}';
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  /// Obtient les données du order book formatées
  Future<String> getFormattedOrderBook() async {
    try {
      final orderBook = await getUnifiedBitcoinOrderBook(limit: 5);
      return 'Bids: ${orderBook.bids.length} | Asks: ${orderBook.asks.length} | Spread: €${orderBook.spread.toStringAsFixed(2)}';
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  /// Obtient l'heure du serveur formatée
  Future<String> getFormattedServerTime() async {
    try {
      final serverTime = await getServerTime();
      final timestamp = SafeConvert.toInt(serverTime['result']?['unixtime']);
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      return 'Server Time: ${dateTime.toLocal().toString()}';
    } catch (e) {
      return 'Erreur: $e';
    }
  }
}