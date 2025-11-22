import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../components/model.dart';
import '../services/strategie.dart';
import '../services/btc_data.dart';
import '../types/types.dart';

class ProfitChartPage extends StatefulWidget {
  final Future<void> Function()? onGlobalRefresh;

  const ProfitChartPage({Key? key, this.onGlobalRefresh}) : super(key: key);

  @override
  _ProfitChartPageState createState() => _ProfitChartPageState();
}

class _ProfitChartPageState extends State<ProfitChartPage> {
  List<ProfitDataPoint> _profitData = [];
  bool _isLoading = true;
  double _prixActuel = 0.0;

  // Cache pour éviter les rafraîchissements trop fréquents
  DateTime? _lastRefresh;
  static const Duration _refreshCooldown = Duration(minutes: 2);
  List<ProfitDataPoint>? _cachedProfitData;
  double? _cachedPrixActuel;

  @override
  void initState() {
    super.initState();
    _loadProfitDataWithCache();
  }

  bool get _canRefresh {
    if (_lastRefresh == null) return true;
    return DateTime.now().difference(_lastRefresh!) > _refreshCooldown;
  }

  Future<void> _loadProfitDataWithCache({bool forceRefresh = false}) async {
    // Utiliser le cache si disponible et pas de force refresh
    if (!forceRefresh && _cachedProfitData != null && _cachedPrixActuel != null) {
      setState(() {
        _profitData = _cachedProfitData!;
        _prixActuel = _cachedPrixActuel!;
        _isLoading = false;
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // Récupérer le prix actuel
      final btcData = await BTCDataService.getBitcoinData();
      _prixActuel = btcData.price;

      // Calculer les données de profit
      await _calculateProfitData();

      // Mettre en cache
      _cachedProfitData = List.from(_profitData);
      _cachedPrixActuel = _prixActuel;
      _lastRefresh = DateTime.now();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Erreur chargement données profit: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRefresh() async {
    if (!_canRefresh && !_isLoading) {
      final nextRefresh = _lastRefresh!.add(_refreshCooldown);
      final remaining = nextRefresh.difference(DateTime.now());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Prochain rafraîchissement dans ${remaining.inMinutes}m ${remaining.inSeconds.remainder(60)}s'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Utiliser le refresh global si disponible, sinon refresh local
    if (widget.onGlobalRefresh != null) {
      await widget.onGlobalRefresh!();
      // Attendre un peu pour que les données globales se mettent à jour
      await Future.delayed(Duration(seconds: 2));
    }

    await _loadProfitDataWithCache(forceRefresh: true);
  }

  Future<void> _calculateProfitData() async {
    final historique = StrategieService.instance.historiqueTrades;
    final profitData = <ProfitDataPoint>[];

    // Trier les trades par date
    historique.sort((a, b) => a.dateAchat.compareTo(b.dateAchat));

    double profitCumule = 0.0;
    final Map<DateTime, double> profitsParJour = {};

    for (var trade in historique) {
      final date = DateTime(trade.dateAchat.year, trade.dateAchat.month, trade.dateAchat.day);

      if (trade.estVente) {
        // VENTE - Calculer le profit réel
        final tradeAchatCorrespondant = _findAchatTradeForVente(trade);
        if (tradeAchatCorrespondant != null) {
          final profit = (trade.montantVente ?? 0) - tradeAchatCorrespondant.montantInvesti;
          profitsParJour[date] = (profitsParJour[date] ?? 0) + profit;
        }
      } else if (!trade.vendu) {
        // POSITION OUVERTE - Calculer le profit non réalisé
        final profitNonRealise = (_prixActuel * trade.quantite) - trade.montantInvesti;
        profitsParJour[date] = (profitsParJour[date] ?? 0) + profitNonRealise;
      }
    }

    // Créer les points de données cumulés
    double cumul = 0.0;
    final sortedDates = profitsParJour.keys.toList()..sort();

    for (var date in sortedDates) {
      cumul += profitsParJour[date]!;
      profitData.add(ProfitDataPoint(
        date: date,
        profit: profitsParJour[date]!,
        profitCumule: cumul,
        type: profitsParJour[date]! >= 0 ? ProfitType.GAIN : ProfitType.PERTE,
      ));
    }

    setState(() {
      _profitData = profitData;
    });
  }

  Trade? _findAchatTradeForVente(Trade vente) {
    final historique = StrategieService.instance.historiqueTrades;

    // Chercher l'achat correspondant à cette vente
    for (var trade in historique) {
      if (!trade.estVente &&
          trade.strikeQuoteId != null &&
          trade.strikeQuoteId == vente.strikeQuoteId?.replaceAll('VENTE', 'ACHAT')) {
        return trade;
      }
    }

    // Fallback: chercher par quantité et date approximative
    for (var trade in historique) {
      if (!trade.estVente &&
          trade.quantite.toStringAsFixed(6) == vente.quantite.toStringAsFixed(6) &&
          trade.dateAchat.isBefore(vente.dateAchat)) {
        return trade;
      }
    }

    return null;
  }

  Widget _buildChart() {
    if (_profitData.isEmpty) {
      return Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.auto_graph_outlined, color: Colors.grey, size: 48),
            SizedBox(height: 12),
            Text(
              'Aucune donnée de profit disponible',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Les gains et pertes apparaîtront ici après vos transactions',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final maxProfit = _profitData.map((e) => e.profitCumule).reduce((a, b) => a > b ? a : b);
    final minProfit = _profitData.map((e) => e.profitCumule).reduce((a, b) => a < b ? a : b);

    // CORRECTION : Éviter les intervalles zéro
    final yRange = (maxProfit - minProfit).abs();
    final yInterval = yRange > 0 ? yRange / 4 : 100.0;
    final xInterval = _profitData.length > 1 ? (_profitData.length / 5).ceil() : 1;

    return Column(
      children: [
        // En-tête du graphique avec indicateur de cache
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.trending_up, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Évolution des Gains/Pertes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    if (_lastRefresh != null)
                      Text(
                        'Dernier rafraîchissement: ${_lastRefresh!.hour.toString().padLeft(2, '0')}:${_lastRefresh!.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.blue[700],
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_profitData.length} jours',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Graphique
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: _getBottomTitles(xInterval),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: _getLeftTitles(yInterval, minProfit, maxProfit),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: _profitData.asMap().entries.map((entry) {
                      return FlSpot(
                        entry.key.toDouble(),
                        entry.value.profitCumule,
                      );
                    }).toList(),
                    isCurved: true,
                    color: _getChartColor(),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          _getChartColor().withOpacity(0.3),
                          _getChartColor().withOpacity(0.1),
                        ],
                      ),
                    ),
                  ),
                ],
                minY: minProfit - (yRange * 0.1),
                maxY: maxProfit + (yRange * 0.1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  SideTitles _getBottomTitles(int interval) {
    return SideTitles(
      showTitles: true,
      interval: interval.toDouble(),
      getTitlesWidget: (value, meta) {
        if (value.toInt() >= 0 && value.toInt() < _profitData.length) {
          final date = _profitData[value.toInt()].date;
          return Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              '${date.day}/${date.month}',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          );
        }
        return Text('');
      },
    );
  }

  SideTitles _getLeftTitles(double interval, double minProfit, double maxProfit) {
    return SideTitles(
      showTitles: true,
      interval: interval,
      getTitlesWidget: (value, meta) {
        final step = (maxProfit - minProfit) / 4;
        final steps = [minProfit, minProfit + step, minProfit + 2*step, minProfit + 3*step, maxProfit];

        if (steps.any((stepValue) => (value - stepValue).abs() < interval * 0.1)) {
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Text(
              '${value.toStringAsFixed(0)}€',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          );
        }
        return Text('');
      },
    );
  }

  Color _getChartColor() {
    if (_profitData.isEmpty) return Colors.grey;
    final dernierProfit = _profitData.last.profitCumule;
    return dernierProfit >= 0 ? Colors.green : Colors.red;
  }

  Widget _buildStatsCards() {
    if (_profitData.isEmpty) return SizedBox();

    final dernierPoint = _profitData.last;
    final profitTotal = dernierPoint.profitCumule;
    final isProfit = profitTotal >= 0;

    final meilleurJour = _profitData.isNotEmpty
        ? _profitData.map((e) => e.profit).reduce((a, b) => a > b ? a : b)
        : 0.0;
    final pireJour = _profitData.isNotEmpty
        ? _profitData.map((e) => e.profit).reduce((a, b) => a < b ? a : b)
        : 0.0;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'RÉSUMÉ DES PERFORMANCES',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Profit Total',
                  '${profitTotal.toStringAsFixed(2)} €',
                  isProfit ? Colors.green : Colors.red,
                  Icons.account_balance_wallet,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Jours de Trading',
                  '${_profitData.length}',
                  Colors.blue,
                  Icons.calendar_today,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Meilleur Jour',
                  '${meilleurJour.toStringAsFixed(2)} €',
                  Colors.green,
                  Icons.arrow_upward,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Pire Jour',
                  '${pireJour.toStringAsFixed(2)} €',
                  Colors.red,
                  Icons.arrow_downward,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    final transactions = StrategieService.instance.historiqueTrades
      ..sort((a, b) => b.dateAchat.compareTo(a.dateAchat));

    if (transactions.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.list_alt, color: Colors.grey, size: 32),
            SizedBox(height: 8),
            Text(
              'Aucune transaction',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'DERNIÈRES TRANSACTIONS',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
        ),
        Container(
          height: 200,
          child: ListView.builder(
            itemCount: transactions.take(10).length,
            itemBuilder: (context, index) {
              final trade = transactions[index];
              return _buildTransactionItem(trade);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionItem(Trade trade) {
    final isAchat = !trade.estVente;
    final profit = isAchat && !trade.vendu
        ? (_prixActuel * trade.quantite) - trade.montantInvesti
        : trade.montantVente != null
        ? trade.montantVente! - trade.montantInvesti
        : 0.0;

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isAchat ? Colors.green[50] : Colors.blue[50],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isAchat ? Icons.shopping_cart : Icons.sell,
              color: isAchat ? Colors.green : Colors.blue,
              size: 16,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAchat ? 'ACHAT BTC' : 'VENTE BTC',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  '${trade.dateAchat.day}/${trade.dateAchat.month}/${trade.dateAchat.year}',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${trade.quantite.toStringAsFixed(6)} BTC',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(2)} €',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: profit >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Graphique des Gains/Pertes'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.refresh),
                onPressed: _handleRefresh,
                tooltip: 'Rafraîchir les données',
              ),
              if (!_canRefresh && _lastRefresh != null)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    constraints: BoxConstraints(
                      minWidth: 12,
                      minHeight: 12,
                    ),
                    child: Text(
                      '!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // Graphique
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: _buildChart(),
            ),

            SizedBox(height: 16),

            // Cartes de statistiques
            _buildStatsCards(),

            SizedBox(height: 16),

            // Liste des transactions
            _buildTransactionList(),

            SizedBox(height: 16),

            // Indicateur de cache
            if (!_canRefresh && _lastRefresh != null)
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Prochain rafraîchissement disponible dans ${_refreshCooldown.inMinutes - DateTime.now().difference(_lastRefresh!).inMinutes} minutes',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[800],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
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

