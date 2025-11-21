// lib/api/binance.dart (version modifiée)
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../components/get_request.dart';
import '../../components/headers.dart';
import '../../components/model.dart';
import '../../components/test_ping.dart';
import '../../utils/safe_convert.dart';
import '../interfaces.dart';
import 'binance_adapter.dart';

class BinanceApi implements BitcoinPriceApi, BitcoinMarketApi {
  final String _baseUrl;

  BinanceApi()
      : _baseUrl = _getBaseUrlFromEnv() {
    print('🌐 Binance Base URL: $_baseUrl');
  }

  static String _getBaseUrlFromEnv() {
    return dotenv.env['BINANCE_BASE_URL'] ?? 'https://data-api.binance.vision';
  }

  final _headers = getHeaders();
  final String _apiName = "binance";

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
    return _get('/api/v3/ping', queryParams: queryParams);
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
      final response = await getPrice(symbol: 'BTCEUR');
      final priceStr = response['price']?.toString();
      return SafeConvert.toDouble(priceStr);
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
      final response = await get24hrTicker(symbol: 'BTCEUR');
      return BinanceAdapter.toUnifiedTicker(response);
    } catch (e) {
      print('❌ Erreur lors de la récupération du ticker Bitcoin: $e');
      return UnifiedTicker(
        symbol: 'BTCEUR',
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
      final response = await getDepth('BTCEUR', limit: limit);
      return BinanceAdapter.toUnifiedOrderBook(response);
    } catch (e) {
      print('❌ Erreur lors de la récupération du order book: $e');
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
      final response = await _get('/api/v3/trades', queryParams: {
        'symbol': 'BTCEUR',
        'limit': limit.toString()
      });

      if (response is! List) return [];

      return response.map<UnifiedTrade>((trade) {
        return BinanceAdapter.toUnifiedTrade(trade);
      }).toList();
    } catch (e) {
      print('❌ Erreur lors de la récupération des trades: $e');
      return [];
    }
  }

  /// Obtient les données OHLC Bitcoin unifiées
  Future<List<UnifiedOHLC>> getUnifiedBitcoinOHLC({
    required String interval,
    int limit = 100,
  }) async {
    try {
      final response = await getKlines(
        symbol: 'BTCEUR',
        interval: interval,
        limit: limit,
      );

      if (response is! List) return [];

      return response.map<UnifiedOHLC>((kline) {
        return BinanceAdapter.toUnifiedOHLC(kline);
      }).toList();
    } catch (e) {
      print('❌ Erreur lors de la récupération des données OHLC: $e');
      return [];
    }
  }

  // ===========================================================================
  // MÉTHODES ORIGINALES DE L'API (conservées pour compatibilité)
  // ===========================================================================

  Future<dynamic> getExchangeInfo({String? symbol}) async {
    final params = <String, String>{};
    if (symbol != null) params['symbol'] = symbol;
    return await _get('/api/v3/exchangeInfo', queryParams: params);
  }

  Future<dynamic> getDepth(String symbol, {int limit = 10}) async {
    final params = <String, String>{
      'symbol': symbol,
      'limit': limit.toString()
    };
    return await _get('/api/v3/depth', queryParams: params);
  }

  Future<dynamic> get24hrTicker({String? symbol}) async {
    final params = <String, String>{};
    if (symbol != null) params['symbol'] = symbol;
    return await _get('/api/v3/ticker/24hr', queryParams: params);
  }

  Future<dynamic> getPrice({String? symbol}) async {
    final params = <String, String>{};
    if (symbol != null) params['symbol'] = symbol;
    return await _get('/api/v3/ticker/price', queryParams: params);
  }

  Future<dynamic> getKlines({
    required String symbol,
    required String interval,
    int limit = 100,
  }) async {
    final params = <String, String>{
      'symbol': symbol,
      'interval': interval,
      'limit': limit.toString(),
    };
    return await _get('/api/v3/klines', queryParams: params);
  }

  /// Obtient le prix Bitcoin formaté
  Future<String> getFormattedBitcoinPrice() async {
    try {
      final price = await getBitcoinPrice();
      return 'BTC/EUR: €${price.toStringAsFixed(2)}';
    } catch (e) {
      return 'Erreur: $e';
    }
  }
}