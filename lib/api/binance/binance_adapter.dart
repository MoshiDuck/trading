// lib/api/adapters/binance_adapter.dart
import '../../components/model.dart';
import '../../utils/safe_convert.dart';

class BinanceAdapter {
  static UnifiedTicker toUnifiedTicker(Map<String, dynamic> json) {
    return UnifiedTicker(
      symbol: json['symbol']?.toString() ?? '',
      lastPrice: SafeConvert.toDouble(json['lastPrice']),
      bid: SafeConvert.toDouble(json['bidPrice']),
      ask: SafeConvert.toDouble(json['askPrice']),
      high24h: SafeConvert.toDouble(json['highPrice']),
      low24h: SafeConvert.toDouble(json['lowPrice']),
      volume24h: SafeConvert.toDouble(json['volume']),
      priceChange24h: SafeConvert.toDouble(json['priceChange']),
      priceChangePercent24h: SafeConvert.toDouble(json['priceChangePercent']),
      open24h: SafeConvert.toDouble(json['openPrice']),
      timestamp: DateTime.now(),
    );
  }

  static UnifiedOrderBook toUnifiedOrderBook(Map<String, dynamic> json) {
    final bids = (json['bids'] as List<dynamic>?)
        ?.map((bid) => UnifiedOrderBookEntry(
      price: SafeConvert.toDouble(bid[0]),
      quantity: SafeConvert.toDouble(bid[1]),
    ))
        .toList() ?? [];

    final asks = (json['asks'] as List<dynamic>?)
        ?.map((ask) => UnifiedOrderBookEntry(
      price: SafeConvert.toDouble(ask[0]),
      quantity: SafeConvert.toDouble(ask[1]),
    ))
        .toList() ?? [];

    return UnifiedOrderBook(
      bids: bids,
      asks: asks,
      timestamp: DateTime.now(),
    );
  }

  static UnifiedTrade toUnifiedTrade(Map<String, dynamic> json) {
    return UnifiedTrade(
      tradeId: json['id']?.toString() ?? '',
      price: SafeConvert.toDouble(json['price']),
      quantity: SafeConvert.toDouble(json['qty']),
      isBuyerMaker: json['isBuyerMaker'] == true,
      timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(json['time'])),
    );
  }

  static UnifiedOHLC toUnifiedOHLC(List<dynamic> kline) {
    return UnifiedOHLC(
      timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(kline[0])),
      open: SafeConvert.toDouble(kline[1]),
      high: SafeConvert.toDouble(kline[2]),
      low: SafeConvert.toDouble(kline[3]),
      close: SafeConvert.toDouble(kline[4]),
      volume: SafeConvert.toDouble(kline[5]),
    );
  }
}