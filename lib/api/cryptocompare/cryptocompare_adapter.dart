// lib/api/adapters/cryptocompare_adapter.dart
import '../../components/model.dart';
import '../../utils/safe_convert.dart';

class CryptoCompareAdapter {
  static UnifiedTicker toUnifiedTicker(Map<String, dynamic> json) {
    return UnifiedTicker(
      symbol: 'BTCEUR',
      lastPrice: SafeConvert.toDouble(json['PRICE']),
      bid: SafeConvert.toDouble(json['BID']),
      ask: SafeConvert.toDouble(json['ASK']),
      high24h: SafeConvert.toDouble(json['HIGH24HOUR']),
      low24h: SafeConvert.toDouble(json['LOW24HOUR']),
      volume24h: SafeConvert.toDouble(json['VOLUME24HOURTO']),
      priceChange24h: SafeConvert.toDouble(json['CHANGE24HOUR']),
      priceChangePercent24h: SafeConvert.toDouble(json['CHANGEPCT24HOUR']),
      open24h: SafeConvert.toDouble(json['OPEN24HOUR']),
      marketCap: SafeConvert.toDouble(json['MKTCAP']), // ← AJOUT IMPORTANT
      timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(json['LASTUPDATE']) * 1000),
    );
  }

  static UnifiedOHLC toUnifiedOHLC(Map<String, dynamic> json) {
    return UnifiedOHLC(
      timestamp: DateTime.fromMillisecondsSinceEpoch(SafeConvert.toInt(json['time']) * 1000),
      open: SafeConvert.toDouble(json['open']),
      high: SafeConvert.toDouble(json['high']),
      low: SafeConvert.toDouble(json['low']),
      close: SafeConvert.toDouble(json['close']),
      volume: SafeConvert.toDouble(json['volumeto']),
    );
  }

  static UnifiedInstrument toUnifiedInstrument(Map<String, dynamic> json) {
    return UnifiedInstrument(
      symbol: json['symbol']?.toString() ?? '',
      baseCurrency: 'BTC',
      quoteCurrency: 'EUR',
      tickSize: 0.01,
      lotSize: 0.0001,
      minSize: 0.0001,
      status: 'ACTIVE',
    );
  }
}