import 'package:flutter/material.dart';
import '../components/model.dart';

class BitcoinDataPage extends StatefulWidget {
  final BTCDataResult? btcData;
  final String btcDataStatus;
  final bool isTestingBTCData;
  final Map<String, dynamic>? sourceStats;
  final Function() onRefreshData;
  final Function() onEvaluateStrategy;

  const BitcoinDataPage({
    super.key,
    required this.btcData,
    required this.btcDataStatus,
    required this.isTestingBTCData,
    required this.sourceStats,
    required this.onRefreshData,
    required this.onEvaluateStrategy,
  });

  @override
  _BitcoinDataPageState createState() => _BitcoinDataPageState();
}

class _BitcoinDataPageState extends State<BitcoinDataPage> {
  String _formatVolume(double? volume) {
    if (volume == null) return 'N/A';
    if (volume >= 1e9) {
      return '${(volume / 1e9).toStringAsFixed(2)}B€';
    } else if (volume >= 1e6) {
      return '${(volume / 1e6).toStringAsFixed(2)}M€';
    } else if (volume >= 1e3) {
      return '${(volume / 1e3).toStringAsFixed(2)}K€';
    }
    return '${volume.toStringAsFixed(2)}€';
  }

  String _formatChangePercent(double? percent) {
    if (percent == null) return 'N/A';
    return '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(2)}%';
  }

  Color _getChangeColor(double? percent) {
    if (percent == null) return Colors.grey;
    return percent >= 0 ? Colors.green : Colors.red;
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 2,
      child: Container(
        constraints: BoxConstraints(
          minHeight: 80,
        ),
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final btcData = widget.btcData;
    final hasValidData = btcData != null && btcData.price > 0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // Carte principale des données Bitcoin
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.currency_bitcoin, color: Colors.orange, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Données Bitcoin Multi-Sources',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),

                  // Indicateur de chargement
                  if (widget.isTestingBTCData) ...[
                    Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            widget.btcDataStatus,
                            style: TextStyle(color: Colors.blue),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Statut de connexion
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: widget.btcDataStatus.contains('Erreur')
                            ? Colors.red[50]
                            : Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: widget.btcDataStatus.contains('Erreur')
                              ? Colors.red
                              : Colors.green,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            widget.btcDataStatus.contains('Erreur')
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            color: widget.btcDataStatus.contains('Erreur')
                                ? Colors.red
                                : Colors.green,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.btcDataStatus,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: widget.btcDataStatus.contains('Erreur')
                                    ? Colors.red
                                    : Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),

                    if (hasValidData) ...[
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.8,
                        children: [
                          // Ligne 1: Prix et Variation
                          _buildStatCard(
                            '💰 Prix actuel',
                            '${btcData.price.toStringAsFixed(2)}€',
                            Colors.blue,
                            Icons.show_chart,
                          ),
                          _buildStatCard(
                            '📈 Variation 24h',
                            _formatChangePercent(btcData.priceChangePercent24h),
                            _getChangeColor(btcData.priceChangePercent24h),
                            Icons.trending_up,
                          ),

                          // Ligne 2: Volume et Market Cap
                          _buildStatCard(
                            '📊 Volume 24h',
                            _formatVolume(btcData.volume),
                            Colors.purple,
                            Icons.bar_chart,
                          ),
                          _buildStatCard(
                            '🏦 Market Cap',
                            btcData.marketCap != null
                                ? _formatVolume(btcData.marketCap)
                                : 'N/A',
                            Colors.blue,
                            Icons.business_center,
                          ),

                          // Ligne 3: HIGH/LOW 24h CÔTE À CÔTE
                          _buildStatCard(
                            '⬆️ High 24h',
                            btcData.high24h != null
                                ? '${btcData.high24h!.toStringAsFixed(2)}€'
                                : 'N/A',
                            Colors.green,
                            Icons.arrow_upward,
                          ),
                          _buildStatCard(
                            '⬇️ Low 24h',
                            btcData.low24h != null
                                ? '${btcData.low24h!.toStringAsFixed(2)}€'
                                : 'N/A',
                            Colors.red,
                            Icons.arrow_downward,
                          ),

                          // Ligne 4: HIGH/LOW 6 MOIS CÔTE À CÔTE
                          _buildStatCard(
                            '🏔️ High 6 mois',
                            btcData.sixMonthsHigh != null
                                ? '${btcData.sixMonthsHigh!.toStringAsFixed(2)}€'
                                : 'N/A',
                            Colors.green,
                            Icons.flag,
                          ),
                          _buildStatCard(
                            '🏷️ Low 6 mois',
                            btcData.sixMonthsLow != null
                                ? '${btcData.sixMonthsLow!.toStringAsFixed(2)}€'
                                : 'N/A',
                            Colors.red,
                            Icons.flag,
                          ),

                          // Ligne 5: Métadonnées techniques
                          _buildStatCard(
                            '📡 Sources actives',
                            '${btcData.sourcesUsed}/${btcData.totalSources}',
                            Colors.orange,
                            Icons.source,
                          ),
                          _buildStatCard(
                            '🔄 Statut cache',
                            btcData.cacheUsed == true ? 'Utilisé' : 'Direct',
                            btcData.cacheUsed == true ? Colors.orange : Colors.green,
                            Icons.cached,
                          ),
                        ],
                      ),
                      SizedBox(height: 16),

                      // Boutons d'action
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: widget.onRefreshData,
                              icon: Icon(Icons.refresh),
                              label: Text('Rafraîchir les données'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          IconButton(
                            onPressed: widget.onEvaluateStrategy,
                            icon: Icon(Icons.analytics, size: 28),
                            tooltip: 'Évaluer la stratégie',
                            color: Colors.purple,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.purple.withOpacity(0.1),
                              padding: EdgeInsets.all(12),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // État sans données
                      Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.currency_bitcoin,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Aucune donnée Bitcoin disponible',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Cliquez sur le bouton ci-dessous pour commencer la collecte',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                            SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: widget.onRefreshData,
                                icon: Icon(Icons.play_arrow),
                                label: Text('Démarrer la collecte Bitcoin'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),

          // Section statistiques des sources
          if (widget.sourceStats != null && widget.sourceStats!.isNotEmpty) ...[
            SizedBox(height: 16),
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.analytics, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          '📊 Statistiques des Sources',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    ...widget.sourceStats!.entries.map((entry) {
                      final stats = entry.value;
                      final success = stats['success'] is int ? stats['success'] : 0;
                      final total = stats['total'] is int ? stats['total'] : 1;
                      final successRate = total > 0 ? (success / total * 100) : 0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '• ${entry.key}',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                            Text(
                              '$success/$total',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: successRate > 50 ? Colors.green :
                                successRate > 25 ? Colors.orange : Colors.red,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '(${successRate.toStringAsFixed(0)}%)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
          ] else if (!widget.isTestingBTCData) ...[
            // Message si pas de statistiques disponibles
            SizedBox(height: 16),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Les statistiques des sources seront disponibles après la première collecte',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}