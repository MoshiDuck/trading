// lib/types/unified_models.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../types/types.dart';
import '../utils/safe_convert.dart';

// ===========================================================================
// MODÈLES UNIFIÉS POUR TOUS LES EXCHANGES
// ===========================================================================

/// Ticker unifié pour tous les exchanges
class UnifiedTicker {
  final String symbol;
  final double lastPrice;
  final double bid;
  final double ask;
  final double high24h;
  final double low24h;
  final double volume24h;
  final double priceChange24h;
  final double priceChangePercent24h;
  final double open24h;
  final double? marketCap;
  final DateTime timestamp;

  UnifiedTicker({
    required this.symbol,
    required this.lastPrice,
    required this.bid,
    required this.ask,
    required this.high24h,
    required this.low24h,
    required this.volume24h,
    required this.priceChange24h,
    required this.priceChangePercent24h,
    required this.open24h,
    this.marketCap,
    required this.timestamp,
  });

  double get spread => ask - bid;
  double get spreadPercent => (spread / lastPrice) * 100;

  Color get changeColor => priceChangePercent24h >= 0 ? Colors.green : Colors.red;
  IconData get changeIcon => priceChangePercent24h >= 0 ? Icons.arrow_upward : Icons.arrow_downward;

  String get formattedVolume {
    if (volume24h >= 1e9) return '€${(volume24h / 1e9).toStringAsFixed(2)}B';
    if (volume24h >= 1e6) return '€${(volume24h / 1e6).toStringAsFixed(2)}M';
    if (volume24h >= 1e3) return '€${(volume24h / 1e3).toStringAsFixed(2)}K';
    return '€${volume24h.toStringAsFixed(2)}';
  }

  @override
  String toString() {
    return '$symbol: €$lastPrice (${priceChangePercent24h.toStringAsFixed(2)}%)';
  }
}

/// Order Book unifié pour tous les exchanges
class UnifiedOrderBook {
  final List<UnifiedOrderBookEntry> bids;
  final List<UnifiedOrderBookEntry> asks;
  final DateTime timestamp;

  UnifiedOrderBook({
    required this.bids,
    required this.asks,
    required this.timestamp,
  });

  double get spread {
    if (bids.isEmpty || asks.isEmpty) return 0;
    return asks.first.price - bids.first.price;
  }

  double get spreadPercent {
    if (bids.isEmpty || asks.isEmpty) return 0;
    return (spread / bids.first.price) * 100;
  }

  @override
  String toString() {
    return 'Bids: ${bids.length}, Asks: ${asks.length}, Spread: €${spread.toStringAsFixed(2)} (${spreadPercent.toStringAsFixed(2)}%)';
  }
}

/// Entrée d'order book unifiée
class UnifiedOrderBookEntry {
  final double price;
  final double quantity;
  final int? count;

  UnifiedOrderBookEntry({
    required this.price,
    required this.quantity,
    this.count,
  });

  @override
  String toString() {
    return 'Price: €$price | Quantity: ${quantity.toStringAsFixed(4)}';
  }
}

/// Trade unifié pour tous les exchanges
class UnifiedTrade {
  final String tradeId;
  final double price;
  final double quantity;
  final bool isBuyerMaker;
  final DateTime timestamp;

  UnifiedTrade({
    required this.tradeId,
    required this.price,
    required this.quantity,
    required this.isBuyerMaker,
    required this.timestamp,
  });

  String get tradeType => isBuyerMaker ? 'Vente' : 'Achat';

  @override
  String toString() {
    return '$tradeType: ${quantity.toStringAsFixed(4)} BTC @ €${price.toStringAsFixed(2)}';
  }
}

/// Données OHLC unifiées
class UnifiedOHLC {
  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  UnifiedOHLC({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  double get priceChange => close - open;
  double get priceChangePercent => open != 0 ? (priceChange / open) * 100 : 0;

  @override
  String toString() {
    return '${timestamp.hour}:${timestamp.minute}: O:€$open H:€$high L:€$low C:€$close';
  }
}

/// Instrument de trading unifié
class UnifiedInstrument {
  final String symbol;
  final String baseCurrency;
  final String quoteCurrency;
  final double tickSize;
  final double lotSize;
  final double minSize;
  final String status;

  UnifiedInstrument({
    required this.symbol,
    required this.baseCurrency,
    required this.quoteCurrency,
    required this.tickSize,
    required this.lotSize,
    required this.minSize,
    required this.status,
  });

  @override
  String toString() {
    return '$baseCurrency/$quoteCurrency (Tick: $tickSize, Lot: $lotSize, Min: $minSize)';
  }
}

// ===========================================================================
// MODÈLES SPÉCIFIQUES À LA STRATÉGIE (inchangés)
// ===========================================================================

class DecisionAchat {
  final bool acheter;
  final String raison;
  final PalierDynamique? palier;
  final double? montantInvestissement;
  final double? prixCibleAchat;
  final double? stopLoss;
  final double? takeProfit;
  final double? fraisEstimes;
  final double? capitalReel;
  final Map<String, String>? metrics;

  DecisionAchat({
    required this.acheter,
    required this.raison,
    this.palier,
    this.montantInvestissement,
    this.prixCibleAchat,
    this.stopLoss,
    this.takeProfit,
    this.fraisEstimes,
    this.capitalReel,
    this.metrics,
  });

  @override
  String toString() {
    return 'DecisionAchat DYNAMIQUE: $raison - Achat: $acheter - Capital: ${capitalReel?.toStringAsFixed(2)}';
  }
}

class DecisionVente {
  final bool vendre;
  final Trade trade;
  final String raison;
  final TypeVente typeVente;
  final double prixVente;
  final Map<String, String>? metrics;

  DecisionVente({
    required this.vendre,
    required this.trade,
    required this.raison,
    required this.typeVente,
    required this.prixVente,
    this.metrics,
  });

  @override
  String toString() {
    return 'DecisionVente DYNAMIQUE: $raison - Vente: $vendre';
  }
}

class BalanceStrike {
  final double soldeEUR;
  final double soldeBTC;
  final DateTime dernierUpdate;
  final String? erreur;

  BalanceStrike({
    required this.soldeEUR,
    required this.soldeBTC,
    required this.dernierUpdate,
    this.erreur,
  });

  bool get aErreur => erreur != null;

  @override
  String toString() {
    if (aErreur) {
      return 'Balance ERREUR: $erreur';
    }
    return 'Balance RÉELLE: ${soldeEUR.toStringAsFixed(2)} EUR, ${soldeBTC.toStringAsFixed(6)} BTC';
  }
}

class SafetyBounds {
  final double minCapitalPercent;
  final double maxCapitalPercent;
  final double minTakeProfitPercent;
  final double maxTakeProfitPercent;
  final double minRSIThreshold;
  final double maxRSIThreshold;

  const SafetyBounds({
    required this.minCapitalPercent,
    required this.maxCapitalPercent,
    required this.minTakeProfitPercent,
    required this.maxTakeProfitPercent,
    required this.minRSIThreshold,
    required this.maxRSIThreshold,
  });
}



class PalierDynamique {
  final double drawdownMin;
  final double drawdownMax;
  final double pourcentageCapital;
  final double takeProfitPercent;
  final String nom;
  final double atrValue;
  final double rsiValue;
  final Map<String, dynamic> metrics;

  const PalierDynamique({
    required this.drawdownMin,
    required this.drawdownMax,
    required this.pourcentageCapital,
    required this.takeProfitPercent,
    required this.nom,
    required this.atrValue,
    required this.rsiValue,
    required this.metrics,
  });

  @override
  String toString() {
    return '$nom (${drawdownMin}% à ${drawdownMax}%) - Invest: ${pourcentageCapital.toStringAsFixed(1)}% - TP: ${takeProfitPercent.toStringAsFixed(1)}%';
  }
}

class TransactionStrike {
  final String id;
  final double montant;
  final String devise;
  final TypeTransaction type;
  final String statut;
  final DateTime date;
  final String description;

  TransactionStrike({
    required this.id,
    required this.montant,
    required this.devise,
    required this.type,
    required this.statut,
    required this.date,
    required this.description,
  });

  @override
  String toString() {
    return '$type RÉEL: ${montant.toStringAsFixed(2)} $devise - $statut';
  }
}

class Trade {
  final String id;
  final double prixAchat;
  final double quantite;
  final double takeProfit;
  final PalierDynamique palier;
  final DateTime dateAchat;
  final double montantInvesti;

  bool vendu = false;
  DateTime? dateVente;
  double? prixVente;
  double? montantVente;
  TypeVente? typeVente;
  String? strikeQuoteId;
  double? soldeEURAvant;
  double? soldeEURApres;
  double? soldeEURApresVente;

  final TypeTrade typeTrade;
  final bool estVente;

  Trade({
    required this.id,
    required this.prixAchat,
    required this.quantite,
    required this.takeProfit,
    required this.palier,
    required this.dateAchat,
    required this.montantInvesti,
    this.strikeQuoteId,
    this.soldeEURAvant,
    this.soldeEURApres,
    this.soldeEURApresVente,
    this.typeTrade = TypeTrade.ACHAT,
    this.estVente = false,
  });

  double calculerProfitAvecPrixActuel(double prixActuel) {
    if (estVente) return 0.0;
    if (vendu && prixVente != null) {
      return ((prixVente! - prixAchat) / prixAchat) * 100;
    } else if (!vendu) {
      return ((prixActuel - prixAchat) / prixAchat) * 100;
    }
    return 0.0;
  }

  double calculerProfitMonetaire(double prixActuel) {
    if (estVente) return 0.0;
    if (vendu && prixVente != null) {
      return (prixVente! - prixAchat) * quantite;
    } else if (!vendu) {
      return (prixActuel - prixAchat) * quantite;
    }
    return 0.0;
  }


  factory Trade.empty() => Trade(
    id: '',
    prixAchat: 0,
    quantite: 0,
    takeProfit: 0,
    palier: PalierDynamique(
      drawdownMin: 0,
      drawdownMax: 0,
      pourcentageCapital: 0,
      takeProfitPercent: 0,
      nom: '',
      atrValue: 0,
      rsiValue: 0,
      metrics: {},
    ),
    dateAchat: DateTime.now(),
    montantInvesti: 0,
  );

  @override
  String toString() {
    if (estVente) {
      return '💰 VENTE#$id: ${quantite.toStringAsFixed(6)} BTC - Date: $dateAchat';
    }
    final profitPercent = calculerProfitAvecPrixActuel(0);
    final profitMonetaire = calculerProfitMonetaire(0);
    final symbole = profitPercent >= 0 ? '📈' : '📉';
    return '💰 ACHAT#$id: ${palier.nom} - Achat: ${prixAchat.toStringAsFixed(2)}€ - Profit: $symbole ${profitPercent.toStringAsFixed(2)}% (${profitMonetaire.toStringAsFixed(2)}€)';
  }
}

class StrategieEvaluation {
  final double prixActuel;
  final double? prixMax6Mois;
  final double drawdownActuel;
  final PalierDynamique? palierActuel;
  final DecisionAchat decisionAchat;
  final List<DecisionVente> decisionsVente;
  final double capitalDisponible;
  final int tradesOuverts;
  final DateTime timestamp;
  final BalanceStrike? balanceStrike;
  final List<TransactionStrike>? transactionsRecent;
  final Map<String, dynamic>? marketDataEtendu;
  final Map<String, dynamic>? metrics;

  StrategieEvaluation({
    required this.prixActuel,
    required this.prixMax6Mois,
    required this.drawdownActuel,
    required this.palierActuel,
    required this.decisionAchat,
    required this.decisionsVente,
    required this.capitalDisponible,
    required this.tradesOuverts,
    required this.timestamp,
    this.balanceStrike,
    this.transactionsRecent,
    this.marketDataEtendu,
    this.metrics,
  });

  Map<String, dynamic> toJson() {
    return {
      'prixActuel': prixActuel,
      'prixMax6Mois': prixMax6Mois,
      'drawdownActuel': drawdownActuel,
      'palierActuel': palierActuel?.toString(),
      'decisionAchat': decisionAchat.toString(),
      'decisionsVente': decisionsVente.map((d) => d.toString()).toList(),
      'capitalDisponible': capitalDisponible,
      'tradesOuverts': tradesOuverts,
      'timestamp': timestamp.toIso8601String(),
      'balanceStrike': balanceStrike?.toString(),
      'marketDataEtendu': marketDataEtendu,
      'metrics': metrics,
    };
  }
}

class StatistiquesStrategie {
  final int totalTrades;
  final int tradesGagnants;
  final int tradesPerdants;
  final double tauxReussite;
  final double pnlTotal;
  final double pnlTotalPercent;
  final double capitalActuel;
  final int positionsOuvertes;
  final double valeurPositionsOuvertes;
  final double soldeEURReel;
  final double soldeBTCReel;
  final Trade? dernierTrade;

  StatistiquesStrategie({
    required this.totalTrades,
    required this.tradesGagnants,
    required this.tradesPerdants,
    required this.tauxReussite,
    required this.pnlTotal,
    required this.pnlTotalPercent,
    required this.capitalActuel,
    required this.positionsOuvertes,
    required this.valeurPositionsOuvertes,
    required this.soldeEURReel,
    required this.soldeBTCReel,
    this.dernierTrade,
  });

  @override
  String toString() {
    return 'Stats DYNAMIQUES: $totalTrades trades, $tauxReussite% réussite, PnL: ${pnlTotal.toStringAsFixed(2)} (${pnlTotalPercent.toStringAsFixed(2)}%), Capital: ${capitalActuel.toStringAsFixed(2)} EUR';
  }
}

// ===========================================================================
// MODÈLES POUR LA COLLECTE DE DONNÉES (inchangés)
// ===========================================================================

class BTCDataConfig {
  static const int DEFAULT_REQUEST_TIMEOUT = 3;
  static const int DEFAULT_MIN_VALID_SOURCES = 2;
  static const double DEFAULT_OUTLIER_THRESHOLD = 10.0;
  static const Duration DEFAULT_CACHE_TTL = Duration(minutes: 1);
  static const Duration DEFAULT_FALLBACK_TTL = Duration(minutes: 5);
  static const Duration DEFAULT_HISTORICAL_CACHE_TTL = Duration(hours: 6);
  static const double DEFAULT_PRICE_CHANGE_SUSPICIOUS_THRESHOLD = 0.2;

  final int requestTimeout;
  final int minValidSources;
  final double outlierThreshold;
  final Duration cacheTTL;
  final Duration fallbackTTL;
  final Duration historicalCacheTTL;
  final double priceChangeSuspiciousThreshold;

  const BTCDataConfig({
    this.requestTimeout = DEFAULT_REQUEST_TIMEOUT,
    this.minValidSources = DEFAULT_MIN_VALID_SOURCES,
    this.outlierThreshold = DEFAULT_OUTLIER_THRESHOLD,
    this.cacheTTL = DEFAULT_CACHE_TTL,
    this.fallbackTTL = DEFAULT_FALLBACK_TTL,
    this.historicalCacheTTL = DEFAULT_HISTORICAL_CACHE_TTL,
    this.priceChangeSuspiciousThreshold = DEFAULT_PRICE_CHANGE_SUSPICIOUS_THRESHOLD,
  });
}

class HistoricalData {
  double? sixMonthsHigh;
  double? sixMonthsLow;

  HistoricalData({
    this.sixMonthsHigh,
    this.sixMonthsLow,
  });

  Map<String, dynamic> toJson() {
    return {
      'sixMonthsHigh': sixMonthsHigh,
      'sixMonthsLow': sixMonthsLow,
    };
  }

  @override
  String toString() {
    return 'HistoricalData(6mHigh: $sixMonthsHigh, 6mLow: $sixMonthsLow)';
  }
}

class PriceSource {
  final String name;
  final dynamic api;

  PriceSource(this.name, this.api);
}

class SourceResponse {
  final String source;
  final MarketData marketData;
  final double responseTime;
  final DateTime timestamp;
  final bool success;
  final String? error;

  SourceResponse({
    required this.source,
    required this.marketData,
    required this.responseTime,
    required this.timestamp,
    required this.success,
    this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'source': source,
      'marketData': marketData.toJson(),
      'responseTime': responseTime,
      'timestamp': timestamp.toIso8601String(),
      'success': success,
      'error': error,
    };
  }
}


class MarketData {
  double price;
  double? volume;
  double? marketCap;
  double? high24h;
  double? low24h;
  double? priceChange24h;
  double? priceChangePercent24h;

  MarketData({
    required this.price,
    this.volume,
    this.marketCap,
    this.high24h,
    this.low24h,
    this.priceChange24h,
    this.priceChangePercent24h,
  });

  factory MarketData.empty() {
    return MarketData(price: 0.0);
  }

  bool get isValid => price > 0;

  Map<String, dynamic> toJson() {
    return {
      'price': price,
      'volume': volume,
      'marketCap': marketCap,
      'high24h': high24h,
      'low24h': low24h,
      'priceChange24h': priceChange24h,
      'priceChangePercent24h': priceChangePercent24h,
    };
  }

  @override
  String toString() {
    return 'MarketData(price: $price, volume: $volume, marketCap: $marketCap, change24h: $priceChangePercent24h%)';
  }
}

class BTCDataResult {
  final double price;
  final double? volume;
  final double? marketCap;
  final double? high24h;
  final double? low24h;
  final double? priceChange24h;
  final double? priceChangePercent24h;
  final double? sixMonthsHigh;
  final double? sixMonthsLow;
  final int sourcesUsed;
  final int totalSources;
  final DateTime timestamp;
  final List<SourceResponse> sourceDetails;
  final bool cacheUsed;
  final bool historicalDataAvailable;

  BTCDataResult({
    required this.price,
    this.volume,
    this.marketCap,
    this.high24h,
    this.low24h,
    this.priceChange24h,
    this.priceChangePercent24h,
    this.sixMonthsHigh,
    this.sixMonthsLow,
    required this.sourcesUsed,
    required this.totalSources,
    required this.timestamp,
    required this.sourceDetails,
    required this.cacheUsed,
    this.historicalDataAvailable = false,
  });

  BTCDataResult copyWith({
    double? price,
    double? volume,
    double? marketCap,
    double? high24h,
    double? low24h,
    double? priceChange24h,
    double? priceChangePercent24h,
    double? sixMonthsHigh,
    double? sixMonthsLow,
    int? sourcesUsed,
    int? totalSources,
    DateTime? timestamp,
    List<SourceResponse>? sourceDetails,
    bool? cacheUsed,
    bool? historicalDataAvailable,
  }) {
    return BTCDataResult(
      price: price ?? this.price,
      volume: volume ?? this.volume,
      marketCap: marketCap ?? this.marketCap,
      high24h: high24h ?? this.high24h,
      low24h: low24h ?? this.low24h,
      priceChange24h: priceChange24h ?? this.priceChange24h,
      priceChangePercent24h: priceChangePercent24h ?? this.priceChangePercent24h,
      sixMonthsHigh: sixMonthsHigh ?? this.sixMonthsHigh,
      sixMonthsLow: sixMonthsLow ?? this.sixMonthsLow,
      sourcesUsed: sourcesUsed ?? this.sourcesUsed,
      totalSources: totalSources ?? this.totalSources,
      timestamp: timestamp ?? this.timestamp,
      sourceDetails: sourceDetails ?? this.sourceDetails,
      cacheUsed: cacheUsed ?? this.cacheUsed,
      historicalDataAvailable: historicalDataAvailable ?? this.historicalDataAvailable,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'price': price,
      'volume': volume,
      'marketCap': marketCap,
      'high24h': high24h,
      'low24h': low24h,
      'priceChange24h': priceChange24h,
      'priceChangePercent24h': priceChangePercent24h,
      'sixMonthsHigh': sixMonthsHigh,
      'sixMonthsLow': sixMonthsLow,
      'sourcesUsed': sourcesUsed,
      'totalSources': totalSources,
      'timestamp': timestamp.toIso8601String(),
      'cacheUsed': cacheUsed,
      'historicalDataAvailable': historicalDataAvailable,
      'sourceDetails': sourceDetails.map((detail) => detail.toJson()).toList(),
    };
  }

  @override
  String toString() {
    return 'BTCDataResult(price: $price, volume: $volume, marketCap: $marketCap, '
        'change24h: $priceChangePercent24h%, 6mHigh: $sixMonthsHigh, sources: $sourcesUsed/$totalSources)';
  }
}

class BTCDataCache {
  final BTCDataResult data;
  final DateTime timestamp;
  final int sourceCount;

  BTCDataCache({
    required this.data,
    required this.timestamp,
    required this.sourceCount,
  });
}

class SourceScore {
  double reliability;
  double responseTime;
  double consistency;
  DateTime lastUpdate;

  SourceScore({
    required this.reliability,
    required this.responseTime,
    required this.consistency,
    required this.lastUpdate,
  });
}
class SourceRequestStats {
  final int successfulRequests;
  final int totalRequests;
  final DateTime lastRequest;

  SourceRequestStats({
    required this.successfulRequests,
    required this.totalRequests,
    required this.lastRequest,
  });

  double get successRate => totalRequests > 0 ? successfulRequests / totalRequests : 0.0;
}

// NOUVEAU : Cache pour les données historiques
class HistoricalDataCache {
  final double? sixMonthsHigh;
  final double? sixMonthsLow;
  final DateTime timestamp;

  HistoricalDataCache({
    this.sixMonthsHigh,
    this.sixMonthsLow,
    required this.timestamp,
  });
}


class ProfitDataPoint {
  final DateTime date;
  final double profit;
  final double profitCumule;
  final ProfitType type;

  ProfitDataPoint({
    required this.date,
    required this.profit,
    required this.profitCumule,
    required this.type,
  });
}