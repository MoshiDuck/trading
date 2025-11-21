// lib/services/btc_data.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:trading/api/strike/strike.dart';

import '../api/binance/binance.dart';
import '../api/bitfinex/bitfinex.dart';
import '../api/bitstamp/bitstamp.dart';
import '../api/cryptocompare/cryptocompare.dart';
import '../api/kraken/kraken.dart';
import '../api/okx/okx.dart';
import '../api/interfaces.dart';
import '../components/model.dart';
import 'stats_database.dart'; // NOUVEAU IMPORT

class _WeightedEntry {
  final double value;
  final double weight;
  _WeightedEntry(this.value, this.weight);
}

/// Collecteur principal de données Bitcoin avec gestion améliorée des erreurs et performance
class BTCDataCollector {
  final BTCDataConfig config;

  // Sources disponibles avec typage via interfaces
  final List<PriceSource> _sources = [];

  // Cache et état
  final Map<String, SourceScore> _sourceScores = {};
  BTCDataCache? _lastValidCache;
  DateTime? _lastSuccessfulCollection;

  // Cache pour les données historiques avec verrou pour éviter les race conditions
  HistoricalDataCache? _historicalCache;
  DateTime? _lastHistoricalUpdate;
  bool _isFetchingHistorical = false;
  late var _historicalLock = Completer<void>()..complete();

  // NOUVEAU : Compteurs de requêtes pour les statistiques
  final Map<String, SourceRequestStats> _sourceRequestStats = {};

  // NOUVEAU : Base de données pour les statistiques
  final StatsDatabase _statsDatabase = StatsDatabase();

  BTCDataCollector({this.config = const BTCDataConfig()}) {
    _initializeSources();
    _initializeSourceStats();
    _initializeDatabase(); // NOUVEAU : Initialiser la base de données
  }

  // NOUVEAU : Initialiser la base de données
  Future<void> _initializeDatabase() async {
    try {
      // S'assurer que la base de données est initialisée
      await _statsDatabase.database;
      print('✅ Base de données statistiques initialisée');
    } catch (e) {
      print('❌ Erreur initialisation base de données: $e');
    }
  }

  Future<Map<String, dynamic>> getSourceStatsForUI() async {
    try {
      // NOUVEAU : Récupérer les statistiques depuis la base de données
      final dbStats = await _statsDatabase.getAggregatedStats(period: const Duration(hours: 24));

      // Combiner avec les scores en mémoire pour une vue complète
      final stats = <String, dynamic>{};

      for (var source in _sources) {
        final score = _sourceScores[source.name];
        final dbStat = dbStats[source.name];

        if (dbStat != null) {
          // Priorité aux statistiques de la base de données
          stats[source.name] = {
            'success': dbStat['success'],
            'total': dbStat['total'],
            'successRate': dbStat['successRate'],
            'reliability': dbStat['avgReliability'],
            'responseTime': dbStat['avgResponseTime'],
            'consistency': dbStat['avgConsistency'],
            'lastUpdate': dbStat['lastRequest'],
            'fromDatabase': true, // Indiquer que ça vient de la DB
          };
        } else if (score != null) {
          // Fallback aux scores en mémoire
          final requestStats = _sourceRequestStats[source.name];
          // CORRECTION : Vérification null-safe
          final successRate = (requestStats?.totalRequests ?? 0) > 0
              ? requestStats!.successfulRequests / requestStats.totalRequests
              : 0.0;

          stats[source.name] = {
            'success': requestStats?.successfulRequests ?? 0,
            'total': requestStats?.totalRequests ?? 0,
            'successRate': successRate,
            'reliability': score.reliability.toStringAsFixed(3),
            'responseTime': score.responseTime.toStringAsFixed(3),
            'consistency': score.consistency.toStringAsFixed(3),
            'lastUpdate': score.lastUpdate.toIso8601String(),
            'fromDatabase': false, // Indiquer que ça vient de la mémoire
          };
        } else {
          // Valeurs par défaut pour les nouvelles sources
          stats[source.name] = {
            'success': 0,
            'total': 0,
            'successRate': 0.0,
            'reliability': '0.000',
            'responseTime': '0.000',
            'consistency': '0.000',
            'lastUpdate': DateTime.now().toIso8601String(),
            'fromDatabase': false,
          };
        }
      }

      return stats;
    } catch (e) {
      print('❌ Erreur récupération statistiques UI: $e');
      // Fallback aux statistiques en mémoire
      return _getFallbackStatsForUI();
    }
  }

  // NOUVEAU : Fallback aux statistiques en mémoire
  Map<String, dynamic> _getFallbackStatsForUI() {
    final stats = <String, dynamic>{};

    for (var source in _sources) {
      final score = _sourceScores[source.name];
      final requestStats = _sourceRequestStats[source.name];

      if (score != null && requestStats != null) {
        // CORRECTION : Pas besoin de vérification null-safe ici car requestStats n'est pas null
        final successRate = requestStats.totalRequests > 0
            ? requestStats.successfulRequests / requestStats.totalRequests
            : 0.0;

        stats[source.name] = {
          'success': requestStats.successfulRequests,
          'total': requestStats.totalRequests,
          'successRate': successRate,
          'reliability': score.reliability.toStringAsFixed(3),
          'responseTime': score.responseTime.toStringAsFixed(3),
          'consistency': score.consistency.toStringAsFixed(3),
          'lastUpdate': score.lastUpdate.toIso8601String(),
          'fromDatabase': false,
        };
      } else {
        stats[source.name] = {
          'success': 0,
          'total': 0,
          'successRate': 0.0,
          'reliability': '0.000',
          'responseTime': '0.000',
          'consistency': '0.000',
          'lastUpdate': DateTime.now().toIso8601String(),
          'fromDatabase': false,
        };
      }
    }

    return stats;
  }

  /// Initialise les sources disponibles avec vérification de compatibilité
  void _initializeSources() {
    final apis = [
      _SourceWrapper('binance', BinanceApi()),
      _SourceWrapper('bitfinex', BitfinexApi()),
      _SourceWrapper('bitstamp', BitstampApi()),
      _SourceWrapper('cryptocompare', CryptoCompareApi()),
      _SourceWrapper('kraken', KrakenApi()),
      _SourceWrapper('okx', OkxApi()),
    ];

    for (var wrapper in apis) {
      bool isCompatible = false;

      if (wrapper.api is BitcoinPriceApi) {
        isCompatible = true;
      }
      if (wrapper.api is BitcoinMarketApi) {
        isCompatible = true;
      }
      if (wrapper.api is BitcoinHistoricalApi) {
        isCompatible = true;
      }

      if (isCompatible) {
        _sources.add(PriceSource(wrapper.name, wrapper.api));
      } else {
        print('❌ Source ${wrapper.name} ignorée - Aucune interface compatible');
      }
    }
  }

  void _initializeSourceScores() {
    for (var source in _sources) {
      _sourceScores[source.name] = SourceScore(
        reliability: 1.0,
        responseTime: 1.0,
        consistency: 1.0,
        lastUpdate: DateTime.now(),
      );
    }
  }

  // NOUVEAU : Initialise les statistiques de requêtes
  void _initializeSourceStats() {
    for (var source in _sources) {
      _sourceScores[source.name] = SourceScore(
        reliability: 0.5, // Commence à 50% de fiabilité
        responseTime: 0.5,
        consistency: 0.5,
        lastUpdate: DateTime.now(),
      );

      // NOUVEAU : Initialiser les statistiques de requêtes
      _sourceRequestStats[source.name] = SourceRequestStats(
        successfulRequests: 0,
        totalRequests: 0,
        lastRequest: DateTime.now(),
      );
    }
  }

  // NOUVEAU : Met à jour les statistiques de requêtes pour une source
  void _updateRequestStats(String sourceName, bool success) {
    final stats = _sourceRequestStats[sourceName];
    if (stats != null) {
      _sourceRequestStats[sourceName] = SourceRequestStats(
        successfulRequests: success ? stats.successfulRequests + 1 : stats.successfulRequests,
        totalRequests: stats.totalRequests + 1,
        lastRequest: DateTime.now(),
      );
    } else {
      // Initialiser si non existant
      _sourceRequestStats[sourceName] = SourceRequestStats(
        successfulRequests: success ? 1 : 0,
        totalRequests: 1,
        lastRequest: DateTime.now(),
      );
    }
  }

  // NOUVEAU : Enregistre les statistiques dans la base de données
  Future<void> _saveStatsToDatabase(SourceResponse response) async {
    try {
      final score = _sourceScores[response.source];

      final record = SourceStatsRecord(
        sourceName: response.source,
        success: response.success,
        responseTime: response.responseTime,
        timestamp: response.timestamp,
        error: response.error,
        reliability: score?.reliability ?? 0.5,
        consistency: score?.consistency ?? 0.5,
      );

      await _statsDatabase.insertStatsRecord(record);

      // Nettoyer occasionnellement les anciens enregistrements
      if (Random().nextDouble() < 0.01) { // 1% de chance à chaque appel
        await _statsDatabase.cleanupOldRecords();
      }
    } catch (e) {
      print('❌ Erreur sauvegarde statistiques DB: $e');
      // Ne pas propager l'erreur pour ne pas casser le flux principal
    }
  }

  // ===========================================================================
  // COLLECTE PARALLÈLE MULTI-SOURCES - VERSION CORRIGÉE
  // ===========================================================================

  double? _extractDoubleFromMap(Map<String, dynamic> map, String key) {
    try {
      final value = map[key];
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    } catch (e) {
      print('⚠️ Erreur extraction $key: $e');
      return null;
    }
  }

  Future<BTCDataResult> collectBitcoinData() async {
    final marketDataFuture = _collectMarketData();
    final historicalDataFuture = _getHistoricalData();

    try {
      final results = await Future.wait([marketDataFuture, historicalDataFuture]);
      final marketResult = results[0] as BTCDataResult;
      final historicalData = results[1] as HistoricalData;

      final completeResult = marketResult.copyWith(
        sixMonthsHigh: historicalData.sixMonthsHigh,
        sixMonthsLow: historicalData.sixMonthsLow,
        historicalDataAvailable: historicalData.sixMonthsHigh != null,
      );

      return completeResult;
    } catch (e) {
      print('❌ Erreur lors de la collecte: $e');
      return _handleFallback();
    }
  }

  Future<BTCDataResult> _collectMarketData() async {
    final List<Future<SourceResponse>> futures = _sources.map((source) {
      return _fetchMarketDataWithTimeout(source);
    }).toList();

    final responses = await Future.wait(futures, eagerError: false);
    return _processMarketDataResponses(responses);
  }

  Future<HistoricalData> _getHistoricalData() async {
    // Utiliser le cache si valide
    if (_historicalCache != null &&
        _lastHistoricalUpdate != null &&
        DateTime.now().difference(_lastHistoricalUpdate!) < config.historicalCacheTTL) {
      return HistoricalData(
        sixMonthsHigh: _historicalCache!.sixMonthsHigh,
        sixMonthsLow: _historicalCache!.sixMonthsLow,
      );
    }

    // Sinon, récupérer les données
    final historicalData = await _fetch6MonthsHistoricalData();

    // Mettre à jour le cache
    _historicalCache = HistoricalDataCache(
      sixMonthsHigh: historicalData.sixMonthsHigh,
      sixMonthsLow: historicalData.sixMonthsLow,
      timestamp: DateTime.now(),
    );
    _lastHistoricalUpdate = DateTime.now();

    return historicalData;
  }

  Future<void> _fetchHistoricalDataInBackground() async {
    // Éviter les appels concurrents
    if (_isFetchingHistorical) return;

    // Vérifier si le cache est encore valide
    if (_historicalCache != null &&
        _lastHistoricalUpdate != null &&
        DateTime.now().difference(_lastHistoricalUpdate!) < config.historicalCacheTTL) {
      return;
    }

    _isFetchingHistorical = true;

    try {
      final historicalData = await _fetch6MonthsHistoricalData();
      _historicalCache = HistoricalDataCache(
        sixMonthsHigh: historicalData.sixMonthsHigh,
        sixMonthsLow: historicalData.sixMonthsLow,
        timestamp: DateTime.now(),
      );
      _lastHistoricalUpdate = DateTime.now();
    } catch (e) {
      print('⚠️ Erreur lors de la récupération des données historiques: $e');
    } finally {
      _isFetchingHistorical = false;
    }
  }

  Future<HistoricalData> _fetch6MonthsHistoricalData() async {
    final historicalData = HistoricalData();
    final List<Future<Map<String, double?>?>> historicalFutures = [];

    for (var source in _sources) {
      final future = _fetchHistoricalHighLowFromSource(source.api)
          .timeout(Duration(seconds: config.requestTimeout), onTimeout: () {
        return null;
      }).catchError((e) {
        print('⚠️ Erreur historique ${source.name}: $e');
        return null;
      });
      historicalFutures.add(future);
    }

    try {
      final results = await Future.wait(historicalFutures, eagerError: false);
      final highs = <double>[];
      final lows = <double>[];

      for (var res in results) {
        if (res == null) continue;
        final h = res['high'];
        final l = res['low'];

        if (h != null && h > 0 && _isReasonablePrice(h)) highs.add(h);
        if (l != null && l > 0 && _isReasonablePrice(l)) lows.add(l);
      }

      // Éviter l'initialisation double
      if (highs.isNotEmpty) {
        historicalData.sixMonthsHigh = highs.reduce(max);
      } else {
        historicalData.sixMonthsHigh = null;
        print('⚠️ Aucun high historique valide trouvé');
      }

      if (lows.isNotEmpty) {
        historicalData.sixMonthsLow = lows.reduce(min);
      } else {
        historicalData.sixMonthsLow = null;
        print('⚠️ Aucun low historique valide trouvé');
      }
    } catch (e) {
      print('❌ Erreur lors de l\'agrégation des données historiques: $e');
    }

    return historicalData;
  }

  Future<Map<String, double?>?> _fetchHistoricalHighLowFromSource(dynamic api) async {
    try {

      // CryptoCompare
      if (api is CryptoCompareApi) {
        try {
          final historical = await api.getBitcoinHistoricalData(limit: 180);
          final prices = historical['prices'] as List<dynamic>?;

          if (prices == null || prices.isEmpty) {
            return null;
          }

          final validHighs = <double>[];
          final validLows = <double>[];

          for (var priceData in prices) {
            if (priceData is Map<String, dynamic>) {
              final high = _safeGetDoubleFromMap(priceData, 'high');
              final low = _safeGetDoubleFromMap(priceData, 'low');

              if (high != null && _isReasonablePrice(high)) {
                validHighs.add(high);
              }
              if (low != null && _isReasonablePrice(low)) {
                validLows.add(low);
              }
            }
          }

          return {
            'high': validHighs.isNotEmpty ? validHighs.reduce(max) : null,
            'low': validLows.isNotEmpty ? validLows.reduce(min) : null,
          };
        } catch (e) {
          print('⚠️ CryptoCompare historique échoué: $e');
          return null;
        }
      }

      // Binance
      if (api is BinanceApi) {
        try {
          final klines = await api.getKlines(symbol: 'BTCEUR', interval: '1d', limit: 180);
          if (klines is List && klines.isNotEmpty) {
            double? maxHigh;
            double? minLow;

            for (var kline in klines) {
              if (kline is List && kline.length > 3) {
                final high = double.tryParse(kline[2].toString());
                final low = double.tryParse(kline[3].toString());

                if (high != null && _isReasonablePrice(high)) {
                  maxHigh = max(maxHigh ?? high, high);
                }
                if (low != null && _isReasonablePrice(low)) {
                  minLow = min(minLow ?? low, low);
                }
              }
            }
            return {
              'high': maxHigh,
              'low': minLow,
            };
          }
        } catch (e) {
          print('⚠️ Binance historique échoué: $e');
        }
        return null;
      }

      // Pour les autres APIs, utiliser les données 24h comme approximation
      final marketData = await _fetchCompleteMarketData(api);
      return {
        'high': _validateHistoricalValue(marketData.high24h),
        'low': _validateHistoricalValue(marketData.low24h),
      };

    } catch (e) {
      print('⚠️ Erreur source historique ${api.runtimeType}: $e');
      return null;
    }
  }

  double? _safeGetDoubleFromMap(Map<String, dynamic> map, String key) {
    try {
      final value = map[key];
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Valide une valeur historique pour éviter les données corrompues
  double? _validateHistoricalValue(double? value) {
    if (value == null || value <= 0 || !_isReasonablePrice(value)) {
      return null;
    }
    return value;
  }

  /// Vérifie si un prix est dans une plage raisonnable pour Bitcoin
  bool _isReasonablePrice(double price) {
    return price >= 50000 && price <= 200000;
  }

  // ===========================================================================
  // COLLECTE DES DONNÉES DE MARCHÉ TEMPS RÉEL
  // ===========================================================================

  /// Récupère les données de marché avec timeout et gestion d'erreurs
  Future<SourceResponse> _fetchMarketDataWithTimeout(PriceSource source) async {
    final stopwatch = Stopwatch()..start();
    MarketData? marketData;
    Object? error;

    try {
      marketData = await _fetchCompleteMarketData(source.api)
          .timeout(Duration(seconds: config.requestTimeout));

      // NOUVEAU : Mettre à jour les statistiques de requête
      _updateRequestStats(source.name, true);

    } catch (e) {
      error = e;
      print('❌ Source ${source.name} a échoué: $e');

      // NOUVEAU : Mettre à jour les statistiques de requête (échec)
      _updateRequestStats(source.name, false);
    } finally {
      stopwatch.stop();
    }

    final response = SourceResponse(
      source: source.name,
      marketData: marketData ?? MarketData.empty(),
      responseTime: stopwatch.elapsedMilliseconds / 1000.0,
      timestamp: DateTime.now(),
      success: marketData != null && _isValidMarketData(marketData!),
      error: error?.toString(),
    );

    // NOUVEAU : Sauvegarder dans la base de données
    _saveStatsToDatabase(response);

    return response;
  }

  Future<MarketData> _fetchCompleteMarketData(dynamic api) async {
    final data = MarketData.empty();

    try {
      if (api is BitcoinMarketApi) {
        final marketDataResponse = await api.getBitcoinMarketData();

        if (marketDataResponse is Map<String, dynamic>) {
          // Extraction robuste avec gestion des types
          data.price = _safeGetDouble(marketDataResponse['currentPrice']) ?? 0.0;
          data.volume = _safeGetDouble(marketDataResponse['volume']);
          data.marketCap = _safeGetDouble(marketDataResponse['marketCap']);
          data.high24h = _safeGetDouble(marketDataResponse['high24h']);
          data.low24h = _safeGetDouble(marketDataResponse['low24h']);
          data.priceChange24h = _safeGetDouble(marketDataResponse['priceChange24h']);
          data.priceChangePercent24h = _safeGetDouble(marketDataResponse['priceChangePercentage24h']);
        } else {
          print('⚠️ Format de réponse inattendu: ${marketDataResponse.runtimeType}');
        }
      }

      // Fallback pour le prix si nécessaire
      if (data.price == 0 && api is BitcoinPriceApi) {
        data.price = await (api).getBitcoinPrice();
      }

    } catch (e) {
      print('❌ Erreur récupération données ${api.runtimeType}: $e');

      // Fallback ultime - seulement le prix
      if (data.price == 0 && api is BitcoinPriceApi) {
        try {
          data.price = await api.getBitcoinPrice();
        } catch (e2) {
          print('❌ Fallback prix aussi en échec: $e2');
          throw e;
        }
      }
    }

    return data;
  }

  // Méthode utilitaire pour conversion sécurisée
  double? _safeGetDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // Méthode utilitaire pour conversion sécurisée
  double? _safeDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // ===========================================================================
  // TRAITEMENT ET VALIDATION DES DONNÉES
  // ===========================================================================

  /// Traite les réponses des sources et agrège les données
  BTCDataResult _processMarketDataResponses(List<SourceResponse> responses) {
    // 1. Filtrer les réponses valides
    final validResponses = responses.where((response) {
      return response.success && _isValidMarketData(response.marketData);
    }).toList();

    if (validResponses.length < config.minValidSources) {
      print('⚠️  Sources valides insuffisantes, utilisation du fallback');
      return _handleFallback();
    }

    // 2. Suppression des outliers pour le prix
    final cleanedResponses = _removePriceOutliers(validResponses);

    if (cleanedResponses.isEmpty) {
      return _handleFallback();
    }

    // 3. Agrégation séparée pour chaque type de donnée
    final aggregatedData = _aggregateAllMarketData(cleanedResponses);

    // 4. Mise à jour des scores des sources
    _updateSourceScores(cleanedResponses);

    // 5. Préparation du résultat
    final result = BTCDataResult(
      price: aggregatedData.price,
      volume: aggregatedData.volume,
      marketCap: aggregatedData.marketCap,
      high24h: aggregatedData.high24h,
      low24h: aggregatedData.low24h,
      priceChange24h: aggregatedData.priceChange24h,
      priceChangePercent24h: aggregatedData.priceChangePercent24h,
      sixMonthsHigh: _historicalCache?.sixMonthsHigh,
      sixMonthsLow: _historicalCache?.sixMonthsLow,
      sourcesUsed: cleanedResponses.length,
      totalSources: _sources.length,
      timestamp: DateTime.now(),
      sourceDetails: cleanedResponses,
      cacheUsed: false,
      historicalDataAvailable: _historicalCache != null,
    );

    // 6. Mise à jour atomique du cache
    _updateCache(result);

    return result;
  }

  Future<void> debugAllApisDetailed() async {

    for (var source in _sources) {

      try {
        bool isConnected = false;
        if (source.api is BinanceApi) {
          isConnected = await (source.api as BinanceApi).testPing();
        } else if (source.api is BitfinexApi) {
          isConnected = await (source.api as BitfinexApi).testPing();
        } else if (source.api is BitstampApi) {
          isConnected = await (source.api as BitstampApi).testPing();
        } else if (source.api is CryptoCompareApi) {
          isConnected = await (source.api as CryptoCompareApi).testPing();
        } else if (source.api is KrakenApi) {
          isConnected = await (source.api as KrakenApi).testPing();
        } else if (source.api is OkxApi) {
          isConnected = await (source.api as OkxApi).testPing();
        } else if (source.api is StrikeApi) {
          isConnected = await (source.api as StrikeApi).testPing();
        }

        // Test des données de marché
        if (source.api is BitcoinMarketApi) {
          final marketApi = source.api as BitcoinMarketApi;
          final marketData = await marketApi.getBitcoinMarketData().timeout(Duration(seconds: 10));

          if (marketData is Map<String, dynamic>) {
          } else {
            print('   ⚠️ Format inattendu: ${marketData.runtimeType}');
          }
        }
      } catch (e) {
        print('   ❌ ${source.name}: ERREUR - $e');
      }
    }
  }

  bool _isValidMarketData(MarketData data) {
    // Validation du prix de base
    if (data.price <= 0 || !_isReasonablePrice(data.price)) {
      print('❌ Prix invalide ou hors plage: ${data.price}');
      return false;
    }

    // Validation optionnelle des autres champs
    if (data.volume != null && data.volume! < 0) {
      print('⚠️ Volume négatif, mise à null: ${data.volume}');
      data.volume = null;
    }

    if (data.marketCap != null && data.marketCap! < 0) {
      print('⚠️ MarketCap négatif, mise à null: ${data.marketCap}');
      data.marketCap = null;
    }

    // Validation de la cohérence high/low (optionnelle)
    if (data.high24h != null && data.low24h != null) {
      if (data.high24h! < data.low24h!) {
        print('⚠️ Incohérence high/low, valeurs ignorées');
        data.high24h = null;
        data.low24h = null;
      } else if (data.price > data.high24h! * 1.05 || data.price < data.low24h! * 0.95) {
        print('⚠️ Prix en dehors de la fourchette 24h, valeurs ignorées');
        data.high24h = null;
        data.low24h = null;
      }
    }

    return true;
  }

  /// Supprime les outliers basés sur la déviation par rapport à la médiane
  List<SourceResponse> _removePriceOutliers(List<SourceResponse> responses) {
    if (responses.length < 3) return responses;

    final prices = responses.map((r) => r.marketData.price).toList();
    final double median = _calculateMedian(prices..sort());

    if (median == 0.0) return responses;

    final filteredResponses = responses.where((response) {
      final price = response.marketData.price;
      final deviation = (price - median).abs() / median * 100;
      final isWithinThreshold = deviation <= config.outlierThreshold;
      return isWithinThreshold;
    }).toList();
    return filteredResponses;
  }

  // ===========================================================================
  // AGRÉGATION AVEC PONDÉRATION OPTIMISÉE
  // ===========================================================================

  /// Agrège toutes les données de marché avec pondération des sources
  MarketData _aggregateAllMarketData(List<SourceResponse> responses) {
    final aggregated = MarketData.empty();

    // Calcul des poids une seule fois
    final sourceWeights = _calculateSourceWeights(responses);

    // Agrégation du prix avec pondération
    aggregated.price = _aggregateWithWeightedMethod(responses, sourceWeights, (r) => r.marketData.price);

    // Agrégation du volume avec pondération
    aggregated.volume = _aggregateWithWeightedMethod(
        responses, sourceWeights, (r) => r.marketData.volume,
        requireValue: true
    );

    // Agrégation de la market cap avec pondération
    aggregated.marketCap = _aggregateWithWeightedMethod(
        responses, sourceWeights, (r) => r.marketData.marketCap,
        requireValue: true
    );

    // Agrégation des autres données
    aggregated.high24h = _aggregateHighs(responses.map((r) => r.marketData.high24h).where((v) => v != null).cast<double>().toList());
    aggregated.low24h = _aggregateLows(responses.map((r) => r.marketData.low24h).where((v) => v != null).cast<double>().toList());
    aggregated.priceChange24h = _aggregatePriceChanges(responses.map((r) => r.marketData.priceChange24h).where((v) => v != null).cast<double>().toList());
    aggregated.priceChangePercent24h = _aggregatePriceChangePercents(responses.map((r) => r.marketData.priceChangePercent24h).where((v) => v != null).cast<double>().toList());

    return aggregated;
  }

  /// Calcule les poids des sources une seule fois pour éviter les recalculs
  Map<String, double> _calculateSourceWeights(List<SourceResponse> responses) {
    final weights = <String, double>{};

    for (var response in responses) {
      final score = _sourceScores[response.source];
      if (score == null) continue;

      // Formule de pondération centralisée
      final weight = (score.reliability * 0.4) +
          (score.consistency * 0.4) +
          (score.responseTime * 0.2);

      weights[response.source] = weight;
    }

    return weights;
  }

  /// Méthode générique d'agrégation pondérée
  double _aggregateWithWeightedMethod(
      List<SourceResponse> responses,
      Map<String, double> sourceWeights,
      double? Function(SourceResponse) valueExtractor, {
        bool requireValue = false
      }) {
    if (responses.isEmpty) return 0.0;
    if (responses.length == 1) {
      final value = valueExtractor(responses.first);
      return value ?? 0.0;
    }

    final List<_WeightedEntry> weightedData = [];
    double totalWeight = 0.0;

    for (var response in responses) {
      final value = valueExtractor(response);
      if (requireValue && value == null) continue;
      final actualValue = value ?? 0.0;

      final weight = sourceWeights[response.source] ?? 0.0;
      if (weight > 0) {
        weightedData.add(_WeightedEntry(actualValue, weight));
        totalWeight += weight;
      }
    }

    if (weightedData.isEmpty) {
      // Fallback: médiane des valeurs disponibles
      final values = responses.map(valueExtractor).where((v) => v != null).cast<double>().toList();
      if (values.isNotEmpty) {
        values.sort();
        return _calculateMedian(values);
      }
      return 0.0;
    }

    if (totalWeight == 0) {
      final values = weightedData.map((w) => w.value).toList()..sort();
      return _calculateMedian(values);
    }

    double weightedSum = 0.0;
    for (var w in weightedData) {
      final normalizedWeight = w.weight / totalWeight;
      weightedSum += w.value * normalizedWeight;
    }

    return weightedSum;
  }

  /// Agrège les highs en prenant le maximum raisonnable
  double? _aggregateHighs(List<double> highs) {
    if (highs.isEmpty) return null;
    if (highs.length == 1) return highs.first;

    final median = _calculateMedian(highs..sort());
    final reasonableHighs = highs.where((h) => h <= median * 1.1).toList();
    return reasonableHighs.isNotEmpty ? reasonableHighs.reduce(max) : median;
  }

  /// Agrège les lows en prenant le minimum raisonnable
  double? _aggregateLows(List<double> lows) {
    if (lows.isEmpty) return null;
    if (lows.length == 1) return lows.first;

    final median = _calculateMedian(lows..sort());
    final reasonableLows = lows.where((l) => l >= median * 0.9).toList();
    return reasonableLows.isNotEmpty ? reasonableLows.reduce(min) : median;
  }

  /// Agrège les changements de prix avec méthode robuste
  double? _aggregatePriceChanges(List<double> changes) {
    return _aggregateWithRobustMethod(changes);
  }

  /// Agrège les pourcentages de changement avec méthode robuste
  double? _aggregatePriceChangePercents(List<double> percents) {
    return _aggregateWithRobustMethod(percents);
  }

  // ===========================================================================
  // GESTION DES SCORES ET MISE À JOUR
  // ===========================================================================

  /// Met à jour les scores des sources basés sur les performances récentes
  void _updateSourceScores(List<SourceResponse> successfulResponses) {
    final allSourceNames = _sourceScores.keys.toList();
    final successfulSources = successfulResponses.map((r) => r.source).toSet();

    for (var sourceName in allSourceNames) {
      final currentScore = _sourceScores[sourceName]!;
      final wasSuccessful = successfulSources.contains(sourceName);

      if (wasSuccessful) {
        // Trouver la réponse correspondante
        final response = successfulResponses.firstWhere(
              (r) => r.source == sourceName,
          orElse: () => SourceResponse(
            source: sourceName,
            marketData: MarketData.empty(),
            responseTime: 1.0,
            timestamp: DateTime.now(),
            success: false,
          ),
        );

        // Améliorer le score pour les sources réussies
        _sourceScores[sourceName] = SourceScore(
          reliability: (currentScore.reliability * 0.8 + 0.2).clamp(0.1, 1.0),
          responseTime: (currentScore.responseTime * 0.7 + 0.3).clamp(0.1, 1.0),
          consistency: (currentScore.consistency * 0.8 + 0.2).clamp(0.1, 1.0),
          lastUpdate: DateTime.now(),
        );

      } else {
        // Réduire le score pour les sources en échec
        _sourceScores[sourceName] = SourceScore(
          reliability: (currentScore.reliability * 0.6).clamp(0.1, 1.0),
          responseTime: (currentScore.responseTime * 0.8).clamp(0.1, 1.0),
          consistency: (currentScore.consistency * 0.7).clamp(0.1, 1.0),
          lastUpdate: DateTime.now(),
        );

        print('❌ ${sourceName}: fiabilité ↓ ${_sourceScores[sourceName]!.reliability.toStringAsFixed(3)}');
      }
    }
  }

  // ===========================================================================
  // GESTION DU CACHE ET FALLBACK
  // ===========================================================================

  /// Met à jour le cache de manière atomique
  void _updateCache(BTCDataResult result) {
    _lastValidCache = BTCDataCache(
      data: result,
      timestamp: DateTime.now(),
      sourceCount: result.sourcesUsed,
    );
    _lastSuccessfulCollection = DateTime.now();
  }

  /// Gère les fallbacks en cas d'échec partiel ou total
  BTCDataResult _handleFallback() {
    final now = DateTime.now();

    if (_lastValidCache != null) {
      final cacheAge = now.difference(_lastValidCache!.timestamp);

      if (cacheAge <= config.cacheTTL) {
        return _lastValidCache!.data.copyWith(cacheUsed: true);
      }

      if (cacheAge <= config.fallbackTTL) {
        return _lastValidCache!.data.copyWith(cacheUsed: true);
      }
    }

    if (_lastValidCache != null) {
      return _lastValidCache!.data.copyWith(cacheUsed: true);
    }

    throw BTCDataException('Aucune donnée Bitcoin disponible et pas de cache de secours');
  }

  // ===========================================================================
  // MÉTHODES UTILITAIRES STATISTIQUES
  // ===========================================================================

  double _calculateMedian(List<double> sortedValues) {
    if (sortedValues.isEmpty) return 0.0;
    final int middle = sortedValues.length ~/ 2;
    if (sortedValues.length % 2 == 1) {
      return sortedValues[middle];
    } else {
      return (sortedValues[middle - 1] + sortedValues[middle]) / 2.0;
    }
  }

  double _calculateTrimmedMean(List<double> sortedValues) {
    if (sortedValues.isEmpty) return 0.0;
    final int trimCount = (sortedValues.length * 0.1).round();
    final int endIndex = sortedValues.length - trimCount;
    if (trimCount == 0 || endIndex <= trimCount) {
      return sortedValues.reduce((a, b) => a + b) / sortedValues.length;
    }
    final trimmedList = sortedValues.sublist(trimCount, endIndex);
    return trimmedList.isEmpty
        ? sortedValues.reduce((a, b) => a + b) / sortedValues.length
        : trimmedList.reduce((a, b) => a + b) / trimmedList.length;
  }

  double _aggregateWithRobustMethod(List<double> values) {
    if (values.isEmpty) return 0.0;
    if (values.length == 1) return values.first;

    final sortedValues = List<double>.from(values)..sort();

    if (values.length < 4) {
      return _calculateMedian(sortedValues);
    }

    final median = _calculateMedian(sortedValues);
    final trimmedMean = _calculateTrimmedMean(sortedValues);

    final difference = (trimmedMean - median).abs() / (median.abs() + 0.0001) * 100;

    return difference <= 0.5 ? trimmedMean : median;
  }

  // ===========================================================================
  // MÉTHODES PUBLIQUES
  // ===========================================================================

  /// Retourne les statistiques des sources pour le débogage
  Map<String, dynamic> getSourceStats() {
    return _sourceScores.map((key, value) => MapEntry(key, {
      'reliability': value.reliability.toStringAsFixed(3),
      'responseTime': value.responseTime.toStringAsFixed(3),
      'consistency': value.consistency.toStringAsFixed(3),
      'lastUpdate': value.lastUpdate.toIso8601String(),
      'weight': ((value.reliability * 0.4) + (value.consistency * 0.4) + (value.responseTime * 0.2)).toStringAsFixed(3),
    }));
  }

  // NOUVEAU : Obtenir les statistiques détaillées depuis la base de données
  Future<Map<String, dynamic>> getDetailedSourceStats({
    Duration period = const Duration(hours: 24),
  }) async {
    try {
      return await _statsDatabase.getAggregatedStats(period: period);
    } catch (e) {
      print('❌ Erreur récupération statistiques détaillées: $e');
      return {};
    }
  }

  // NOUVEAU : Obtenir l'historique des statistiques pour une source
  Future<List<SourceStatsRecord>> getSourceHistory(
      String sourceName, {
        Duration period = const Duration(hours: 24),
      }) async {
    try {
      return await _statsDatabase.getSourceStats(sourceName, period: period);
    } catch (e) {
      print('❌ Erreur récupération historique source $sourceName: $e');
      return [];
    }
  }

  /// Réinitialise les scores des sources
  void resetSourceScores() {
    _initializeSourceScores();

    // NOUVEAU : Réinitialiser aussi les statistiques de requêtes
    for (var source in _sources) {
      _sourceRequestStats[source.name] = SourceRequestStats(
        successfulRequests: 0,
        totalRequests: 0,
        lastRequest: DateTime.now(),
      );
    }
  }

  /// Vérifie la santé du service
  Future<bool> healthCheck() async {
    try {
      final result = await collectBitcoinData();
      return result.sourcesUsed >= config.minValidSources;
    } catch (e) {
      return false;
    }
  }

  /// Force la mise à jour des données historiques
  Future<void> refreshHistoricalData() async {
    _historicalCache = null;
    _lastHistoricalUpdate = null;
    await _fetchHistoricalDataInBackground();
  }

  /// Obtient les données historiques (avec cache)
  Future<HistoricalData> getHistoricalData() async {
    if (_historicalCache == null) {
      await _fetchHistoricalDataInBackground();
    }
    return HistoricalData(
      sixMonthsHigh: _historicalCache?.sixMonthsHigh,
      sixMonthsLow: _historicalCache?.sixMonthsLow,
    );
  }

  // NOUVEAU : Fermer la base de données
  Future<void> close() async {
    try {
      await _statsDatabase.close();
      print('✅ Base de données statistiques fermée');
    } catch (e) {
      print('❌ Erreur fermeture base de données: $e');
    }
  }
}

/// Wrapper pour l'initialisation des sources
class _SourceWrapper {
  final String name;
  final dynamic api;

  _SourceWrapper(this.name, this.api);
}

// ===========================================================================
// EXCEPTIONS SPÉCIFIQUES
// ===========================================================================

/// Exception pour les erreurs de collecte de données
class BTCDataException implements Exception {
  final String message;
  BTCDataException(this.message);

  @override
  String toString() => 'BTCDataException: $message';
}

/// Exception pour les erreurs historiques des sources
class SourceHistoricalException implements Exception {
  final String source;
  final String error;

  SourceHistoricalException({required this.source, required this.error});

  @override
  String toString() => 'SourceHistoricalException($source): $error';
}

// ===========================================================================
// SERVICE SINGLETON CONFIGURABLE
// ===========================================================================

/// Service singleton global pour l'accès aux données Bitcoin
class BTCDataService {
  static BTCDataCollector _instance = BTCDataCollector();
  static BTCDataConfig _config = const BTCDataConfig();

  static BTCDataCollector get instance => _instance;

  /// Configure le service avec une configuration personnalisée
  static void configure(BTCDataConfig config) {
    _config = config;
    _instance = BTCDataCollector(config: config);
  }

  static Future<Map<String, dynamic>> getSourceStatsForUI() async {
    return _instance.getSourceStatsForUI();
  }

  // NOUVEAU : Obtenir les statistiques détaillées depuis la base de données
  static Future<Map<String, dynamic>> getDetailedSourceStats({
    Duration period = const Duration(hours: 24),
  }) async {
    return await _instance.getDetailedSourceStats(period: period);
  }

  // NOUVEAU : Obtenir l'historique d'une source
  static Future<List<SourceStatsRecord>> getSourceHistory(
      String sourceName, {
        Duration period = const Duration(hours: 24),
      }) async {
    return await _instance.getSourceHistory(sourceName, period: period);
  }

  /// Obtient le prix Bitcoin rapidement
  static Future<double> getBitcoinPrice() async {
    final result = await _instance.collectBitcoinData();
    return result.price;
  }

  /// Obtient les données Bitcoin complètes
  static Future<BTCDataResult> getBitcoinData() async {
    return await _instance.collectBitcoinData();
  }

  /// Obtient les données de marché sous forme de map
  static Future<Map<String, dynamic>> getBitcoinMarketData() async {
    final result = await _instance.collectBitcoinData();
    return {
      'price': result.price,
      'volume': result.volume,
      'marketCap': result.marketCap,
      'high24h': result.high24h,
      'low24h': result.low24h,
      'priceChange24h': result.priceChange24h,
      'priceChangePercent24h': result.priceChangePercent24h,
      'sixMonthsHigh': result.sixMonthsHigh,
      'sixMonthsLow': result.sixMonthsLow,
    };
  }

  /// Obtient les données historiques
  static Future<HistoricalData> getHistoricalData() async {
    return await _instance.getHistoricalData();
  }

  /// Force la mise à jour des données historiques
  static Future<void> refreshHistoricalData() async {
    await _instance.refreshHistoricalData();
  }

  /// Obtient les statistiques des sources
  static Map<String, dynamic> getSourceStats() {
    return _instance.getSourceStats();
  }

  /// Réinitialise les scores des sources
  static void resetSourceScores() {
    _instance.resetSourceScores();
  }

  /// Vérifie la santé du service
  static Future<bool> healthCheck() async {
    return await _instance.healthCheck();
  }

  // NOUVEAU : Fermer le service et la base de données
  static Future<void> close() async {
    await _instance.close();
  }
}