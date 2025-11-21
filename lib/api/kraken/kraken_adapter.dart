import '../../components/model.dart';
import '../../utils/safe_convert.dart';

class KrakenAdapter {
  static UnifiedTicker toUnifiedTicker(Map<String, dynamic> json) {
    try {
      // Safe extraction with proper type checking
      final lastTrade = _safeExtractPrice(json['c']);
      final bid = _safeExtractPrice(json['b']);
      final ask = _safeExtractPrice(json['a']);

      // Extract highs and lows safely
      final high24h = _safeExtractPrice(json['h'], isArray: true, index: 1);
      final low24h = _safeExtractPrice(json['l'], isArray: true, index: 1);
      final volume24h = _safeExtractPrice(json['v'], isArray: true, index: 1);
      final openPrice = _safeExtractPrice(json['o'], isArray: true, index: 0);

      // Calculate price changes
      final priceChange24h = lastTrade - openPrice;
      final priceChangePercent24h = openPrice != 0 ? (priceChange24h / openPrice) * 100 : 0.0;

      return UnifiedTicker(
        symbol: 'XBTEUR',
        lastPrice: lastTrade,
        bid: bid,
        ask: ask,
        high24h: high24h,
        low24h: low24h,
        volume24h: volume24h,
        priceChange24h: priceChange24h,
        priceChangePercent24h: priceChangePercent24h,
        open24h: openPrice,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      print('❌ Erreur dans KrakenAdapter.toUnifiedTicker: $e ');
      print('❌ Données reçues: $json');
      return _createFallbackTicker();
    }
  }

  /// Safe method to extract prices from Kraken response
  static double _safeExtractPrice(dynamic data, {bool isArray = true, int index = 0}) {
    try {
      if (data == null) return 0.0;

      if (isArray) {
        if (data is List) {
          if (data.length > index) {
            return SafeConvert.toDouble(data[index]);
          }
        } else if (data is String) {
          // Handle case where we get a string instead of array
          return SafeConvert.toDouble(data);
        }
      } else {
        if (data is List && data.isNotEmpty) {
          return SafeConvert.toDouble(data[0]);
        } else if (data is String) {
          return SafeConvert.toDouble(data);
        }
      }
      return 0.0;
    } catch (e) {
      print('⚠️ Erreur extraction prix Kraken: $e - données: $data');
      return 0.0;
    }
  }

  static UnifiedOrderBook toUnifiedOrderBook(Map<String, dynamic> json) {
    try {
      final bids = _safeExtractOrderBookEntries(json['bids']);
      final asks = _safeExtractOrderBookEntries(json['asks']);

      return UnifiedOrderBook(
        bids: bids,
        asks: asks,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      print('❌ Erreur dans KrakenAdapter.toUnifiedOrderBook: $e');
      return UnifiedOrderBook(bids: [], asks: [], timestamp: DateTime.now());
    }
  }

  static List<UnifiedOrderBookEntry> _safeExtractOrderBookEntries(dynamic entries) {
    try {
      if (entries is! List) return [];

      return entries.map<UnifiedOrderBookEntry>((entry) {
        if (entry is List && entry.length >= 2) {
          return UnifiedOrderBookEntry(
            price: SafeConvert.toDouble(entry[0]),
            quantity: SafeConvert.toDouble(entry[1]),
          );
        }
        return UnifiedOrderBookEntry(price: 0.0, quantity: 0.0);
      }).where((entry) => entry.price > 0 && entry.quantity > 0).toList();
    } catch (e) {
      print('⚠️ Erreur extraction order book entries: $e');
      return [];
    }
  }

  static UnifiedTrade toUnifiedTrade(List<dynamic> trade) {
    try {
      if (trade.length < 4) {
        throw Exception('Format de trade invalide');
      }

      return UnifiedTrade(
        tradeId: trade[2]?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        price: SafeConvert.toDouble(trade[0]),
        quantity: SafeConvert.toDouble(trade[1]),
        isBuyerMaker: trade[3]?.toString().toLowerCase() == 's',
        timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(trade[2]) * 1000),
      );
    } catch (e) {
      print('❌ Erreur dans KrakenAdapter.toUnifiedTrade: $e');
      return UnifiedTrade(
        tradeId: DateTime.now().millisecondsSinceEpoch.toString(),
        price: 0.0,
        quantity: 0.0,
        isBuyerMaker: false,
        timestamp: DateTime.now(),
      );
    }
  }

  static UnifiedTicker _createFallbackTicker() {
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