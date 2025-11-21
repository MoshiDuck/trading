import 'dart:math' as math;

class TechnicalIndicators {
  // Calcul du True Range
  static double calculateTrueRange(
      double currentHigh, double currentLow, double previousClose) {
    final range1 = currentHigh - currentLow;
    final range2 = (currentHigh - previousClose).abs();
    final range3 = (currentLow - previousClose).abs();
    return [range1, range2, range3].reduce(math.max);
  }

  // Calcul de l'ATR (Average True Range) sur N périodes
  static double calculateATR(List<Map<String, double>> ohlcData, int period) {
    if (ohlcData.length < period + 1) {
      return 0.0;
    }

    final trValues = <double>[];

    for (int i = 1; i < ohlcData.length; i++) {
      final current = ohlcData[i];
      final previous = ohlcData[i - 1];

      final tr = calculateTrueRange(
        current['high'] ?? 0.0,
        current['low'] ?? 0.0,
        previous['close'] ?? 0.0,
      );
      trValues.add(tr);
    }

    // Premier ATR = moyenne simple des premiers TR
    double atr = trValues.take(period).reduce((a, b) => a + b) / period;

    // ATR suivant = (ATR précédent * (n-1) + TR courant) / n
    for (int i = period; i < trValues.length; i++) {
      atr = (atr * (period - 1) + trValues[i]) / period;
    }

    return atr;
  }

  // Calcul du RSI (Relative Strength Index) sur N périodes
  static double calculateRSI(List<double> closes, int period) {
    if (closes.length <= period) {
      return 50.0; // Valeur neutre si pas assez de données
    }

    final gains = <double>[];
    final losses = <double>[];

    for (int i = 1; i < closes.length; i++) {
      final difference = closes[i] - closes[i - 1];
      if (difference >= 0) {
        gains.add(difference);
        losses.add(0.0);
      } else {
        gains.add(0.0);
        losses.add(difference.abs());
      }
    }

    // Moyennes des gains et pertes
    double avgGain = gains.take(period).reduce((a, b) => a + b) / period;
    double avgLoss = losses.take(period).reduce((a, b) => a + b) / period;

    // Calcul des moyennes lissées
    for (int i = period; i < gains.length; i++) {
      avgGain = (avgGain * (period - 1) + gains[i]) / period;
      avgLoss = (avgLoss * (period - 1) + losses[i]) / period;
    }

    if (avgLoss == 0) return 100.0;

    final rs = avgGain / avgLoss;
    final rsi = 100 - (100 / (1 + rs));

    return rsi;
  }

  // Récupération des données OHLC pour les calculs
  static Future<List<Map<String, double>>> fetchOHLCData(int days) async {
    // Cette méthode sera implémentée en utilisant une API comme CryptoCompare
    // Pour l'instant, retournons des données mockées
    return [];
  }

  static Future<List<double>> fetchClosePrices(int days) async {
    // Implémentation similaire pour les prix de clôture
    return [];
  }
}

class ATRConfig {
  final int period;
  final double multiplier;
  final double minATRPercent;
  final double maxATRPercent;

  const ATRConfig({
    this.period = 14,
    this.multiplier = 2.0,
    this.minATRPercent = 0.5,
    this.maxATRPercent = 3.0,
  });
}

class RSIConfig {
  final int period;
  final double oversold;
  final double overbought;
  final double neutral;

  const RSIConfig({
    this.period = 14,
    this.oversold = 30.0,
    this.overbought = 70.0,
    this.neutral = 50.0,
  });
}