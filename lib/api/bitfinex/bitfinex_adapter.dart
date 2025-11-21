// lib/api/adapters/bitfinex_adapter.dart

import '../../components/model.dart';
import '../../utils/safe_convert.dart';

class BitfinexAdapter {
  static UnifiedTicker toUnifiedTicker(List<dynamic> array) {
    if (array.isEmpty) {
      return UnifiedTicker(
        symbol: 'tBTCEUR',
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

    return UnifiedTicker(
      symbol: 'tBTCEUR',
      lastPrice: SafeConvert.toDouble(array[6]),
      bid: SafeConvert.toDouble(array[0]),
      ask: SafeConvert.toDouble(array[2]),
      high24h: SafeConvert.toDouble(array[8]),
      low24h: SafeConvert.toDouble(array[9]),
      volume24h: SafeConvert.toDouble(array[7]),
      priceChange24h: SafeConvert.toDouble(array[4]),
      priceChangePercent24h: SafeConvert.toDouble(array[5]) * 100,
      open24h: SafeConvert.toDouble(array[6]) - SafeConvert.toDouble(array[4]),
      timestamp: DateTime.now(),
    );
  }

  static UnifiedOrderBook toUnifiedOrderBook(List<dynamic> array) {
    final bids = <UnifiedOrderBookEntry>[];
    final asks = <UnifiedOrderBookEntry>[];

    for (var item in array) {
      if (item is List && item.length >= 3) {
        final price = SafeConvert.toDouble(item[0]);
        final count = SafeConvert.toInt(item[1]);
        final amount = SafeConvert.toDouble(item[2]);

        final entry = UnifiedOrderBookEntry(
          price: price,
          quantity: amount.abs(),
          count: count,
        );

        if (amount > 0) {
          bids.add(entry);
        } else {
          asks.add(entry);
        }
      }
    }

    bids.sort((a, b) => b.price.compareTo(a.price));
    asks.sort((a, b) => a.price.compareTo(b.price));

    return UnifiedOrderBook(
      bids: bids,
      asks: asks,
      timestamp: DateTime.now(),
    );
  }

  static UnifiedTrade toUnifiedTrade(List<dynamic> array) {
    return UnifiedTrade(
      tradeId: SafeConvert.toInt(array[0]).toString(),
      price: SafeConvert.toDouble(array[3]),
      quantity: SafeConvert.toDouble(array[2]).abs(),
      isBuyerMaker: SafeConvert.toDouble(array[2]) < 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(array[1])),
    );
  }

  static UnifiedOHLC toUnifiedOHLC(List<dynamic> array) {
    return UnifiedOHLC(
      timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(array[0])),
      open: SafeConvert.toDouble(array[1]),
      high: SafeConvert.toDouble(array[3]),
      low: SafeConvert.toDouble(array[4]),
      close: SafeConvert.toDouble(array[2]),
      volume: SafeConvert.toDouble(array[5]),
    );
  }
}