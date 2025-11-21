// lib/strategie/trading_strategie.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:synchronized/synchronized.dart';
import '../../components/model.dart';
import '../../types/types.dart';
import '../btc_data.dart';
import '../technical_indicators.dart';
import '../../api/strike/strike.dart';

class TradingStrategie {
  static const SafetyBounds BORNES_SECURITE = SafetyBounds(
    minCapitalPercent: 5.0,
    maxCapitalPercent: 70.0,
    minTakeProfitPercent: 5.0,
    maxTakeProfitPercent: 200.0,
    minRSIThreshold: 20.0,
    maxRSIThreshold: 80.0,
  );

  // CONFIGURATION DES INDICATEURS
  static const ATRConfig CONFIG_ATR = ATRConfig(
    period: 14,
    multiplier: 2.0,
    minATRPercent: 0.5,
    maxATRPercent: 3.0,
  );

  static const RSIConfig CONFIG_RSI = RSIConfig(
    period: 14,
    oversold: 30.0,
    overbought: 70.0,
    neutral: 50.0,
  );

  // FACTEURS DE REDIMENSIONNEMENT PAR DRAWDOWN
  static const Map<String, double> FACTEURS_DRAWDOWN = {
    'leger': 1.0,      // -10% à -15%
    'modere': 1.2,     // -15% à -20%
    'fort': 1.5,       // -20% à -25%
    'bear': 2.0,       // -25% à -30%
    'crise': 2.5,      // < -30%
  };

  static const Duration COOLDOWN_ENTRE_ACHATS = Duration(hours: 18);
  static const Duration INTERVALLE_REEVALUATION = Duration(minutes: 10);
  static const double FRAIS_TRADING_FRACTION = 0.0;
  static const double MONTANT_MINIMAL_ACHAT = 0.01;
  static const double MONTANT_MAXIMAL_ACHAT = 5000.0;

  double _drawdownActuel = 0.0;
  PalierDynamique? _palierActuel;
  final List<Trade> historiqueTrades = [];
  DateTime? dernierAchat;
  DateTime derniereReevaluation = DateTime.now();
  PalierDynamique? dernierPalierAchete;
  bool _enCoursExecution = false;
  final StrikeApi strikeApi = StrikeApi();
  final Lock _lock = Lock();

  // Cache pour les données de marché étendues
  BTCDataResult? _dernierBTCData;
  Map<String, dynamic>? _dernierMarketData;

  // Cache pour les indicateurs techniques
  double _atrValue = 0.0;
  double _rsiValue = 50.0;
  DateTime _lastIndicatorUpdate = DateTime.now();

  void _initialiserDernierAchatDepuisHistorique() {
    if (historiqueTrades.isEmpty) {
      dernierAchat = null;
      dernierPalierAchete = null;
      return;
    }

    Trade? dernierTradeAchat;
    for (var trade in historiqueTrades) {
      if (trade.typeTrade == TypeTrade.ACHAT && !trade.estVente) {
        if (dernierTradeAchat == null || trade.dateAchat.isAfter(dernierTradeAchat.dateAchat)) {
          dernierTradeAchat = trade;
        }
      }
    }

    if (dernierTradeAchat != null) {
      dernierAchat = dernierTradeAchat.dateAchat;
      dernierPalierAchete = dernierTradeAchat.palier;
    }
  }

  TradingStrategie();

  Future<void> rechargerDonneesCompletes() async {
    _enCoursExecution = false;
    await chargerHistoriqueStrike();
    historiqueTrades.removeWhere((trade) => trade.id.contains('INVALIDE'));
  }

  void mettreAJourProfits(double prixActuel) {
    for (var trade in historiqueTrades) {
      if (trade.estVente) continue;
      final profitPercent = trade.calculerProfitAvecPrixActuel(prixActuel);
      final profitMonetaire = trade.calculerProfitMonetaire(prixActuel);
    }
  }

  void resetExecutionLock() {
    _enCoursExecution = false;
  }

  Future<void> rechargerHistorique() async {
    await chargerHistoriqueStrike();
    nettoyerTradesAberrants();
  }

  // NOUVELLE MÉTHODE : Calcul des indicateurs techniques
  Future<void> _calculerIndicateursTechniques(double prixActuel) async {
    try {
      if (DateTime.now().difference(_lastIndicatorUpdate) < Duration(minutes: 10)) {
        return;
      }

      // Récupérer les données OHLC (simulation - à adapter avec votre source de données)
      final ohlcData = await TechnicalIndicators.fetchOHLCData(30);
      final closePrices = await TechnicalIndicators.fetchClosePrices(30);

      // Calculer ATR
      if (ohlcData.length > CONFIG_ATR.period) {
        _atrValue = TechnicalIndicators.calculateATR(ohlcData, CONFIG_ATR.period);
      }

      // Calculer RSI
      if (closePrices.length > CONFIG_RSI.period) {
        _rsiValue = TechnicalIndicators.calculateRSI(closePrices, CONFIG_RSI.period);
      }

      _lastIndicatorUpdate = DateTime.now();

    } catch (e) {
      print('⚠️ Erreur calcul indicateurs techniques: $e');
      _atrValue = prixActuel * 0.02;
      _rsiValue = 50.0;
    }
  }

  PalierDynamique _genererPalierDynamique(double drawdownActuel, double prixActuel) {
    final drawdownAbsolu = drawdownActuel.abs();

    double facteurDrawdown = 1.0;
    if (drawdownAbsolu <= 15.0) facteurDrawdown = FACTEURS_DRAWDOWN['leger']!;
    else if (drawdownAbsolu <= 20.0) facteurDrawdown = FACTEURS_DRAWDOWN['modere']!;
    else if (drawdownAbsolu <= 25.0) facteurDrawdown = FACTEURS_DRAWDOWN['fort']!;
    else if (drawdownAbsolu <= 30.0) facteurDrawdown = FACTEURS_DRAWDOWN['bear']!;
    else facteurDrawdown = FACTEURS_DRAWDOWN['crise']!;

    // AJUSTEMENT PAR ATR - Base pour les décisions
    final atrPercent = (_atrValue / prixActuel) * 100;

    // AJUSTEMENT PAR RSI - Influence l'agressivité
    double ajustementRSI = 1.0;
    if (_rsiValue < CONFIG_RSI.oversold) {
      // Conditions de survente - plus agressif
      ajustementRSI = 1.3;
    } else if (_rsiValue > CONFIG_RSI.overbought) {
      // Conditions de surachat - plus conservateur
      ajustementRSI = 0.7;
    } else {
      // Zone neutre - ajustement linéaire
      final distanceFromNeutral = (_rsiValue - CONFIG_RSI.neutral).abs() / (CONFIG_RSI.neutral - CONFIG_RSI.oversold);
      ajustementRSI = 1.0 + (0.3 * (1 - distanceFromNeutral));
    }

    // CALCUL DES PARAMÈTRES FINAUX AVEC BORNES DE SÉCURITÉ
    final pourcentageCapital = _calculerPourcentageCapital(
        drawdownAbsolu,
        facteurDrawdown,
        ajustementRSI
    );

    // SUPPRESSION COMPLÈTE DU STOP-LOSS
    // Calcul du take-profit uniquement
    final takeProfitPercent = _calculerTakeProfitPercentDynamique(
        drawdownAbsolu,
        ajustementRSI
    );

    // CALCUL DU SCORE DE CONFIANCE
    final metrics = _calculerMetricsConfiance(
        drawdownAbsolu,
        atrPercent,
        _rsiValue,
        pourcentageCapital,
        takeProfitPercent
    );

    return PalierDynamique(
      drawdownMin: drawdownActuel - 2.0, // Marge de 2%
      drawdownMax: drawdownActuel + 2.0,
      pourcentageCapital: pourcentageCapital,
      takeProfitPercent: takeProfitPercent,
      nom: _getNomPalier(drawdownAbsolu),
      atrValue: _atrValue,
      rsiValue: _rsiValue,
      metrics: metrics,
    );
  }

  double _calculerPourcentageCapital(double drawdownAbsolu, double facteurDrawdown, double ajustementRSI) {
    // Base progressive selon le drawdown
    double basePercent;
    if (drawdownAbsolu <= 15.0) basePercent = 10.0;
    else if (drawdownAbsolu <= 20.0) basePercent = 20.0;
    else if (drawdownAbsolu <= 25.0) basePercent = 30.0;
    else if (drawdownAbsolu <= 30.0) basePercent = 40.0;
    else basePercent = 50.0;

    // Application des facteurs
    final percentFinal = basePercent * facteurDrawdown * ajustementRSI;

    // Application des bornes de sécurité
    return percentFinal.clamp(BORNES_SECURITE.minCapitalPercent, BORNES_SECURITE.maxCapitalPercent);
  }

  // NOUVELLE MÉTHODE : Calcul du take-profit sans stop-loss
  double _calculerTakeProfitPercentDynamique(double drawdownAbsolu, double ajustementRSI) {
    // Take-profit basé sur le drawdown et la volatilité
    double baseTakeProfit;
    if (drawdownAbsolu <= 15.0) baseTakeProfit = 8.0;
    else if (drawdownAbsolu <= 20.0) baseTakeProfit = 12.0;
    else if (drawdownAbsolu <= 25.0) baseTakeProfit = 18.0;
    else if (drawdownAbsolu <= 30.0) baseTakeProfit = 25.0;
    else baseTakeProfit = 35.0;

    // Ajustement par volatilité (ATR) - plus de volatilité = take-profit plus élevé
    final ajustementVolatilite = math.max(0.8, math.min(1.5, _atrValue / 1000));

    final takeProfitPercent = baseTakeProfit * ajustementRSI * ajustementVolatilite;

    return takeProfitPercent.clamp(BORNES_SECURITE.minTakeProfitPercent, BORNES_SECURITE.maxTakeProfitPercent);
  }

  Map<String, dynamic> _calculerMetricsConfiance(
      double drawdownAbsolu,
      double atrPercent,
      double rsiValue,
      double capitalPercent,
      double takeProfitPercent
      ) {
    // Score volatilité
    final scoreVolatilite = math.max(0, 100 - (atrPercent * 15));

    // Score momentum basé sur RSI
    double scoreMomentum;
    if (rsiValue > 70) {
      scoreMomentum = 60 - ((rsiValue - 70) * 2);
    } else if (rsiValue > 50) {
      scoreMomentum = 40 + ((rsiValue - 50) * 1);
    } else if (rsiValue > 30) {
      scoreMomentum = 60 - ((50 - rsiValue) * 1);
    } else {
      scoreMomentum = 40 - ((30 - rsiValue) * 2);
    }
    scoreMomentum = scoreMomentum.clamp(0, 100);

    // Score drawdown
    double scoreDrawdown;
    if (drawdownAbsolu <= 5.0) {
      scoreDrawdown = 90 - (drawdownAbsolu * 4);
    } else if (drawdownAbsolu <= 15.0) {
      scoreDrawdown = 70 - ((drawdownAbsolu - 5) * 4);
    } else if (drawdownAbsolu <= 25.0) {
      scoreDrawdown = 30 - ((drawdownAbsolu - 15) * 3);
    } else {
      scoreDrawdown = 0;
    }
    scoreDrawdown = scoreDrawdown.clamp(0, 100);

    // Score take-profit (objectif de gain)
    final scoreTakeProfit = math.min(100, takeProfitPercent * 3);

    // Score global sans stop-loss
    final scoreGlobal = (
        scoreVolatilite * 0.20 +
            scoreMomentum * 0.25 +
            scoreDrawdown * 0.40 +
            scoreTakeProfit * 0.15
    );

    return {
      'scoreGlobal': scoreGlobal.roundToDouble(),
      'scoreVolatilite': scoreVolatilite.roundToDouble(),
      'scoreMomentum': scoreMomentum.roundToDouble(),
      'scoreDrawdown': scoreDrawdown.roundToDouble(),
      'scoreTakeProfit': scoreTakeProfit.roundToDouble(),
      'takeProfitPercent': takeProfitPercent.toStringAsFixed(1) + '%',
      'atrPercent': atrPercent.toStringAsFixed(2) + '%',
      'rsiValue': rsiValue.toStringAsFixed(2),
      'drawdownAbsolu': drawdownAbsolu.toStringAsFixed(2) + '%',
      'confidenceLevel': _getNiveauConfiance(scoreGlobal),
    };
  }

  String _getNiveauConfiance(double score) {
    if (score >= 80) return 'TRÈS ÉLEVÉE';
    if (score >= 60) return 'ÉLEVÉE';
    if (score >= 40) return 'MOYENNE';
    if (score >= 20) return 'FAIBLE';
    return 'TRÈS FAIBLE';
  }

  String _getNomPalier(double drawdownAbsolu) {
    if (drawdownAbsolu <= 15.0) return "Correction légère ATR+RSI";
    if (drawdownAbsolu <= 20.0) return "Correction modérée ATR+RSI";
    if (drawdownAbsolu <= 25.0) return "Correction forte ATR+RSI";
    if (drawdownAbsolu <= 30.0) return "Bear market ATR+RSI";
    return "Crise majeure ATR+RSI";
  }

  // CORRECTION : Méthode pour calculer le prix de take-profit
  double _calculerPrixTakeProfit(double prixAchat, PalierDynamique palier) {
    return prixAchat * (1 + palier.takeProfitPercent / 100);
  }

  // MÉTHODE EXISTANTE MODIFIÉE : Récupérer les données de marché étendues
  Future<Map<String, dynamic>> _getMarketDataEtendu() async {
    try {
      final btcData = await BTCDataService.getBitcoinData();
      _dernierBTCData = btcData;

      final marketData = await BTCDataService.getBitcoinMarketData();
      _dernierMarketData = marketData;

      // Calcul des indicateurs techniques
      await _calculerIndicateursTechniques(btcData.price);

      return {
        'prixActuel': btcData.price,
        'prixMax6Mois': btcData.sixMonthsHigh,
        'prixMin6Mois': btcData.sixMonthsLow,
        'volume24h': btcData.volume,
        'change24h': btcData.priceChangePercent24h,
        'high24h': btcData.high24h,
        'low24h': btcData.low24h,
        'volatilite': _atrValue / btcData.price,
        'rsi': _rsiValue,
        'atr': _atrValue,
        'timestamp': DateTime.now(),
      };
    } catch (e) {
      print('❌ Erreur récupération données marché étendues: $e');
      return {
        'prixActuel': 0.0,
        'volatilite': 0.0,
        'rsi': 50.0,
        'atr': 0.0,
        'timestamp': DateTime.now(),
      };
    }
  }

  // MÉTHODE PRINCIPALE MODIFIÉE : Évaluation du marché
  Future<StrategieEvaluation> evaluerMarche() async {
    return _lock.synchronized(() async {
      _enCoursExecution = true;

      try {
        await chargerHistoriqueStrike();
        final marketDataEtendu = await _getMarketDataEtendu();
        final balanceStrike = await _getBalanceStrike();
        final transactionsRecent = await _getTransactionsRecent();

        mettreAJourProfits(marketDataEtendu['prixActuel']);

        if (marketDataEtendu['prixMax6Mois'] == null) {
          _drawdownActuel = 0.0;
          _palierActuel = null;
          return StrategieEvaluation(
            prixActuel: marketDataEtendu['prixActuel'],
            prixMax6Mois: null,
            drawdownActuel: 0.0,
            palierActuel: null,
            decisionAchat: DecisionAchat(
              acheter: false,
              raison: 'Données historiques non disponibles',
            ),
            decisionsVente: [],
            capitalDisponible: balanceStrike.soldeEUR,
            tradesOuverts: historiqueTrades.where((t) => !t.vendu).length,
            timestamp: DateTime.now(),
            balanceStrike: balanceStrike,
            transactionsRecent: transactionsRecent,
          );
        }

        final prixMax6Mois = marketDataEtendu['prixMax6Mois']!.toDouble();
        final drawdownActuel = _calculerDrawdownCorrige(marketDataEtendu['prixActuel'], prixMax6Mois);

        // GÉNÉRATION DYNAMIQUE DU PALIER
        final palierActuel = _genererPalierDynamique(drawdownActuel, marketDataEtendu['prixActuel']);

        _drawdownActuel = drawdownActuel;
        _palierActuel = palierActuel;

        analyserOpportunites(palierActuel, drawdownActuel);

        final decisionAchat = await _evaluerConditionsAchatReel(
          palierActuel,
          drawdownActuel,
          marketDataEtendu['prixActuel'],
          balanceStrike.soldeEUR,
          marketDataEtendu,
        );

        final decisionsVente = await _evaluerConditionsVenteAmeliorees(
          marketDataEtendu['prixActuel'],
          marketDataEtendu,
        );

        return StrategieEvaluation(
          prixActuel: marketDataEtendu['prixActuel'],
          prixMax6Mois: prixMax6Mois,
          drawdownActuel: drawdownActuel,
          palierActuel: palierActuel,
          decisionAchat: decisionAchat,
          decisionsVente: decisionsVente,
          capitalDisponible: balanceStrike.soldeEUR,
          tradesOuverts: historiqueTrades.where((t) => !t.vendu).length,
          timestamp: DateTime.now(),
          balanceStrike: balanceStrike,
          transactionsRecent: transactionsRecent,
          marketDataEtendu: marketDataEtendu,
          metrics: palierActuel.metrics,
        );
      } catch (e) {
        print('❌ Erreur lors de l\'évaluation de la stratégie: $e');
        return _creerEvaluationErreur('Erreur d\'évaluation: $e');
      } finally {
        _enCoursExecution = false;
        print('🔓 Verrou libéré');
      }
    });
  }

  StrategieEvaluation _creerEvaluationErreur(String message) {
    return StrategieEvaluation(
      prixActuel: 0.0,
      prixMax6Mois: null,
      drawdownActuel: 0.0,
      palierActuel: null,
      decisionAchat: DecisionAchat(
        acheter: false,
        raison: message,
      ),
      decisionsVente: [],
      capitalDisponible: 0.0,
      tradesOuverts: 0,
      timestamp: DateTime.now(),
      balanceStrike: null,
      transactionsRecent: [],
    );
  }

  double _calculerDrawdownCorrige(double prixActuel, double prixMax6Mois) {
    if (prixMax6Mois == 0.0) return 0.0;
    final drawdown = ((prixActuel - prixMax6Mois) / prixMax6Mois) * 100;
    return double.parse(drawdown.toStringAsFixed(2));
  }

  Future<DecisionAchat> _evaluerConditionsAchatReel(
      PalierDynamique? palierActuel,
      double drawdownActuel,
      double prixActuel,
      double capitalReel,
      Map<String, dynamic> marketData,
      ) async {

    if (capitalReel < 0.01) {
      return DecisionAchat(
        acheter: false,
        raison: 'Capital insuffisant (${capitalReel.toStringAsFixed(2)} EUR)',
      );
    }

    if (palierActuel == null) {
      return DecisionAchat(
        acheter: false,
        raison: 'Drawdown (${drawdownActuel.toStringAsFixed(2)}%) hors des paliers d\'achat',
      );
    }

    // VÉRIFICATION CONDITIONS DE MARCHÉ POUR L'ACHAT
    final rsi = marketData['rsi'] ?? 50.0;

    if (rsi > BORNES_SECURITE.maxRSIThreshold) {
      return DecisionAchat(
        acheter: false,
        raison: 'Conditions de surachat détectées (RSI: ${rsi.toStringAsFixed(1)})',
      );
    }

    final maintenant = DateTime.now();
    final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);

    if (dernierAchat != null && dernierPalierAchete != null) {
      final dernierAchatDate = DateTime(dernierAchat!.year, dernierAchat!.month, dernierAchat!.day);
      final memeDate = dernierAchatDate == aujourdhui;
      final memeDrawdown = dernierPalierAchete!.nom == palierActuel.nom;

      if (memeDate && memeDrawdown) {
        return DecisionAchat(
          acheter: false,
          raison: 'Achat déjà effectué aujourd\'hui pour le drawdown ${palierActuel.nom}',
        );
      }
    }

    if (_dejaAchetePalierRecemment(palierActuel)) {
      return DecisionAchat(
        acheter: false,
        raison: 'Palier ${palierActuel.nom} déjà acheté récemment (limite 7 jours)',
      );
    }

    final montantInvestissement = _calculerMontantInvestissementReel(palierActuel, capitalReel);

    if (montantInvestissement < 0.01) {
      return DecisionAchat(
        acheter: false,
        raison: 'Montant d\'investissement trop faible (${montantInvestissement.toStringAsFixed(2)} EUR)',
      );
    }

    if (montantInvestissement > MONTANT_MAXIMAL_ACHAT) {
      return DecisionAchat(
        acheter: false,
        raison: 'Montant d\'investissement trop élevé (${montantInvestissement.toStringAsFixed(2)} EUR)',
      );
    }

    if (montantInvestissement > capitalReel) {
      return DecisionAchat(
        acheter: false,
        raison: 'Solde EUR insuffisant (${capitalReel.toStringAsFixed(2)} disponible)',
      );
    }

    // CALCUL DES NIVEAUX DYNAMIQUES - SUPPRESSION DU STOP-LOSS
    final takeProfitDynamique = _calculerPrixTakeProfit(prixActuel, palierActuel);

    final takeProfitPercent = ((takeProfitDynamique - prixActuel) / prixActuel * 100);

    return DecisionAchat(
      acheter: true,
      raison: 'Conditions dynamiques remplies pour le palier ${palierActuel.nom}',
      palier: palierActuel,
      montantInvestissement: montantInvestissement,
      prixCibleAchat: _calculerPrixCibleAchat(prixActuel),
      takeProfit: takeProfitDynamique,
      fraisEstimes: 0.0,
      capitalReel: capitalReel,
      metrics: {
        'atr': '${_atrValue.toStringAsFixed(2)} (${(_atrValue / prixActuel * 100).toStringAsFixed(2)}%)',
        'rsi': _rsiValue.toStringAsFixed(1),
        'takeProfitPercent': takeProfitPercent.toStringAsFixed(1) + '%',
        'drawdownActuel': drawdownActuel.toStringAsFixed(1) + '%',
        'scoreGlobal': palierActuel.metrics['scoreGlobal'].toString(),
        'confidenceLevel': palierActuel.metrics['confidenceLevel'],
      },
    );
  }

  double _calculerMontantInvestissementReel(PalierDynamique palier, double capitalReel) {
    final montantTheorique = capitalReel * (palier.pourcentageCapital / 100);
    return _arrondirMontantFinancier(montantTheorique);
  }

  double _arrondirMontantFinancier(double montant) {
    return (montant * 100).round() / 100.0;
  }

  double _calculerPrixCibleAchat(double prixActuel) {
    return prixActuel * 0.995;
  }

  bool _dejaAchetePalierRecemment(PalierDynamique palier) {
    final maintenant = DateTime.now();
    final limiteJours = Duration(days: 7);

    final achatRecent = historiqueTrades.any((trade) {
      final memePalier = trade.palier.nom == palier.nom;
      final recent = maintenant.difference(trade.dateAchat) < limiteJours;
      final pasVendu = !trade.vendu;
      return memePalier && recent && pasVendu;
    });

    if (achatRecent) {
      print('⚠️ Achat récent détecté pour le palier ${palier.nom}');
    }

    return achatRecent;
  }

  Future<BalanceStrike> _getBalanceStrike() async {
    try {
      final response = await strikeApi.getBalances().timeout(Duration(seconds: 15));

      if (response is! List || response.isEmpty) {
        throw Exception('Format de réponse Balance Strike invalide ou vide');
      }

      double soldeEUR = 0.0;
      double soldeBTC = 0.0;
      bool foundEUR = false;
      bool foundBTC = false;

      for (var balance in response) {
        if (balance['currency'] == 'EUR') {
          soldeEUR = _parseMontantSecurise(balance['available'], decimales: 2);
          foundEUR = true;
        } else if (balance['currency'] == 'BTC') {
          soldeBTC = _parseMontantSecurise(balance['available'], decimales: 8);
          foundBTC = true;
        }
      }

      if (!foundEUR) {
        print('⚠️ Devise EUR non trouvée dans la balance Strike');
      }
      if (!foundBTC) {
        print('⚠️ Devise BTC non trouvée dans la balance Strike');
      }

      return BalanceStrike(
        soldeEUR: soldeEUR,
        soldeBTC: soldeBTC,
        dernierUpdate: DateTime.now(),
      );
    } catch (e) {
      print('❌ Erreur critique récupération balance Strike: $e');
      return BalanceStrike(
        soldeEUR: 0.0,
        soldeBTC: 0.0,
        dernierUpdate: DateTime.now(),
        erreur: e.toString(),
      );
    }
  }

  double _parseMontantSecurise(dynamic montant, {int decimales = 2}) {
    try {
      if (montant == null) return 0.0;
      final parsed = double.tryParse(montant.toString()) ?? 0.0;
      return double.parse(parsed.toStringAsFixed(decimales));
    } catch (e) {
      print('❌ Erreur parsing montant: $montant - $e');
      return 0.0;
    }
  }

  Future<List<TransactionStrike>> _getTransactionsRecent() async {
    try {
      final response = await strikeApi.getInvoices().timeout(Duration(seconds: 10));
      final List<TransactionStrike> transactions = [];

      List<dynamic> invoices = [];
      if (response is Map<String, dynamic> && response.containsKey('items')) {
        invoices = response['items'] as List<dynamic>;
      } else if (response is List) {
        invoices = response;
      } else {
        return [];
      }

      for (var invoice in invoices.take(20)) {
        try {
          final description = invoice['description']?.toString() ?? '';
          if (description.contains('BTC') || description.contains('ACHAT') || description.contains('VENTE')) {
            transactions.add(TransactionStrike(
              id: invoice['invoiceId']?.toString() ?? invoice['id']?.toString() ?? 'INCONNU',
              montant: _parseMontantSecurise(invoice['amount']?['amount']),
              devise: invoice['amount']?['currency']?.toString() ?? 'EUR',
              type: _determinerTypeTransaction(invoice),
              statut: invoice['state']?.toString() ?? invoice['status']?.toString() ?? 'INCONNU',
              date: DateTime.tryParse(invoice['created']?.toString() ?? invoice['createdDate']?.toString() ?? '') ?? DateTime.now(),
              description: description,
            ));
          }
        } catch (e) {
          print('❌ Erreur parsing transaction: $e');
          continue;
        }
      }
      return transactions;
    } catch (e) {
      print('❌ Erreur récupération transactions Strike: $e');
      return [];
    }
  }

  TypeTransaction _determinerTypeTransaction(Map<String, dynamic> invoice) {
    final type = invoice['type']?.toString() ?? '';
    final description = invoice['description']?.toString() ?? '';

    final typeLower = type.toLowerCase();
    final descLower = description.toLowerCase();

    if (typeLower.contains('payment') || typeLower.contains('pay') || descLower.contains('achat') || descLower.contains('buy')) {
      return TypeTransaction.PAIEMENT;
    } else if (typeLower.contains('exchange') || descLower.contains('change') || descLower.contains('swap')) {
      return TypeTransaction.ECHANGE;
    } else {
      return TypeTransaction.FACTURE;
    }
  }

  void analyserOpportunites(PalierDynamique? palierActuel, double drawdownActuel) {
    final tradesParPalier = <String, int>{};
    for (var trade in historiqueTrades.where((t) => !t.vendu)) {
      tradesParPalier[trade.palier.nom] = (tradesParPalier[trade.palier.nom] ?? 0) + 1;
    }
  }
  Future<Trade> executerAchatStrike(DecisionAchat decision) async {
    if (!decision.acheter) {
      throw Exception('Tentative d\'exécution d\'un achat non autorisé: ${decision.raison}');
    }

    return _lock.synchronized(() async {
      // VÉRIFICATION RENFORCÉE DU VERROU
      if (_enCoursExecution) {
        throw Exception('❌ Une exécution est déjà en cours. Veuillez attendre la fin de l\'opération en cours.');
      }

      _enCoursExecution = true;
      String? quoteId = null;

      try {
        print('🔒 Début de l\'exécution d\'achat - Verrou acquis');

        // VÉRIFICATION PRÉLIMINAIRE DE BALANCE
        final balanceActuelle = await _getBalanceStrike();
        double montantInvestissementAjuste = decision.montantInvestissement!;

        if (montantInvestissementAjuste > balanceActuelle.soldeEUR) {
          final maxInvest = balanceActuelle.soldeEUR * 0.99;
          if (maxInvest < 0.01) {
            throw Exception('Solde EUR insuffisant pour acheter BTC. Disponible: ${balanceActuelle.soldeEUR.toStringAsFixed(2)} EUR');
          }
          montantInvestissementAjuste = maxInvest;
          print('⚠️ Ajustement du montant d\'investissement à ${maxInvest.toStringAsFixed(2)} EUR');
        }

        if (montantInvestissementAjuste < 0.01) {
          throw Exception('Montant d\'investissement trop faible: ${montantInvestissementAjuste.toStringAsFixed(2)} EUR');
        }

        if (montantInvestissementAjuste > MONTANT_MAXIMAL_ACHAT) {
          throw Exception('Montant d\'investissement trop élevé: ${montantInvestissementAjuste.toStringAsFixed(2)} EUR');
        }

        final btcData = await BTCDataService.getBitcoinData();
        final drawdownActuel = _calculerDrawdownCorrige(btcData.price, btcData.sixMonthsHigh!.toDouble());

        final quoteData = {
          'amount': montantInvestissementAjuste.toStringAsFixed(2),
        };

        // CRÉATION DE QUOTE AVEC RETRY
        print('🔄 Création du devis de change...');
        final quoteResponse = await strikeApi.createCurrencyExchangeQuote(quoteData);

        if (quoteResponse == null) {
          throw Exception('Réponse nulle lors de la création du devis');
        }

        quoteId = quoteResponse['id']?.toString();
        if (quoteId == null) {
          throw Exception('Échec création devis de change RÉEL - ID manquant');
        }

        print('✅ Devis créé - ID: $quoteId');

        // VÉRIFICATION SI CETTE QUOTE A DÉJÀ ÉTÉ EXÉCUTÉE
        final existingTrade = historiqueTrades.firstWhere(
              (trade) => trade.strikeQuoteId == quoteId,
          orElse: () => Trade.empty(),
        );

        if (existingTrade.id.isNotEmpty) {
          throw Exception('❌ Cette transaction a déjà été exécutée (quote ID: $quoteId)');
        }

        double prixReelAchat = 0.0;
        double quantiteReelle = 0.0;

        if (quoteResponse['conversionRate'] != null && quoteResponse['conversionRate']['amount'] != null) {
          final conversionRate = _parseMontantSecurise(quoteResponse['conversionRate']['amount'], decimales: 10);
          if (conversionRate > 0) {
            prixReelAchat = 1.0 / conversionRate;
            quantiteReelle = montantInvestissementAjuste * conversionRate;
          }
        }

        if (prixReelAchat == 0 && quoteResponse['source'] != null && quoteResponse['target'] != null) {
          final montantSource = _parseMontantSecurise(quoteResponse['source']['amount'], decimales: 2);
          final montantTarget = _parseMontantSecurise(quoteResponse['target']['amount'], decimales: 8);

          if (montantSource > 0 && montantTarget > 0) {
            if (quoteResponse['source']['currency'] == 'EUR' && quoteResponse['target']['currency'] == 'BTC') {
              prixReelAchat = montantSource / montantTarget;
              quantiteReelle = montantTarget;
            }
          }
        }

        if (prixReelAchat == 0 || quantiteReelle == 0) {
          throw Exception('Impossible d\'extraire le taux de change du devis Strike');
        }

        // EXÉCUTION DE LA QUOTE
        print('🔄 Exécution de la quote $quoteId...');
        final executionResponse = await strikeApi.executeCurrencyExchangeQuote(quoteId);
        print('✅ Réponse d\'exécution: $executionResponse');

        // ATTENTE ROBUSTE DE LA COMPLÉTION
        await strikeApi.attendreCompletionQuote(quoteId);

        // VÉRIFICATION FINALE
        final quoteFinale = await strikeApi.getCurrencyExchangeQuote(quoteId);
        final stateFinal = quoteFinale?['state']?.toString();

        if (stateFinal != 'COMPLETED') {
          throw Exception('Échec de l\'exécution du devis: état final $stateFinal');
        }

        await _calculerIndicateursTechniques(prixReelAchat);

        // CRÉATION DE LA FACTURE (optionnel)
        final invoiceData = {
          'correlationId': quoteId,
          'description': _formaterDescriptionAchat(decision.palier!, quantiteReelle, prixReelAchat, drawdownActuel),
          'amount': montantInvestissementAjuste.toStringAsFixed(2),
          'currency': 'EUR',
        };

        try {
          await strikeApi.createInvoice(invoiceData);
          print('✅ Facture créée avec succès');
        } catch (e) {
          print('⚠️ Erreur création facture (non critique): $e');
        }

        final nouvelleBalance = await _getBalanceStrike();

        // CRÉATION DU TRADE
        final trade = Trade(
          id: 'REEL_${DateTime.now().millisecondsSinceEpoch}',
          prixAchat: prixReelAchat,
          quantite: quantiteReelle,
          takeProfit: decision.takeProfit!,
          palier: decision.palier!,
          dateAchat: DateTime.now(),
          montantInvesti: montantInvestissementAjuste,
          strikeQuoteId: quoteId,
          soldeEURAvant: balanceActuelle.soldeEUR,
          soldeEURApres: nouvelleBalance.soldeEUR,
        );

        // AJOUT DU TRADE À L'HISTORIQUE
        historiqueTrades.add(trade);
        dernierAchat = DateTime.now();
        dernierPalierAchete = decision.palier;

        print('🎉 ACHAT RÉUSSI - ${quantiteReelle.toStringAsFixed(8)} BTC à ${prixReelAchat.toStringAsFixed(2)} EUR');
        print('💶 Montant investi: ${montantInvestissementAjuste.toStringAsFixed(2)} EUR');
        print('📈 Take-profit: ${decision.takeProfit!.toStringAsFixed(2)} EUR');

        return trade;
      } catch (e) {
        print('❌ ERREUR EXÉCUTION ACHAT: $e');

        // ANNULATION SI ERREUR APRÈS CRÉATION DE QUOTE
        if (quoteId != null) {
          print('🔄 Tentative d\'annulation de la quote $quoteId...');
          try {
            final quoteStatus = await strikeApi.getCurrencyExchangeQuote(quoteId);
            final state = quoteStatus?['state']?.toString();
            print('ℹ️ État de la quote après erreur: $state');
          } catch (cancelError) {
            print('⚠️ Impossible de vérifier l\'état de la quote après erreur: $cancelError');
          }
        }

        rethrow;
      } finally {
        _enCoursExecution = false;
        print('🔓 Verrou libéré - Exécution terminée');
      }
    });
  }

  Future<void> executerVenteStrike(DecisionVente decision) async {
    if (!decision.vendre) {
      throw Exception('Tentative d\'exécution d\'une vente non autorisée: ${decision.raison}');
    }

    return _lock.synchronized(() async {
      if (_enCoursExecution) {
        throw Exception('Une exécution est déjà en cours');
      }

      _enCoursExecution = true;

      try {
        final trade = decision.trade;

        final balanceActuelle = await _getBalanceStrike();
        if (trade.quantite > balanceActuelle.soldeBTC) {
          throw Exception('Solde BTC insuffisant. Disponible: ${balanceActuelle.soldeBTC.toStringAsFixed(6)} BTC, Requis: ${trade.quantite.toStringAsFixed(6)} BTC');
        }

        final btcData = await BTCDataService.getBitcoinData();
        final drawdownActuel = _calculerDrawdownCorrige(btcData.price, btcData.sixMonthsHigh!.toDouble());

        final quoteData = {
          'sourceCurrency': 'BTC',
          'targetCurrency': 'EUR',
          'amount': trade.quantite.toStringAsFixed(8),
        };

        // CRÉATION DE QUOTE AVEC RETRY
        final quoteResponse = await strikeApi.createCurrencyExchangeQuote(quoteData);

        if (quoteResponse == null) {
          throw Exception('Réponse nulle lors de la création du devis de vente');
        }

        final quoteId = quoteResponse['id']?.toString();
        if (quoteId == null) {
          throw Exception('Échec création devis de vente RÉEL - ID manquant');
        }

        final prixReelVente = _parseMontantSecurise(quoteResponse['exchangeRate'], decimales: 6);
        if (prixReelVente == 0.0) {
          throw Exception('Taux de change invalide reçu pour la vente');
        }

        // EXÉCUTION DE LA QUOTE
        print('🔄 Exécution de la vente quote $quoteId...');
        final executionResponse = await strikeApi.executeCurrencyExchangeQuote(quoteId);

        if (executionResponse == null) {
          throw Exception('Réponse nulle lors de l\'exécution du devis de vente');
        }

        // ATTENTE ROBUSTE DE LA COMPLÉTION
        await strikeApi.attendreCompletionQuote(quoteId);

        // VÉRIFICATION FINALE
        final quoteFinale = await strikeApi.getCurrencyExchangeQuote(quoteId);
        final stateFinal = quoteFinale?['state']?.toString();

        if (stateFinal != 'COMPLETED') {
          throw Exception('Échec de l\'exécution du devis de vente: état final $stateFinal');
        }

        final nouvelleBalance = await _getBalanceStrike();

        final montantVenteEUR = trade.quantite * prixReelVente;
        final frais = montantVenteEUR * FRAIS_TRADING_FRACTION;
        final montantNet = montantVenteEUR - frais;

        trade.vendu = true;
        trade.dateVente = DateTime.now();
        trade.prixVente = prixReelVente;
        trade.montantVente = montantNet;
        trade.typeVente = decision.typeVente;
        trade.strikeQuoteId = quoteId;
        trade.soldeEURApresVente = nouvelleBalance.soldeEUR;

        final pnl = montantNet - trade.montantInvesti;
        final pnlPercent = (pnl / trade.montantInvesti) * 100;

        final invoiceData = {
          'correlationId': quoteId,
          'description': _formaterDescriptionVente(trade.quantite, prixReelVente, drawdownActuel, pnlPercent),
          'amount': trade.quantite.toStringAsFixed(8),
          'currency': 'BTC',
        };

        try {
          await strikeApi.createInvoice(invoiceData);
        } catch (e) {
          print('⚠️ Erreur création facture de vente (non critique): $e');
        }

        print('✅ Vente exécutée avec succès - ${trade.quantite.toStringAsFixed(8)} BTC à ${prixReelVente.toStringAsFixed(2)} EUR - PnL: ${pnlPercent.toStringAsFixed(2)}%');

      } catch (e) {
        print('❌ ERREUR EXÉCUTION VENTE DYNAMIQUE RÉELLE: $e');
        rethrow;
      } finally {
        _enCoursExecution = false;
      }
    });
  }

  String _formaterDescriptionAchat(PalierDynamique palier, double quantiteBTC, double prixAchat, double drawdownActuel) {
    return 'STRATÉGIE ACHAT BTC:${quantiteBTC.toStringAsFixed(8)}, EUR:${prixAchat.toStringAsFixed(2)}, Drawdown%:${drawdownActuel.toStringAsFixed(2)}';
  }

  String _formaterDescriptionVente(double quantiteBTC, double prixVente, double drawdownActuel, double pnlPercent) {
    return 'STRATÉGIE VENTE BTC:${quantiteBTC.toStringAsFixed(8)}, EUR:${prixVente.toStringAsFixed(2)}, Drawdown%:${drawdownActuel.toStringAsFixed(2)}, PnL%:${pnlPercent.toStringAsFixed(2)}';
  }

  Future<void> chargerHistoriqueStrike() async {
    try {
      final response = await strikeApi.getInvoices();
      List<dynamic> invoices = [];
      if (response is Map<String, dynamic> && response.containsKey('items')) {
        invoices = response['items'] as List<dynamic>;
      } else {
        return;
      }

      historiqueTrades.removeWhere((trade) => trade.strikeQuoteId != null && trade.strikeQuoteId!.startsWith('STRIKE_'));

      final tradesAchats = invoices.where((invoice) {
        final description = invoice['description']?.toString() ?? '';
        final isAchatReel = description.contains('STRATÉGIE ACHAT BTC:') &&
            description.contains('EUR:') &&
            description.contains('Drawdown%:');
        final isEUR = invoice['amount'] is Map &&
            (invoice['amount'] as Map)['currency'] == 'EUR';
        return isAchatReel && isEUR;
      }).toList();

      final tradesVentes = invoices.where((invoice) {
        final description = invoice['description']?.toString() ?? '';
        final isVente = description.contains('STRATÉGIE VENTE BTC:') &&
            description.contains('EUR:') &&
            description.contains('Drawdown%:');
        final isBTC = invoice['amount'] is Map &&
            (invoice['amount'] as Map)['currency'] == 'BTC';
        return isVente && isBTC;
      }).toList();

      for (var facture in tradesAchats) {
        try {
          final id = facture['invoiceId']?.toString() ?? 'INCONNU';
          final description = facture['description']?.toString() ?? '';

          final existeDeja = historiqueTrades.any((trade) => trade.strikeQuoteId == id);
          if (existeDeja) {
            continue;
          }

          double quantiteBTC = 0.0;
          double montantEUR = 0.0;
          double prixAchatReel = 0.0;
          double drawdownAuMomentAchat = 0.0;

          final btcRegex = RegExp(r'BTC:(\d+\.\d+)');
          final btcMatch = btcRegex.firstMatch(description);
          if (btcMatch != null) {
            quantiteBTC = double.parse(btcMatch.group(1)!);
          }

          final eurRegex = RegExp(r'EUR:(\d+\.\d+)');
          final eurMatch = eurRegex.firstMatch(description);
          if (eurMatch != null) {
            prixAchatReel = double.parse(eurMatch.group(1)!);
          }

          final drawdownRegex = RegExp(r'Drawdown%:([-\d.]+)');
          final drawdownMatch = drawdownRegex.firstMatch(description);
          if (drawdownMatch != null) {
            drawdownAuMomentAchat = double.parse(drawdownMatch.group(1)!);
          }

          if (facture['amount'] is Map) {
            final amountData = facture['amount'] as Map;
            montantEUR = _parseMontantSecurise(amountData['amount'], decimales: 2);
          }

          if (prixAchatReel == 0 && quantiteBTC > 0 && montantEUR > 0) {
            prixAchatReel = montantEUR / quantiteBTC;
          }

          if (montantEUR > 0 && prixAchatReel > 0) {
            if (prixAchatReel < 1000 || prixAchatReel > 200000) {
              continue;
            }

            // Création d'un palier dynamique pour le trade historique
            final palierReel = _genererPalierDynamique(drawdownAuMomentAchat, prixAchatReel);

            final marketData = await _getMarketDataEtendu();
            final takeProfit = _calculerPrixTakeProfit(prixAchatReel, palierReel);

            final trade = Trade(
              id: 'STRIKE_ACHAT_$id',
              prixAchat: prixAchatReel,
              quantite: quantiteBTC,
              takeProfit: takeProfit,
              palier: palierReel,
              dateAchat: DateTime.tryParse(facture['created']?.toString() ?? '') ?? DateTime.now(),
              montantInvesti: montantEUR,
              strikeQuoteId: id,
              typeTrade: TypeTrade.ACHAT,
            );

            historiqueTrades.add(trade);
          }
        } catch (e) {
          print('❌ Erreur parsing facture ACHAT Strike: $e');
        }
      }

      for (var facture in tradesVentes) {
        try {
          final id = facture['invoiceId']?.toString() ?? 'INCONNU';
          final description = facture['description']?.toString() ?? '';

          final existeDeja = historiqueTrades.any((trade) => trade.strikeQuoteId == id);
          if (existeDeja) {
            continue;
          }

          double quantiteBTC = 0.0;
          double prixVenteReel = 0.0;
          double drawdownAuMomentVente = 0.0;

          final btcRegex = RegExp(r'STRATÉGIE VENTE BTC:(\d+\.\d+)');
          final btcMatch = btcRegex.firstMatch(description);
          if (btcMatch != null) {
            quantiteBTC = double.parse(btcMatch.group(1)!);
          }

          final eurRegex = RegExp(r'EUR:(\d+\.\d+)');
          final eurMatch = eurRegex.firstMatch(description);
          if (eurMatch != null) {
            prixVenteReel = double.parse(eurMatch.group(1)!);
          }

          final drawdownRegex = RegExp(r'Drawdown%:([-\d.]+)');
          final drawdownMatch = drawdownRegex.firstMatch(description);
          if (drawdownMatch != null) {
            drawdownAuMomentVente = double.parse(drawdownMatch.group(1)!);
          }

          if (quantiteBTC == 0 && facture['amount'] is Map) {
            final amountData = facture['amount'] as Map;
            if (amountData['currency'] == 'BTC') {
              quantiteBTC = _parseMontantSecurise(amountData['amount'], decimales: 8);
            }
          }

          if (quantiteBTC > 0) {
            final trade = Trade(
              id: 'STRIKE_VENTE_$id',
              prixAchat: 0.0,
              quantite: quantiteBTC,
              takeProfit: 0.0,
              palier: _genererPalierDynamique(drawdownAuMomentVente, prixVenteReel),
              dateAchat: DateTime.tryParse(facture['created']?.toString() ?? '') ?? DateTime.now(),
              montantInvesti: 0.0,
              strikeQuoteId: id,
              typeTrade: TypeTrade.VENTE,
              estVente: true,
            );

            historiqueTrades.add(trade);
          }
        } catch (e) {
          print('❌ Erreur parsing facture VENTE Strike: $e');
        }
      }
      final btcData = await BTCDataService.getBitcoinData();
      mettreAJourProfits(btcData.price);

    } catch (e) {
      print('❌ Erreur chargement historique Strike: $e');
    }
  }

  void nettoyerTradesAberrants() {
    final initialCount = historiqueTrades.length;
    final seenIds = <String>{};
    historiqueTrades.removeWhere((trade) {
      if (trade.strikeQuoteId != null) {
        if (seenIds.contains(trade.strikeQuoteId)) {
          return true;
        }
        seenIds.add(trade.strikeQuoteId!);
      }

      if (!trade.estVente) {
        final prixAchat = trade.prixAchat;
        final isAberrant = prixAchat < 1000 || prixAchat > 200000;
        if (isAberrant) {
          return true;
        }
      }
      return false;
    });
  }

  Future<Trade> executerAchat(DecisionAchat decision) async => executerAchatStrike(decision);

  Future<void> executerVente(DecisionVente decision) async => executerVenteStrike(decision);

  Future<StatistiquesStrategie> getStatistiques() async {
    final tradesVendus = historiqueTrades.where((t) => t.vendu).toList();
    final tradesOuverts = historiqueTrades.where((t) => !t.vendu).toList();

    final balanceReelle = await _getBalanceStrike();
    final btcData = await BTCDataService.getBitcoinData();

    double totalInvesti = 0;
    double totalVendu = 0;
    double pnlTotal = 0;
    int tradesGagnants = 0;
    int tradesPerdants = 0;

    for (var trade in tradesVendus) {
      totalInvesti += trade.montantInvesti;
      totalVendu += trade.montantVente ?? 0;
      final pnl = (trade.montantVente ?? 0) - trade.montantInvesti;
      pnlTotal += pnl;

      if (pnl > 0) {
        tradesGagnants++;
      } else {
        tradesPerdants++;
      }
    }

    double valeurPositionsOuvertes = 0;
    for (var trade in tradesOuverts) {
      valeurPositionsOuvertes += trade.quantite * btcData.price;
    }

    final valeurBTCReelle = balanceReelle.soldeBTC * btcData.price;
    final valeurTotaleReelle = balanceReelle.soldeEUR + valeurBTCReelle;

    final totalTrades = tradesVendus.length;
    final tauxReussite = totalTrades > 0 ? (tradesGagnants / totalTrades) * 100 : 0;

    return StatistiquesStrategie(
      totalTrades: totalTrades,
      tradesGagnants: tradesGagnants,
      tradesPerdants: tradesPerdants,
      tauxReussite: tauxReussite.toDouble(),
      pnlTotal: pnlTotal,
      pnlTotalPercent: totalInvesti > 0 ? (pnlTotal / totalInvesti) * 100 : 0,
      capitalActuel: valeurTotaleReelle,
      positionsOuvertes: tradesOuverts.length,
      valeurPositionsOuvertes: valeurPositionsOuvertes,
      soldeEURReel: balanceReelle.soldeEUR,
      soldeBTCReel: balanceReelle.soldeBTC,
      dernierTrade: historiqueTrades.isNotEmpty ? historiqueTrades.last : null,
    );
  }

  void resetStrategie() {
    historiqueTrades.clear();
    dernierAchat = null;
    dernierPalierAchete = null;
    _enCoursExecution = false;
  }

  bool get enCooldown {
    if (dernierAchat == null || dernierPalierAchete != null) return false;
    final maintenant = DateTime.now();
    final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final dernierAchatDate = DateTime(dernierAchat!.year, dernierAchat!.month, dernierAchat!.day);
    return dernierAchatDate == aujourdhui;
  }

  Duration get tempsRestantCooldown {
    if (!enCooldown) return Duration.zero;
    final maintenant = DateTime.now();
    final minuit = DateTime(maintenant.year, maintenant.month, maintenant.day).add(Duration(days: 1));
    return minuit.difference(maintenant);
  }

  List<Trade> get tradesActifs => historiqueTrades.where((t) => !t.vendu).toList();
  bool get enCoursExecution => _enCoursExecution;

  // MÉTHODES POUR L'ÉVALUATION DES VENTES
  Future<List<DecisionVente>> _evaluerConditionsVenteAmeliorees(
      double prixActuel,
      Map<String, dynamic> marketData,
      ) async {
    final decisions = <DecisionVente>[];
    final tradesOuverts = historiqueTrades.where((t) => !t.vendu && t.typeTrade == TypeTrade.ACHAT && !t.estVente).toList();
    final balanceActuelle = await _getBalanceStrike();

    for (var trade in tradesOuverts) {
      if (trade.quantite > balanceActuelle.soldeBTC) {
        print('⚠️ Trade ${trade.id} ne correspond pas au solde BTC réel');
        continue;
      }

      final decision = _evaluerVenteTradeAmelioree(trade, prixActuel, marketData);
      if (decision.vendre) {
        decisions.add(decision);
      }
    }

    return decisions;
  }

  DecisionVente _evaluerVenteTradeAmelioree(Trade trade, double prixActuel, Map<String, dynamic> marketData) {
    final prixAchatReel = trade.prixAchat;
    final profitActuel = ((prixActuel - prixAchatReel) / prixAchatReel) * 100;
    final volatilite = marketData['volatilite'] ?? 0.0;
    final rsi = marketData['rsi'] ?? 50.0;

    // VÉRIFICATION TAKE-PROFIT UNIQUEMENT
    if (prixActuel >= trade.takeProfit) {
      if (rsi > 60.0) {
        return DecisionVente(
          vendre: true,
          trade: trade,
          raison: 'Take-profit atteint (${trade.takeProfit.toStringAsFixed(2)}) avec confirmation surachat - Profit: ${profitActuel.toStringAsFixed(2)}%',
          typeVente: TypeVente.TAKE_PROFIT,
          prixVente: trade.takeProfit,
          metrics: {
            'volatilite': (volatilite * 100).toStringAsFixed(1) + '%',
            'rsi': rsi.toStringAsFixed(1),
            'profit_realise': profitActuel.toStringAsFixed(2) + '%',
          },
        );
      }
    }

    // VÉRIFICATION CONDITIONS DE MARCHÉ EXTRÊMES
    if (volatilite > 0.20 && profitActuel > 10.0) {
      return DecisionVente(
        vendre: true,
        trade: trade,
        raison: 'Prise de bénéfice anticipée due à la haute volatilité - Profit: ${profitActuel.toStringAsFixed(2)}%',
        typeVente: TypeVente.VOLATILITE_ELEVEE,
        prixVente: prixActuel,
        metrics: {
          'volatilite': (volatilite * 100).toStringAsFixed(1) + '%',
          'rsi': rsi.toStringAsFixed(1),
          'profit_realise': profitActuel.toStringAsFixed(2) + '%',
        },
      );
    }

    return DecisionVente(
      vendre: false,
      trade: trade,
      raison: 'Trade actif - Profit: ${profitActuel.toStringAsFixed(2)}% - Target: ${trade.takeProfit.toStringAsFixed(2)}',
      typeVente: TypeVente.AUCUNE,
      prixVente: 0.0,
      metrics: {
        'volatilite': (volatilite * 100).toStringAsFixed(1) + '%',
        'rsi': rsi.toStringAsFixed(1),
      },
    );
  }
}

class StrategieService {
  static TradingStrategie? _instance;

  static Future<void> rechargerDonneesCompletes() async {
    await instance.rechargerDonneesCompletes();
  }

  static TradingStrategie get instance {
    if (_instance == null) {
      throw Exception('StrategieService non initialisé. Appeler init() d\'abord.');
    }
    return _instance!;
  }

  static void init() {
    _instance ??= TradingStrategie();
  }

  static Future<StrategieEvaluation> evaluerMarche() async {
    return await instance.evaluerMarche();
  }

  static void resetExecutionLock() {
    instance.resetExecutionLock();
  }

  static Future<Trade> executerAchat(DecisionAchat decision) async {
    return await instance.executerAchatStrike(decision);
  }

  static Future<void> executerVente(DecisionVente decision) async {
    return await instance.executerVenteStrike(decision);
  }

  static Future<StatistiquesStrategie> getStatistiques() async {
    return await instance.getStatistiques();
  }

  static void reset() {
    instance.resetStrategie();
  }

  static bool get enCoursExecution => instance.enCoursExecution;
  static bool get enCooldown => instance.enCooldown;
  static Duration get tempsRestantCooldown => instance.tempsRestantCooldown;
}