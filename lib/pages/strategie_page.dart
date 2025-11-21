import 'package:flutter/material.dart';
import '../components/model.dart';
import '../services/strategie/strategie.dart';
import '../types/types.dart';

class StrategiePage extends StatefulWidget {
  final StrategieEvaluation? strategieEvaluation;
  final bool isEvaluatingStrategy;
  final Function() onEvaluateStrategy;
  final Function() onExecuteAchat;
  final Function(DecisionVente) onExecuteVente;

  const StrategiePage({
    Key? key,
    required this.strategieEvaluation,
    required this.isEvaluatingStrategy,
    required this.onEvaluateStrategy,
    required this.onExecuteAchat,
    required this.onExecuteVente,
  }) : super(key: key);

  @override
  _StrategiePageState createState() => _StrategiePageState();
}

class _StrategiePageState extends State<StrategiePage> {
  int _selectedView = 0;

  Widget _buildDataRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 1,
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewSelector() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedView = 0;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedView == 0
                      ? Colors.green
                      : Colors.grey[200],
                  foregroundColor: _selectedView == 0
                      ? Colors.white
                      : Colors.grey[700],
                  elevation: _selectedView == 0 ? 2 : 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_cart, size: 16),
                    SizedBox(width: 6),
                    Text('Achats'),
                  ],
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedView = 1;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedView == 1
                      ? Colors.blue
                      : Colors.grey[200],
                  foregroundColor: _selectedView == 1
                      ? Colors.white
                      : Colors.grey[700],
                  elevation: _selectedView == 1 ? 2 : 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.trending_down, size: 16),
                    SizedBox(width: 6),
                    Text('Ventes'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ⭐ NOUVELLE MÉTHODE : Extraire le drawdown de la description
  double? _extraireDrawdownDeDescription(String description) {
    try {
      final drawdownRegex = RegExp(r'Drawdown%:([-\d.]+)');
      final match = drawdownRegex.firstMatch(description);
      if (match != null) {
        return double.tryParse(match.group(1)!);
      }
    } catch (e) {
      print('❌ Erreur extraction drawdown: $e');
    }
    return null;
  }

  Widget _buildTransactionsList() {
    final seenIds = <String>{};

    // Récupérer les trades selon la vue sélectionnée
    List<Trade> tradesFiltres =
        StrategieService.instance.historiqueTrades.where((trade) {
          if (trade.strikeQuoteId == null) return false;
          if (seenIds.contains(trade.strikeQuoteId)) return false;
          seenIds.add(trade.strikeQuoteId!);

          if (_selectedView == 0) {
            return trade.typeTrade == TypeTrade.ACHAT && !trade.estVente;
          } else {
            return trade.estVente;
          }
        }).toList()..sort((a, b) => b.dateAchat.compareTo(a.dateAchat));

    if (tradesFiltres.isEmpty) {
      return Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              _selectedView == 0
                  ? Icons.shopping_cart_outlined
                  : Icons.trending_down_outlined,
              color: Colors.grey,
              size: 48,
            ),
            SizedBox(height: 12),
            Text(
              _selectedView == 0
                  ? 'Aucun achat effectué'
                  : 'Aucune vente effectuée',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              _selectedView == 0
                  ? 'Les achats apparaîtront ici après exécution'
                  : 'Les ventes apparaîtront ici après exécution',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // En-tête
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _selectedView == 0 ? Colors.green[50] : Colors.blue[50],
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _selectedView == 0 ? Icons.shopping_cart : Icons.trending_down,
                color: _selectedView == 0 ? Colors.green : Colors.blue,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                _selectedView == 0
                    ? 'Historique des Achats'
                    : 'Historique des Ventes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _selectedView == 0 ? Colors.green : Colors.blue,
                ),
              ),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _selectedView == 0 ? Colors.green : Colors.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${tradesFiltres.length}',
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

        // Liste des transactions
        ListView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: tradesFiltres.length,
          itemBuilder: (context, index) {
            final trade = tradesFiltres[index];
            return _buildTransactionItem(trade);
          },
        ),
      ],
    );
  }

  Widget _buildTransactionItem(Trade trade) {
    final isAchat = trade.typeTrade == TypeTrade.ACHAT;
    final isVente = trade.estVente;
    final prixActuel = widget.strategieEvaluation?.prixActuel ?? 0.0;

    // ⭐ NOUVEAU : Récupérer le drawdown depuis la description Strike
    double? drawdownAuMomentOperation;
    if (trade.strikeQuoteId != null) {
      // Chercher dans l'historique Strike pour récupérer la description complète
      final strikeTrade = StrategieService.instance.historiqueTrades.firstWhere(
        (t) => t.strikeQuoteId == trade.strikeQuoteId,
        orElse: () => trade,
      );

      // Si c'est une vente, on doit récupérer la description depuis les factures Strike
      // Pour l'instant, on va afficher le drawdown actuel comme placeholder
      if (widget.strategieEvaluation != null) {
        drawdownAuMomentOperation = widget.strategieEvaluation!.drawdownActuel;
      }
    }

    double profitPercent = 0.0;
    double profitMonetaire = 0.0;

    if (!isVente) {
      profitPercent = trade.calculerProfitAvecPrixActuel(prixActuel);
      profitMonetaire = trade.calculerProfitMonetaire(prixActuel);
    }

    return Container(
      decoration: BoxDecoration(
        color: isVente ? Colors.blue[50] : Colors.green[50],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date et statut
            Row(
              children: [
                Text(
                  '${trade.dateAchat.day}/${trade.dateAchat.month}/${trade.dateAchat.year}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Spacer(),
                // ⭐ NOUVEAU : Afficher le drawdown s'il est disponible
                if (drawdownAuMomentOperation != null)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: drawdownAuMomentOperation <= -20
                          ? Colors.orange
                          : Colors.grey,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'DD: ${drawdownAuMomentOperation.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                SizedBox(width: 8),
                if (trade.vendu)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, color: Colors.white, size: 10),
                        SizedBox(width: 4),
                        Text(
                          'TERMINÉ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            SizedBox(height: 8),

            // Détails selon le type
            if (isAchat && !isVente) ...[
              _buildTransactionRow('Palier', trade.palier.nom),
              _buildTransactionRow(
                'Quantité BTC',
                '${trade.quantite.toStringAsFixed(6)}',
              ),
              _buildTransactionRow(
                'Prix d\'achat',
                '${trade.prixAchat.toStringAsFixed(2)} €',
              ),
              _buildTransactionRow(
                'Montant investi',
                '${trade.montantInvesti.toStringAsFixed(2)} €',
              ),

              if (!trade.vendu) ...[
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: profitPercent >= 0
                        ? Colors.green[100]
                        : Colors.red[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Profit actuel',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${profitPercent.toStringAsFixed(2)}%',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: profitPercent >= 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Gain/Perte',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${profitMonetaire >= 0 ? '+' : ''}${profitMonetaire.toStringAsFixed(2)} €',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: profitMonetaire >= 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ] else if (isVente) ...[
              _buildTransactionRow(
                'Quantité BTC',
                '${trade.quantite.toStringAsFixed(6)}',
              ),
              if (trade.prixVente != null && trade.prixVente! > 0)
                _buildTransactionRow(
                  'Prix de vente',
                  '${trade.prixVente!.toStringAsFixed(2)} €',
                ),
              if (trade.montantVente != null && trade.montantVente! > 0)
                _buildTransactionRow(
                  'Montant reçu',
                  '${trade.montantVente!.toStringAsFixed(2)} €',
                ),
              if (trade.typeVente != null)
                _buildTransactionRow(
                  'Type de vente',
                  _getTypeVenteText(trade.typeVente!),
                ),
            ],

            // Stop Loss / Take Profit pour les achats ouverts
            if (isAchat && !trade.vendu && !isVente) ...[
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_upward,
                            color: Colors.green,
                            size: 12,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'TP: ${trade.takeProfit.toStringAsFixed(0)}€',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getTypeVenteText(TypeVente typeVente) {
    switch (typeVente) {
      case TypeVente.TAKE_PROFIT:
        return 'Take Profit 🎯';
      case TypeVente.STOP_LOSS:
        return 'Stop Loss 🛑';
      case TypeVente.TRAILING_STOP:
        return 'Trailing Stop 📈';
      default:
        return 'Vente';
    }
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_graph, color: Colors.purple),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Stratégie de Trading Drawdown',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),

                  if (widget.isEvaluatingStrategy) ...[
                    Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Évaluation de la stratégie...'),
                        ],
                      ),
                    ),
                  ] else if (widget.strategieEvaluation != null) ...[
                    // Drawdown actuel
                    _buildDataRow(
                      '📉 Drawdown actuel',
                      '${widget.strategieEvaluation!.drawdownActuel.toStringAsFixed(2)}%',
                      color: _getDrawdownColor(
                        widget.strategieEvaluation!.drawdownActuel,
                      ),
                    ),

                    // Palier actuel
                    _buildDataRow(
                      '🎯 Palier stratégique',
                      widget.strategieEvaluation!.palierActuel?.nom ??
                          'Hors palier',
                      color: widget.strategieEvaluation!.palierActuel != null
                          ? Colors.blue
                          : Colors.grey,
                    ),

                    // Décision d'achat
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: widget.strategieEvaluation!.decisionAchat.acheter
                            ? Colors.green[50]
                            : Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              widget.strategieEvaluation!.decisionAchat.acheter
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            widget.strategieEvaluation!.decisionAchat.acheter
                                ? Icons.shopping_cart_checkout
                                : Icons.pause_circle,
                            color:
                                widget
                                    .strategieEvaluation!
                                    .decisionAchat
                                    .acheter
                                ? Colors.green
                                : Colors.orange,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget
                                          .strategieEvaluation!
                                          .decisionAchat
                                          .acheter
                                      ? '✅ ACHAT RECOMMANDÉ'
                                      : '⏸️ ATTENDRE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        widget
                                            .strategieEvaluation!
                                            .decisionAchat
                                            .acheter
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ),
                                Text(
                                  widget
                                      .strategieEvaluation!
                                      .decisionAchat
                                      .raison,
                                  style: TextStyle(fontSize: 12),
                                ),
                                if (widget
                                        .strategieEvaluation!
                                        .decisionAchat
                                        .montantInvestissement !=
                                    null)
                                  Text(
                                    'Montant: ${widget.strategieEvaluation!.decisionAchat.montantInvestissement!.toStringAsFixed(2)} EUR',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (widget.strategieEvaluation!.decisionAchat.acheter)
                            ElevatedButton(
                              onPressed: widget.onExecuteAchat,
                              child: Text('EXÉCUTER'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    SizedBox(height: 12),

                    // Décisions de vente
                    if (widget
                        .strategieEvaluation!
                        .decisionsVente
                        .isNotEmpty) ...[
                      Text(
                        'Décisions de Vente (${widget.strategieEvaluation!.decisionsVente.length})',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      ...widget.strategieEvaluation!.decisionsVente
                          .map(
                            (decision) => Container(
                              width: double.infinity,
                              margin: EdgeInsets.only(bottom: 8),
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    decision.typeVente == TypeVente.TAKE_PROFIT
                                    ? Colors.green[50]
                                    : Colors.red[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    decision.typeVente == TypeVente.TAKE_PROFIT
                                        ? Icons.trending_up
                                        : Icons.trending_down,
                                    color:
                                        decision.typeVente ==
                                            TypeVente.TAKE_PROFIT
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          decision.typeVente ==
                                                  TypeVente.TAKE_PROFIT
                                              ? '🎯 TAKE PROFIT'
                                              : '🛑 STOP LOSS',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          decision.raison,
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        widget.onExecuteVente(decision),
                                    child: Text('VENDRE'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          decision.typeVente ==
                                              TypeVente.TAKE_PROFIT
                                          ? Colors.green
                                          : Colors.red,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: widget.strategieEvaluation!.tradesOuverts > 0
                              ? Colors.green[50]
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: widget.strategieEvaluation!.tradesOuverts > 0
                                ? Colors.green
                                : Colors.grey,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              widget.strategieEvaluation!.tradesOuverts > 0
                                  ? Icons.shopping_bag
                                  : Icons.shopping_bag_outlined,
                              color:
                                  widget.strategieEvaluation!.tradesOuverts > 0
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Trades ouverts: ${widget.strategieEvaluation!.tradesOuverts}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    widget.strategieEvaluation!.tradesOuverts >
                                        0
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                            if (widget.strategieEvaluation!.tradesOuverts >
                                0) ...[
                              SizedBox(width: 8),
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 16,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    SizedBox(height: 12),

                    // Capital disponible
                    _buildDataRow(
                      '💰 Capital disponible',
                      '${widget.strategieEvaluation!.capitalDisponible.toStringAsFixed(2)} EUR',
                    ),

                    // Balance Strike
                    if (widget.strategieEvaluation!.balanceStrike != null) ...[
                      _buildDataRow(
                        '🏦 Solde EUR Strike',
                        '${widget.strategieEvaluation!.balanceStrike!.soldeEUR.toStringAsFixed(2)} EUR',
                      ),
                      _buildDataRow(
                        '₿ Solde BTC Strike',
                        '${widget.strategieEvaluation!.balanceStrike!.soldeBTC.toStringAsFixed(6)} BTC',
                      ),
                    ],
                  ] else ...[
                    Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.analytics_outlined,
                            size: 48,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Aucune évaluation de stratégie',
                            style: TextStyle(color: Colors.grey),
                          ),
                          SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: widget.onEvaluateStrategy,
                            icon: Icon(Icons.play_arrow),
                            label: Text('Évaluer la stratégie'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          SizedBox(height: 16),

          if (widget.strategieEvaluation?.metrics != null) ...[
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📊 MÉTRIQUES DYNAMIQUES',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    _buildMetricRow(
                      'Score global',
                      '${widget.strategieEvaluation!.metrics!['scoreGlobal']}',
                    ),
                    _buildMetricRow(
                      'Niveau confiance',
                      '${widget.strategieEvaluation!.metrics!['confidenceLevel']}',
                    ),
                    _buildMetricRow(
                      'Score volatilité',
                      '${widget.strategieEvaluation!.metrics!['scoreVolatilite']}',
                    ),
                    _buildMetricRow(
                      'Score momentum',
                      '${widget.strategieEvaluation!.metrics!['scoreMomentum']}',
                    ),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: 12),

          SizedBox(height: 16),

          // Sélecteur de vue (Achats/Ventes)
          _buildViewSelector(),

          SizedBox(height: 16),

          // Liste des transactions (filtré selon la vue)
          _buildTransactionsList(),

          SizedBox(height: 16),
        ],
      ),
    );
  }

  // ⭐ NOUVELLE MÉTHODE : Obtenir la couleur du drawdown
  Color _getDrawdownColor(double drawdown) {
    if (drawdown >= -10) return Colors.green;
    if (drawdown >= -15) return Colors.orange;
    if (drawdown >= -20) return Colors.deepOrange;
    if (drawdown >= -25) return Colors.red;
    return Colors.red[900]!;
  }
}
