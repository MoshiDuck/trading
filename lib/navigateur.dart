import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trading/pages/balance_page.dart';
import 'package:trading/pages/bitcoin_data_page.dart';
import 'package:trading/pages/profit_chart_page.dart';
import 'package:trading/pages/strategie_page.dart';
import 'package:trading/services/strategie.dart';
import '../services/btc_data.dart';
import 'components/model.dart';

class Navigateur extends StatefulWidget {
  const Navigateur({Key? key}) : super(key: key);

  @override
  _NavigateurState createState() => _NavigateurState();
}

class _NavigateurState extends State<Navigateur> {
  int _currentIndex = 0;
  final List<Widget> _pages = [];

  // États partagés
  BTCDataResult? _btcData;
  String _btcDataStatus = 'Initialisation...';
  bool _isTestingBTCData = false;
  bool _isEvaluatingStrategy = false;
  StrategieEvaluation? _strategieEvaluation;
  Map<String, dynamic>? _sourceStats;
  Timer? _autoRefreshTimer;
  DateTime _lastEvaluation = DateTime.now();

  // CORRECTION CRITIQUE : Utiliser une instance unique de BTCDataCollector
  final BTCDataCollector _btcDataCollector = BTCDataCollector();

  @override
  void initState() {
    super.initState();
    _initialDataLoad();
    _refreshAllData();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    StrategieService.dispose();
    super.dispose();
  }

  Future<void> _refreshAllData() async {
    try {
      StrategieService.resetExecutionLock();
      await _testBTCDataCollector();
      await StrategieService.instance.rechargerHistorique();
      _lastEvaluation = DateTime.now().subtract(Duration(minutes: 10));
      await _evaluateTradingStrategy();
    } catch (e) {
      print('❌ Erreur lors du rafraîchissement: $e');
    }
  }

  Future<void> _testBTCDataCollector() async {
    if (_isTestingBTCData) return;

    setState(() {
      _isTestingBTCData = true;
      _btcDataStatus = 'Collecte en cours...';
    });

    try {
      final result = await _btcDataCollector.collectBitcoinData();
      final stats = await _btcDataCollector.getSourceStatsForUI();

      setState(() {
        _btcData = result;
        _sourceStats = stats;
        _btcDataStatus = '✅ Données mises à jour (${result.sourcesUsed} sources)';
        _isTestingBTCData = false;
      });

      _evaluateTradingStrategy();
    } catch (e) {
      setState(() {
        _btcDataStatus = '❌ Erreur: ${e.toString()}';
        _isTestingBTCData = false;
      });
    }
  }

  Future<void> _evaluateTradingStrategy() async {
    final now = DateTime.now();
    if (now.difference(_lastEvaluation) < Duration(seconds: 10)) {
      return;
    }

    if (StrategieService.enCoursExecution) {
      StrategieService.resetExecutionLock();
      await Future.delayed(Duration(seconds: 1));
    }

    setState(() {
      _isEvaluatingStrategy = true;
      _lastEvaluation = now;
    });

    try {
      await StrategieService.instance.rechargerHistorique();
      final evaluation = await StrategieService.evaluerMarche(
          forceEvaluation: StrategieService.forceAchatActive
      ).timeout(Duration(seconds: 45));

      if (mounted) {
        setState(() {
          _strategieEvaluation = evaluation;
          _isEvaluatingStrategy = false;
        });
      }
    } catch (e) {
      StrategieService.resetExecutionLock();
      if (mounted) {
        setState(() {
          _isEvaluatingStrategy = false;
        });
      }
    }
  }

  Future<void> _initialDataLoad() async {
    await _testBTCDataCollector();

    try {
      await BTCDataService.refreshHistoricalData();
      await Future.delayed(Duration(seconds: 2));
      await _evaluateTradingStrategy();
    } catch (e) {
      print('⚠️ Erreur lors du chargement initial des historiques: $e');
    }

    _autoRefreshTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      if (mounted) {
        _testBTCDataCollector();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (StrategieService.enCoursExecution)
            IconButton(
              icon: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              onPressed: _refreshAllData,
            ),
        ],
      ),
      body: _buildCurrentPage(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.blue,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.currency_bitcoin),
              label: 'Bitcoin Data',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_graph),
              label: 'Stratégie',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.trending_up),
              label: 'Profits',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet),
              label: 'Balances',
            ),
          ],
          backgroundColor: Colors.blue,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          selectedLabelStyle: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 11,
          ),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _refreshAllData,
        child: Icon(Icons.refresh),
        tooltip: 'Rafraîchir toutes les données',
      ),
    );
  }

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return BitcoinDataPage(
          btcData: _btcData,
          btcDataStatus: _btcDataStatus,
          isTestingBTCData: _isTestingBTCData,
          sourceStats: _sourceStats,
          onRefreshData: _testBTCDataCollector,
          onEvaluateStrategy: _evaluateTradingStrategy,
        );
      case 1:
        return StrategiePage(
          strategieEvaluation: _strategieEvaluation,
          isEvaluatingStrategy: _isEvaluatingStrategy,
          onEvaluateStrategy: _evaluateTradingStrategy,
        );
      case 2:
        return ProfitChartPage(onGlobalRefresh: _refreshAllData);
      case 3:
        return BalancePage();
      default:
        return BitcoinDataPage(
          btcData: _btcData,
          btcDataStatus: _btcDataStatus,
          isTestingBTCData: _isTestingBTCData,
          sourceStats: _sourceStats,
          onRefreshData: _testBTCDataCollector,
          onEvaluateStrategy: _evaluateTradingStrategy,
        );
    }
  }

  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Données Bitcoin';
      case 1:
        return 'Stratégie Automatique';
      case 2:
        return 'Graphique des Profits';
      case 3:
        return 'Mes Balances';
      default:
        return 'Trading Bitcoin Automatique';
    }
  }
}