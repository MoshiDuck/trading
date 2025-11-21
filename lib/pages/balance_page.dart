import 'package:flutter/material.dart';
import '../api/strike/strike.dart';

class BalancePage extends StatefulWidget {
  const BalancePage({Key? key}) : super(key: key);

  @override
  _BalancePageState createState() => _BalancePageState();
}

class _BalancePageState extends State<BalancePage> {
  late Future<Map<String, double>> _balancesFuture;
  final StrikeApi _strikeApi = StrikeApi();

  @override
  void initState() {
    super.initState();
    _balancesFuture = _strikeApi.getBtcAndEurAvailable();
  }

  Future<void> _refreshBalances() {
    setState(() {
      _balancesFuture = _strikeApi.getBtcAndEurAvailable();
    });
    return _balancesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '💰 Balances Strike',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Spacer(),
              IconButton(
                onPressed: _refreshBalances,
                icon: Icon(Icons.refresh),
                tooltip: 'Actualiser les balances',
              ),
            ],
          ),
          SizedBox(height: 16),

          FutureBuilder<Map<String, double>>(
            future: _balancesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Card(
                  child: ListTile(
                    leading: CircularProgressIndicator(),
                    title: Text('Chargement des balances...'),
                  ),
                );
              } else if (snapshot.hasError) {
                return Card(
                  color: Colors.red[50],
                  child: ListTile(
                    leading: Icon(Icons.error, color: Colors.red),
                    title: Text(
                      'Erreur lors de la récupération des balances',
                      style: TextStyle(color: Colors.red),
                    ),
                    subtitle: Text(
                      '${snapshot.error}',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                );
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Card(
                  child: ListTile(
                    leading: Icon(Icons.warning),
                    title: Text('Aucune donnée de balance disponible.'),
                  ),
                );
              } else {
                final btc = snapshot.data!['BTC']!;
                final eur = snapshot.data!['EUR']!;

                return Column(
                  children: [
                    Card(
                      elevation: 4,
                      child: ListTile(
                        leading: Icon(Icons.currency_bitcoin, color: Colors.orange),
                        title: Text('Bitcoin (BTC)'),
                        subtitle: Text('Solde disponible'),
                        trailing: Chip(
                          label: Text('$btc BTC'),
                          backgroundColor: Colors.orange[100],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Card(
                      elevation: 4,
                      child: ListTile(
                        leading: Icon(Icons.euro, color: Colors.green),
                        title: Text('Euros (EUR)'),
                        subtitle: Text('Solde disponible'),
                        trailing: Chip(
                          label: Text('$eur€'),
                          backgroundColor: Colors.green[100],
                        ),
                      ),
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey[700]),
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
}