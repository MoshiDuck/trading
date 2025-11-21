// Todo : lib/api/interfaces.dart
abstract class BitcoinPriceApi {
  Future<double> getBitcoinPrice();
}

abstract class BitcoinMarketApi {
  Future<dynamic> getBitcoinMarketData();
}

abstract class BitcoinHistoricalApi {
  Future<dynamic> getBitcoinHistoricalData({int? days, int? limit});
}