// lib/api/cryptocompare.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../components/get_request.dart';
import '../../components/headers.dart';
import '../../components/model.dart';
import '../../components/test_ping.dart';
import '../../utils/safe_convert.dart';
import '../interfaces.dart';
import 'cryptocompare_adapter.dart';

/// Client CryptoCompare API spécialisé Bitcoin uniquement
class CryptoCompareApi implements BitcoinPriceApi, BitcoinMarketApi, BitcoinHistoricalApi {
  final String _baseUrl;
  final String? apiKey;

  CryptoCompareApi()
      : _baseUrl = _getBaseUrlFromEnv(),
        apiKey = _getApiKeyFromEnv() {
    print('🌐 CryptoCompare Base URL: $_baseUrl');
    print(
      '🔑 CryptoCompare API Key: ${apiKey != null ? '✅ Present' : '❌ Missing'}',
    );
  }

  static String _getBaseUrlFromEnv() {
    return dotenv.env['CRYPTOCOMPARE_BASE_URL'] ??
        'https://min-api.cryptocompare.com/data';
  }

  static String? _getApiKeyFromEnv() {
    return dotenv.env['CRYPTOCOMPARE_API_KEY'];
  }

  Map<String, String> get _headers => getHeaders(bearerToken: apiKey);

  // ===========================================================================
  // GESTION DES RÉPONSES HTTP
  // ===========================================================================
  final String _apiName = "cryptocompare";

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
    return _get('/price?fsym=BTC&tsyms=EUR', queryParams: queryParams);
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
      final response = await _get(
        '/price',
        queryParams: {'fsym': 'BTC', 'tsyms': 'EUR'},
      );
      final price = SafeConvert.toDouble(response['EUR']);
      if (price == 0) {
        throw Exception('Prix Bitcoin non trouvé');
      }
      return price;
    } catch (e) {
      print('❌ Erreur lors de la récupération du prix Bitcoin: $e');
      return 0.0;
    }
  }

  /// Obtient le ticker Bitcoin unifié
  Future<UnifiedTicker> getUnifiedBitcoinTicker() async {
    try {
      final response = await _get(
        '/pricemultifull',
        queryParams: {'fsyms': 'BTC', 'tsyms': 'EUR'},
      );

      final rawData = response['RAW']?['BTC']?['EUR'];
      if (rawData == null) throw Exception('Données BTC non trouvées');

      return CryptoCompareAdapter.toUnifiedTicker(rawData);
    } catch (e) {
      print('❌ Erreur lors de la récupération du ticker Bitcoin: $e');
      return CryptoCompareAdapter.toUnifiedTicker({});
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
        'marketCap': ticker.marketCap,
      };
    } catch (e) {
      print('❌ Erreur lors de la récupération des données de marché Bitcoin: $e');
      return {
        'currentPrice': 0.0,
        'volume': 0.0,
        'high24h': 0.0,
        'low24h': 0.0,
        'priceChange24h': 0.0,
        'priceChangePercentage24h': 0.0,
        'marketCap': 0.0,
      };
    }
  }

  @override
  Future<Map<String, dynamic>> getBitcoinHistoricalData({
    int? days,
    int? limit,
  }) async {
    try {
      final actualLimit = limit ?? 10;
      final response = await _get(
        '/v2/histoday',
        queryParams: {
          'fsym': 'BTC',
          'tsym': 'EUR',
          'limit': actualLimit.toString(),
        },
      );

      final data = response['Data']?['Data'];
      if (data == null) throw Exception('Données historiques non trouvées');

      final historicalData = data.map<UnifiedOHLC>((point) {
        return CryptoCompareAdapter.toUnifiedOHLC(point);
      }).toList();

      return {
        'prices': historicalData,
        'timeFrom': historicalData.first.timestamp.millisecondsSinceEpoch,
        'timeTo': historicalData.last.timestamp.millisecondsSinceEpoch,
        'limit': actualLimit,
      };
    } catch (e) {
      print('❌ Erreur lors de la récupération des données historiques Bitcoin: $e');
      return {
        'prices': [],
        'timeFrom': 0,
        'timeTo': 0,
        'limit': 0,
      };
    }
  }

  /// Obtient les paires de trading principales pour Bitcoin unifiées
  Future<List<UnifiedInstrument>> getUnifiedBitcoinTradingPairs() async {
    try {
      final response = await _get('/pairs', queryParams: {'fsym': 'BTC'});

      final data = response['Data'];
      if (data == null) throw Exception('Données des paires non trouvées');

      final pairs = <UnifiedInstrument>[];
      for (var pair in data.take(5)) {
        pairs.add(CryptoCompareAdapter.toUnifiedInstrument(pair));
      }
      return pairs;
    } catch (e) {
      print('❌ Erreur lors de la récupération des paires de trading Bitcoin: $e');
      return [];
    }
  }

  // ===========================================================================
  // MÉTHODES DE COMPATIBILITÉ (pour éviter de casser le code existant)
  // ===========================================================================

  /// Obtient les données de marché (ancienne méthode - dépréciée)
  @Deprecated('Utilisez getUnifiedBitcoinTicker() à la place')
  Future<Map<String, dynamic>> getBitcoinMarketDataLegacy() async {
    try {
      final response = await _get(
        '/pricemultifull',
        queryParams: {'fsyms': 'BTC', 'tsyms': 'EUR'},
      );

      final rawData = response['RAW']?['BTC']?['EUR'];
      if (rawData == null) throw Exception('Données BTC non trouvées');

      return {
        'currentPrice': SafeConvert.toDouble(rawData['PRICE']),
        'volume': SafeConvert.toDouble(rawData['VOLUME24HOURTO']),
        'high24h': SafeConvert.toDouble(rawData['HIGH24HOUR']),
        'low24h': SafeConvert.toDouble(rawData['LOW24HOUR']),
        'priceChange24h': SafeConvert.toDouble(rawData['CHANGE24HOUR']),
        'priceChangePercentage24h': SafeConvert.toDouble(rawData['CHANGEPCT24HOUR']),
        'marketCap': SafeConvert.toDouble(rawData['MKTCAP']),
      };
    } catch (e) {
      print('❌ Erreur lors de la récupération des données de marché Bitcoin: $e');
      return {
        'currentPrice': 0.0,
        'volume': 0.0,
        'high24h': 0.0,
        'low24h': 0.0,
        'priceChange24h': 0.0,
        'priceChangePercentage24h': 0.0,
        'marketCap': 0.0,
      };
    }
  }

  // ===========================================================================
  // MÉTHODES FORMATTÉES
  // ===========================================================================

  /// Obtient le prix Bitcoin formaté
  Future<String> getFormattedBitcoinPrice() async {
    try {
      final price = await getBitcoinPrice();
      final marketDataMap = await getBitcoinMarketData();
      final change = SafeConvert.toDouble(marketDataMap['priceChangePercentage24h']);
      return 'BTC/EUR: €${price.toStringAsFixed(2)} (${change.toStringAsFixed(2)}%)';
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  /// Obtient les données de marché formatées
  Future<String> getFormattedMarketData() async {
    try {
      final marketDataMap = await getBitcoinMarketData();
      final change = SafeConvert.toDouble(marketDataMap['priceChangePercentage24h']);
      final volume = SafeConvert.toDouble(marketDataMap['volume']);

      String formatVolume(double value) {
        if (value >= 1e9) return '€${(value / 1e9).toStringAsFixed(2)}B';
        if (value >= 1e6) return '€${(value / 1e6).toStringAsFixed(2)}M';
        return '€${value.toStringAsFixed(2)}';
      }

      return '24h Change: ${change.toStringAsFixed(2)}% | Volume: ${formatVolume(volume)}';
    } catch (e) {
      return 'Erreur: $e';
    }
  }

  Future<String> getFormattedHistoricalData() async {
    try {
      final historicalDataMap = await getBitcoinHistoricalData(limit: 7);
      final prices = historicalDataMap['prices'] as List<UnifiedOHLC>? ?? [];

      if (prices.isEmpty) return 'No historical data available';

      final firstClose = prices.first.close;
      final lastClose = prices.last.close;

      if (firstClose == 0.0 || lastClose == 0.0) {
        return 'Incomplete historical data';
      }

      final totalChange = lastClose - firstClose;
      final totalChangePercent = firstClose != 0
          ? (totalChange / firstClose) * 100
          : 0;

      return '7-Day Performance: ${totalChangePercent.toStringAsFixed(2)}% (${totalChange >= 0 ? '+' : ''}€${totalChange.toStringAsFixed(2)})';
    } catch (e) {
      return 'Erreur: $e';
    }
  }
}

// Exception personnalisée pour CryptoCompare
class CryptoCompareApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  CryptoCompareApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() {
    return 'CryptoCompareApiException: $message';
  }
}