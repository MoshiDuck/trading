// lib/api/adapters/bitstamp_adapter.dart

import '../../components/model.dart';
import '../../utils/safe_convert.dart';

class BitstampAdapter {
  static UnifiedTicker toUnifiedTicker(Map<String, dynamic> json) {
    final last = SafeConvert.toDouble(json['last']);
    final open = SafeConvert.toDouble(json['open']);

    return UnifiedTicker(
      symbol: 'BTCEUR',
      lastPrice: last,
      bid: SafeConvert.toDouble(json['bid']),
      ask: SafeConvert.toDouble(json['ask']),
      high24h: SafeConvert.toDouble(json['high']),
      low24h: SafeConvert.toDouble(json['low']),
      volume24h: SafeConvert.toDouble(json['volume']),
      priceChange24h: last - open,
      priceChangePercent24h: open != 0 ? ((last - open) / open) * 100 : 0,
      open24h: open,
      timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(json['timestamp']) * 1000),
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
      timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(json['timestamp']) * 1000),
    );
  }

  static UnifiedTrade toUnifiedTrade(Map<String, dynamic> json) {
    return UnifiedTrade(
      tradeId: SafeConvert.toInt(json['tid']).toString(),
      price: SafeConvert.toDouble(json['price']),
      quantity: SafeConvert.toDouble(json['amount']),
      isBuyerMaker: json['type'] == 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(json['date']) * 1000),
    );
  }

  static UnifiedOHLC toUnifiedOHLC(Map<String, dynamic> json) {
    return UnifiedOHLC(
      timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(json['timestamp']) * 1000),
      open: SafeConvert.toDouble(json['open']),
      high: SafeConvert.toDouble(json['high']),
      low: SafeConvert.toDouble(json['low']),
      close: SafeConvert.toDouble(json['close']),
      volume: SafeConvert.toDouble(json['volume']),
    );
  }

  static UnifiedInstrument toUnifiedInstrument(Map<String, dynamic> json) {
    return UnifiedInstrument(
      symbol: json['name']?.toString() ?? '',
      baseCurrency: json['base_currency']?.toString() ?? '',
      quoteCurrency: json['quote_currency']?.toString() ?? '',
      tickSize: 0.01, // Valeur par défaut
      lotSize: 0.0001, // Valeur par défaut
      minSize: 0.0001, // Valeur par défaut
      status: SafeConvert.toInt(json['trading']) == 1 ? 'ACTIVE' : 'INACTIVE',
    );
  }
}