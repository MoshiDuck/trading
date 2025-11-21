// lib/api/okx.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../components/get_request.dart';
import '../../components/headers.dart';
import '../../components/model.dart';
import '../../components/test_ping.dart';
import '../interfaces.dart';
import 'okx_adapter.dart';

/// Client OKX API spécialisé Bitcoin uniquement avec modèles unifiés
class OkxApi implements BitcoinPriceApi, BitcoinMarketApi {
  final String _baseUrl;

  OkxApi()
      : _baseUrl = _getBaseUrlFromEnv() {
    print('🌐 OKX Base URL: $_baseUrl');
  }

  static String _getBaseUrlFromEnv() {
    return dotenv.env['OKX_BASE_URL'] ?? 'https://www.okx.com/api/v5';
  }

  final _headers = getHeaders();

  // ===========================================================================
  // GESTION DES RÉPONSES HTTP
  // ===========================================================================

  final String _apiName = "okx";

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
    return _get('/system/status', queryParams: queryParams);
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
      final response = await _get('/market/ticker', queryParams: {'instId': 'BTC-EUR'});
      final data = response['data']?[0];
      if (data == null) throw Exception('Données ticker non trouvées');

      return OkxAdapter.toUnifiedTicker(data);
    } catch (e) {
      print('❌ Erreur lors de la récupération du ticker Bitcoin: $e');
      return UnifiedTicker(
        symbol: 'BTC-EUR',
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
      final response = await _get('/market/books', queryParams: {
        'instId': 'BTC-EUR',
        'sz': limit.toString()
      });
      final data = response['data']?[0];
      if (data == null) throw Exception('Données order book non trouvées');

      return OkxAdapter.toUnifiedOrderBook(data);
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
      final response = await _get('/market/trades', queryParams: {
        'instId': 'BTC-EUR',
        'limit': limit.toString()
      });
      final List<dynamic> data = response['data'] ?? [];
      return data.map((item) => OkxAdapter.toUnifiedTrade(item)).toList();
    } catch (e) {
      print('❌ Erreur lors de la récupération des trades Bitcoin: $e');
      return [];
    }
  }

  /// Obtient les données OHLC Bitcoin unifiées
  Future<List<UnifiedOHLC>> getUnifiedBitcoinOHLC({
    String interval = '1H',
    int limit = 24,
  }) async {
    try {
      final response = await _get('/market/candles', queryParams: {
        'instId': 'BTC-EUR',
        'bar': interval,
        'limit': limit.toString()
      });
      final List<dynamic> data = response['data'] ?? [];
      return data.map((item) => OkxAdapter.toUnifiedOHLC(item)).toList();
    } catch (e) {
      print('❌ Erreur lors de la récupération des données OHLC Bitcoin: $e');
      return [];
    }
  }

  /// Obtient les informations sur les instruments Bitcoin unifiées
  Future<UnifiedInstrument> getUnifiedBitcoinInstrument() async {
    try {
      final response = await _get('/public/instruments', queryParams: {
        'instType': 'SPOT',
        'instId': 'BTC-EUR'
      });
      final data = response['data']?[0];
      if (data == null) throw Exception('Données instrument non trouvées');

      return OkxAdapter.toUnifiedInstrument(data);
    } catch (e) {
      print('❌ Erreur lors de la récupération des informations instrument Bitcoin: $e');
      return UnifiedInstrument(
        symbol: 'BTC-EUR',
        baseCurrency: 'BTC',
        quoteCurrency: 'EUR',
        tickSize: 0.0,
        lotSize: 0.0,
        minSize: 0.0,
        status: 'unknown',
      );
    }
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
      return '24h High: €${ticker.high24h.toStringAsFixed(2)} | 24h Low: €${ticker.low24h.toStringAsFixed(2)} | 24h Vol: ${ticker.formattedVolume}';
    } catch (e) {
      return 'Erreur: $e';
    }
  }
}