import 'dart:convert';
import 'package:http/http.dart' as http;

/// Exceptions pour chaque API
class BinanceApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  BinanceApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'BinanceApiException: $message';
}

class CryptoCompareApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  CryptoCompareApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'CryptoCompareApiException: $message';
}

class KrakenApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  KrakenApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'KrakenApiException: $message';
}

class OkxApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  OkxApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'OkxApiException: $message';
}

class StrikeApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  StrikeApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'StrikeApiException: $message';
}

class BitstampApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  BitstampApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'BitstampApiException: $message';
}

class BitfinexApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  BitfinexApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => 'BitfinexApiException: $message';
}

/// Fonction générique pour gérer les réponses HTTP
/// [apiName] : Nom de l'API pour gérer les erreurs spécifiques
dynamic handleResponse(http.Response response, {required String apiName}) {
  final statusOk = response.statusCode >= 200 && response.statusCode < 300;
  dynamic decoded = response.body.isNotEmpty ? jsonDecode(response.body) : null;

  if (statusOk) {
    switch (apiName.toLowerCase()) {
      case 'binance':
      case 'strike':
        return decoded;
      case 'cryptocompare':
        if (decoded != null && decoded['Response'] == 'Error') {
          throw CryptoCompareApiException(
            decoded['Message'] ?? 'Unknown error',
            statusCode: response.statusCode,
            responseBody: response.body,
          );
        }
        return decoded;
      case 'kraken':
        if (decoded != null && decoded['error'] is List && decoded['error'].isNotEmpty) {
          throw KrakenApiException(
            decoded['error'].join(', '),
            statusCode: response.statusCode,
            responseBody: response.body,
          );
        }
        return decoded;
      case 'okx':
        if (decoded != null && decoded['code'] != '0') {
          throw OkxApiException(
            decoded['msg'] ?? 'Unknown error',
            statusCode: response.statusCode,
            responseBody: response.body,
          );
        }
        return decoded;
      case 'bitstamp':
        if (decoded != null && decoded['error'] != null) {
          throw BitstampApiException(
            decoded['error'] ?? 'Unknown error',
            statusCode: response.statusCode,
            responseBody: response.body,
          );
        }
        return decoded;
      case 'bitfinex':
        if (decoded is List && decoded.isNotEmpty && decoded[0] is String && decoded[0].contains('error')) {
          throw BitfinexApiException(
            decoded[0] ?? 'Unknown error',
            statusCode: response.statusCode,
            responseBody: response.body,
          );
        }
        return decoded;
      default:
        return decoded;
    }
  } else {
    final errorMsg = decoded != null
        ? (decoded['msg'] ?? decoded['error'] ?? response.body)
        : response.body;

    switch (apiName.toLowerCase()) {
      case 'binance':
        throw BinanceApiException(errorMsg, statusCode: response.statusCode, responseBody: response.body);
      case 'cryptocompare':
        throw CryptoCompareApiException(errorMsg, statusCode: response.statusCode, responseBody: response.body);
      case 'kraken':
        throw KrakenApiException(errorMsg, statusCode: response.statusCode, responseBody: response.body);
      case 'okx':
        throw OkxApiException(errorMsg, statusCode: response.statusCode, responseBody: response.body);
      case 'strike':
        throw StrikeApiException(errorMsg, statusCode: response.statusCode, responseBody: response.body);
      case 'bitstamp':
        throw BitstampApiException(errorMsg, statusCode: response.statusCode, responseBody: response.body);
      case 'bitfinex':
        throw BitfinexApiException(errorMsg, statusCode: response.statusCode, responseBody: response.body);
      default:
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }
}
