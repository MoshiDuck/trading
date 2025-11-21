// lib/api/adapters/okx_adapter.dart

import '../../components/model.dart';
import '../../utils/safe_convert.dart';

class OkxAdapter {
  static UnifiedTicker toUnifiedTicker(Map<String, dynamic> json) {
    return UnifiedTicker(
      symbol: json['instId']?.toString() ?? '',
      lastPrice: SafeConvert.toDouble(json['last']),
      bid: SafeConvert.toDouble(json['bidPx']),
      ask: SafeConvert.toDouble(json['askPx']),
      high24h: SafeConvert.toDouble(json['high24h']),
      low24h: SafeConvert.toDouble(json['low24h']),
      volume24h: SafeConvert.toDouble(json['vol24h']),
      priceChange24h: SafeConvert.toDouble(json['change24h']),
      priceChangePercent24h: SafeConvert.toDouble(json['changePercent24h']),
      open24h: SafeConvert.toDouble(json['open24h']),
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
      tradeId: json['tradeId']?.toString() ?? '',
      price: SafeConvert.toDouble(json['px']),
      quantity: SafeConvert.toDouble(json['sz']),
      isBuyerMaker: json['side']?.toString().toLowerCase() == 'sell',
      timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(json['ts'])),
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

  static UnifiedInstrument toUnifiedInstrument(Map<String, dynamic> json) {
    return UnifiedInstrument(
      symbol: json['instId']?.toString() ?? '',
      baseCurrency: json['baseCcy']?.toString() ?? '',
      quoteCurrency: json['quoteCcy']?.toString() ?? '',
      tickSize: SafeConvert.toDouble(json['tickSz']),
      lotSize: SafeConvert.toDouble(json['lotSz']),
      minSize: SafeConvert.toDouble(json['minSz']),
      status: json['state']?.toString() ?? '',
    );
  }
}