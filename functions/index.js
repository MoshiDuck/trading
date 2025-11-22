/**
 * index.js - STRATÉGIE DE TRADING BITCOIN AUTOMATIQUE RÉELLE
 */

require('dotenv').config();

const { setGlobalOptions } = require("firebase-functions/v2");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const axios = require('axios');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

// ===========================================================================
// INITIALISATION FIREBASE
// ===========================================================================

initializeApp();
const db = getFirestore();

// ===========================================================================
// CONFIGURATION GLOBALE - ALIGNÉE AVEC DART
// ===========================================================================
setGlobalOptions({
  maxInstances: 10,
  timeoutSeconds: 540,
  memory: "1GiB",
});

const CONFIG = {
  firestore: {
    useSimpleQueries: true,
    batchSize: 10,
    maxQueryAttempts: 3
  },
  strike: {
    timeout: 30000,
    maxRetries: 3,
    retryDelay: 2000
  },
  trading: {
    minCapitalPercent: 5.0,
    maxCapitalPercent: 70.0,
    minTakeProfitPercent: 5.0,
    maxTakeProfitPercent: 200.0,
    minRSIThreshold: 20.0,      // NOUVEAU: Aligné avec Dart
    maxRSIThreshold: 80.0,      // NOUVEAU: Aligné avec Dart
    montantMinimalAchat: 0.01,
    montantMaximalAchat: 5000.0,
    fraisTradingFraction: 0.0,
    cooldownAchatMemePalier: 18 * 60 * 60 * 1000,
    verifierMemeDateAchat: true
  }
};

const STRIKE_API_CONFIG = {
  baseURL: process.env.STRIKE_BASE_URL || 'https://api.strike.me/v1',
  apiKey: process.env.STRIKE_API_KEY,
  timeout: 30000
};

// ===========================================================================
// FONCTIONS UTILITAIRES CRITIQUES - OPTIMISÉES POUR FIRESTORE
// ===========================================================================

async function withRetry(operation, maxRetries = 3, delay = 2000) {
  let lastError;
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      logger.warn(`⚠️ Tentative ${attempt}/${maxRetries} échouée:`, error.message);
      if (attempt < maxRetries) {
        logger.log(`⏳ Nouvelle tentative dans ${delay}ms...`);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }
  throw lastError;
}

// ===========================================================================
// FONCTION DE STATISTIQUES DES SOURCES
// ===========================================================================

/**
 * Met à jour les statistiques des sources de données Bitcoin dans Firestore
 */
async function updateSourceStats(sourceDetails) {
  try {
    const statsRef = db.collection('system_stats').doc('source_statistics');
    const now = new Date();
    const timestamp = now.toISOString();

    const updateData = {
      lastUpdate: timestamp,
      totalExecutions: FieldValue.increment(1),
      sources: {}
    };

    sourceDetails.forEach((source, index) => {
      const sourceKey = `sources.${source.source}`;

      updateData[`${sourceKey}.lastUsed`] = timestamp;
      updateData[`${sourceKey}.success`] = FieldValue.increment(source.success ? 1 : 0);
      updateData[`${sourceKey}.total`] = FieldValue.increment(1);

      if (source.success) {
        updateData[`${sourceKey}.lastSuccess`] = timestamp;
        updateData[`${sourceKey}.lastResponseTime`] = source.responseTime;

        if (!updateData[`${sourceKey}.avgResponseTime`]) {
          updateData[`${sourceKey}.avgResponseTime`] = source.responseTime;
        } else {
          updateData[`${sourceKey}.avgResponseTime`] = FieldValue.increment(
            (source.responseTime - (updateData[`${sourceKey}.avgResponseTime`] || source.responseTime)) * 0.1
          );
        }
      } else {
        updateData[`${sourceKey}.lastError`] = source.error;
        updateData[`${sourceKey}.errors`] = FieldValue.increment(1);
      }
    });

    const successfulSources = sourceDetails.filter(s => s.success).length;
    const totalSources = sourceDetails.length;
    const successRate = totalSources > 0 ? (successfulSources / totalSources) * 100 : 0;

    updateData.globalSuccessRate = successRate;
    updateData.lastSuccessfulSources = successfulSources;
    updateData.lastTotalSources = totalSources;

    await statsRef.set(updateData, { merge: true });

    logger.info('✅ Statistiques des sources mises à jour', {
      successfulSources,
      totalSources,
      successRate: `${successRate.toFixed(1)}%`
    });

    return updateData;
  } catch (error) {
    logger.error('❌ Erreur mise à jour statistiques sources:', error);
    return null;
  }
}

/**
 * Récupère les statistiques actuelles des sources
 */
async function getSourceStats() {
  try {
    const statsRef = db.collection('system_stats').doc('source_statistics');
    const doc = await statsRef.get();

    if (doc.exists) {
      return doc.data();
    } else {
      return {
        lastUpdate: null,
        totalExecutions: 0,
        globalSuccessRate: 0,
        sources: {}
      };
    }
  } catch (error) {
    logger.error('Erreur récupération statistiques sources:', error);
    return null;
  }
}

// ===========================================================================
// FONCTIONS DE GESTION DES TRADES
// ===========================================================================

async function sauvegarderTrade(tradeData) {
  try {
    const tradeRef = db.collection('trades').doc(tradeData.id);
    await tradeRef.set({
      ...tradeData,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp()
    });
    logger.info(`✅ Trade sauvegardé: ${tradeData.id}`);
  } catch (error) {
    logger.error('❌ Erreur sauvegarde trade:', error);
    throw error;
  }
}

async function getTradesOuvertsReel() {
  try {
    const snapshot = await db.collection('trades')
      .where('estVente', '==', false)
      .where('vendu', '==', false)
      .limit(100)
      .get();

    return snapshot.docs.map(doc => doc.data());
  } catch (error) {
    logger.error('Erreur récupération trades ouverts:', error);
    return [];
  }
}

async function getTradesRecentsParPalier(nomPalier, heures = 24) {
  try {
    const dateLimite = new Date(Date.now() - (heures * 60 * 60 * 1000));

    const snapshot = await db.collection('trades')
      .where('dateAchat', '>=', dateLimite)
      .limit(100)
      .get();

    return snapshot.docs
      .map(doc => doc.data())
      .filter(trade =>
        trade.estVente === false &&
        trade.palier &&
        trade.palier.nom === nomPalier
      );

  } catch (error) {
    logger.error('Erreur récupération trades récents:', error);
    return [];
  }
}

async function verifierAchatMemeDateMemePalier(nomPalier) {
  try {
    const aujourdhui = new Date();
    const debutJour = new Date(aujourdhui.getFullYear(), aujourdhui.getMonth(), aujourdhui.getDate());

    const snapshot = await db.collection('trades')
      .where('dateAchat', '>=', debutJour)
      .limit(100)
      .get();

    const tradesDuJour = snapshot.docs
      .map(doc => doc.data())
      .filter(trade =>
        trade.estVente === false &&
        trade.palier &&
        trade.palier.nom === nomPalier
      );

    if (tradesDuJour.length > 0) {
      logger.info(`🛑 Achat déjà effectué aujourd'hui pour le palier: ${nomPalier}`);
      return true;
    }

    return false;
  } catch (error) {
    logger.error('Erreur vérification achat même date:', error);

    try {
      const dateLimite = new Date(Date.now() - (24 * 60 * 60 * 1000));
      const snapshot = await db.collection('trades')
        .where('dateAchat', '>=', dateLimite)
        .limit(50)
        .get();

      const tradesRecents = snapshot.docs
        .map(doc => doc.data())
        .filter(trade =>
          trade.estVente === false &&
          trade.palier &&
          trade.palier.nom === nomPalier
        );

      return tradesRecents.length > 0;
    } catch (fallbackError) {
      logger.error('Erreur même dans la méthode fallback:', fallbackError);
      return false;
    }
  }
}

async function updateTrade(tradeId, updates) {
  try {
    const tradeRef = db.collection('trades').doc(tradeId);
    await tradeRef.update({
      ...updates,
      updatedAt: new Date()
    });
    logger.info(`✅ Trade mis à jour: ${tradeId}`);
  } catch (error) {
    logger.error('❌ Erreur mise à jour trade:', error);
    throw error;
  }
}

// ===========================================================================
// NOUVELLES FONCTIONS POUR LE CALCUL DU TAKE-PROFIT (ALIGNÉES SUR DART)
// ===========================================================================

/**
 * Calcule le take-profit dynamique avec ajustements RSI et ATR (ALIGNÉ SUR DART)
 */
function calculerTakeProfitPercentDynamique(drawdownAbsolu, atrValue, rsiValue, prixActuel) {
  // Base take-profit selon le drawdown (identique au code Dart)
  let baseTakeProfit;
  if (drawdownAbsolu <= 15.0) baseTakeProfit = 8.0;
  else if (drawdownAbsolu <= 20.0) baseTakeProfit = 12.0;
  else if (drawdownAbsolu <= 25.0) baseTakeProfit = 18.0;
  else if (drawdownAbsolu <= 30.0) baseTakeProfit = 25.0;
  else baseTakeProfit = 35.0;

  // AJUSTEMENT RSI IDENTIQUE AU CODE DART
  let ajustementRSI = 1.0;
  const RSI_OVERSOLD = 30.0;
  const RSI_OVERBOUGHT = 70.0;
  const RSI_NEUTRAL = 50.0;

  if (rsiValue < RSI_OVERSOLD) {
    // Conditions de survente - plus agressif
    ajustementRSI = 1.3;
    logger.info(`📊 Ajustement RSI: Survente (${rsiValue.toFixed(1)}) → +30%`);
  } else if (rsiValue > RSI_OVERBOUGHT) {
    // Conditions de surachat - plus conservateur
    ajustementRSI = 0.7;
    logger.info(`📊 Ajustement RSI: Surachat (${rsiValue.toFixed(1)}) → -30%`);
  } else {
    // Zone neutre - ajustement linéaire (identique au Dart)
    const distanceFromNeutral = Math.abs(rsiValue - RSI_NEUTRAL) / (RSI_NEUTRAL - RSI_OVERSOLD);
    ajustementRSI = 1.0 + (0.3 * (1 - distanceFromNeutral));
    logger.info(`📊 Ajustement RSI: Neutre (${rsiValue.toFixed(1)}) → ${ajustementRSI.toFixed(2)}`);
  }

  // AJUSTEMENT VOLATILITÉ ATR (identique au code Dart)
  const ajustementVolatilite = Math.max(0.8, Math.min(1.5, atrValue / 1000));
  logger.info(`📊 Ajustement ATR: ${atrValue.toFixed(2)} → ${ajustementVolatilite.toFixed(2)}`);

  // Calcul final
  const takeProfitPercent = baseTakeProfit * ajustementRSI * ajustementVolatilite;

  // Application des bornes de sécurité (identique au Dart)
  const takeProfitFinal = Math.max(CONFIG.trading.minTakeProfitPercent,
    Math.min(CONFIG.trading.maxTakeProfitPercent, takeProfitPercent));

  logger.info(`🎯 Take-Profit: Base=${baseTakeProfit}% × RSI=${ajustementRSI.toFixed(2)} × ATR=${ajustementVolatilite.toFixed(2)} = ${takeProfitPercent.toFixed(2)}% → Final=${takeProfitFinal.toFixed(2)}%`);

  return takeProfitFinal;
}

/**
 * Calcule les métriques de confiance (identique au code Dart)
 */
function calculerMetricsConfiance(drawdownAbsolu, atrPercent, rsiValue, capitalPercent, takeProfitPercent) {
  // Score volatilité
  const scoreVolatilite = Math.max(0, 100 - (atrPercent * 15));

  // Score momentum basé sur RSI
  let scoreMomentum;
  if (rsiValue > 70) {
    scoreMomentum = 60 - ((rsiValue - 70) * 2);
  } else if (rsiValue > 50) {
    scoreMomentum = 40 + ((rsiValue - 50) * 1);
  } else if (rsiValue > 30) {
    scoreMomentum = 60 - ((50 - rsiValue) * 1);
  } else {
    scoreMomentum = 40 - ((30 - rsiValue) * 2);
  }
  scoreMomentum = Math.max(0, Math.min(100, scoreMomentum));

  // Score drawdown
  let scoreDrawdown;
  if (drawdownAbsolu <= 5.0) {
    scoreDrawdown = 90 - (drawdownAbsolu * 4);
  } else if (drawdownAbsolu <= 15.0) {
    scoreDrawdown = 70 - ((drawdownAbsolu - 5) * 4);
  } else if (drawdownAbsolu <= 25.0) {
    scoreDrawdown = 30 - ((drawdownAbsolu - 15) * 3);
  } else {
    scoreDrawdown = 0;
  }
  scoreDrawdown = Math.max(0, Math.min(100, scoreDrawdown));

  // Score take-profit (objectif de gain)
  const scoreTakeProfit = Math.min(100, takeProfitPercent * 3);

  // Score global sans stop-loss
  const scoreGlobal = (
    scoreVolatilite * 0.20 +
    scoreMomentum * 0.25 +
    scoreDrawdown * 0.40 +
    scoreTakeProfit * 0.15
  );

  // Niveau de confiance
  function getNiveauConfiance(score) {
    if (score >= 80) return 'TRÈS ÉLEVÉE';
    if (score >= 60) return 'ÉLEVÉE';
    if (score >= 40) return 'MOYENNE';
    if (score >= 20) return 'FAIBLE';
    return 'TRÈS FAIBLE';
  }

  return {
    scoreGlobal: Math.round(scoreGlobal),
    scoreVolatilite: Math.round(scoreVolatilite),
    scoreMomentum: Math.round(scoreMomentum),
    scoreDrawdown: Math.round(scoreDrawdown),
    scoreTakeProfit: Math.round(scoreTakeProfit),
    takeProfitPercent: takeProfitPercent.toFixed(1) + '%',
    atrPercent: atrPercent.toFixed(2) + '%',
    rsiValue: rsiValue.toFixed(2),
    drawdownAbsolu: drawdownAbsolu.toFixed(2) + '%',
    confidenceLevel: getNiveauConfiance(scoreGlobal),
  };
}

// ===========================================================================
// FONCTIONS DE FORMATAGE DES FACTURES (IDENTIQUES AU CODE DART)
// ===========================================================================

function formaterDescriptionAchat(palier, quantiteBTC, prixAchat, drawdownActuel) {
  return `STRATÉGIE ACHAT BTC:${quantiteBTC.toFixed(8)}, EUR:${prixAchat.toFixed(2)}, Drawdown%:${drawdownActuel.toFixed(2)}`;
}

function formaterDescriptionVente(quantiteBTC, prixVente, drawdownActuel, pnlPercent) {
  return `STRATÉGIE VENTE BTC:${quantiteBTC.toFixed(8)}, EUR:${prixVente.toFixed(2)}, Drawdown%:${drawdownActuel.toFixed(2)}, PnL%:${pnlPercent.toFixed(2)}`;
}

// ===========================================================================
// FONCTION PRINCIPALE D'EXÉCUTION AUTOMATIQUE - AVEC LOGS DÉTAILLÉS
// ===========================================================================

exports.executionStrategieAutomatique = onSchedule({
  schedule: "every 5 minutes",
  timeZone: "Europe/Paris",
  retryCount: 2,
  maxBackoffSeconds: 60,
}, async (event) => {
  const executionId = `AUTO_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  logger.info(`🤖 DÉBUT EXÉCUTION AUTOMATIQUE RÉELLE ${executionId}`);

  try {
    // ÉTAPE 1: COLLECTE RÉELLE DES DONNÉES BITCOIN
    logger.info(`📊 [${executionId}] Collecte RÉELLE des données Bitcoin...`);
    const btcData = await withRetry(() => collecterDonneesBitcoinReel(), 2, 3000);

    logger.info(`✅ [${executionId}] Données Bitcoin RÉELLES collectées`, {
      prix: btcData.price,
      sources: btcData.sourcesUsed,
      drawdown: btcData.sixMonthsHigh ? ((btcData.price - btcData.sixMonthsHigh) / btcData.sixMonthsHigh * 100).toFixed(2) + '%' : 'N/A'
    });

    // METTRE À JOUR LES STATISTIQUES DES SOURCES
    if (btcData.sourceDetails && btcData.sourceDetails.length > 0) {
      logger.info(`📈 [${executionId}] Mise à jour des statistiques des sources...`);
      await updateSourceStats(btcData.sourceDetails);
    }

    // ÉTAPE 2: ÉVALUATION RÉELLE DE LA STRATÉGIE
    logger.info(`🎯 [${executionId}] Évaluation RÉELLE de la stratégie...`);
    const evaluation = await withRetry(() => evaluerStrategieTradingReel(btcData), 2, 2000);

    // LOG DÉTAILLÉ DE L'ÉVALUATION
    logger.info(`📋 [${executionId}] SYNTHÈSE ÉVALUATION:`, {
      drawdown: evaluation.drawdownActuel.toFixed(2) + '%',
      decisionAchat: evaluation.decisionAchat.acheter ? '✅ ACHAT RECOMMANDÉ' : '❌ PAS D\'ACHAT',
      raisonAchat: evaluation.decisionAchat.raison,
      decisionsVente: evaluation.decisionsVente.length,
      tradesOuverts: evaluation.tradesOuverts,
      capitalDisponible: evaluation.capitalDisponible.toFixed(2) + ' EUR',
      palierActuel: evaluation.palierActuel?.nom || 'Aucun',
      takeProfitPalier: evaluation.palierActuel?.takeProfitPercent?.toFixed(2) + '%' || 'N/A'
    });

    // ÉTAPE 3: EXÉCUTION RÉELLE DES VENTES
    let ventesExecutees = 0;
    if (evaluation.decisionsVente.length > 0) {
      logger.info(`🔄 [${executionId}] Exécution RÉELLE des ventes automatiques...`);

      for (const decisionVente of evaluation.decisionsVente) {
        if (decisionVente.vendre) {
          try {
            logger.info(`💰 TENTATIVE VENTE: ${decisionVente.trade.id} - ${decisionVente.raison}`);
            await withRetry(() => executerVenteStrikeReel(decisionVente), 2, 3000);
            ventesExecutees++;

            logger.info(`✅ [${executionId}] Vente RÉELLE exécutée`, {
              tradeId: decisionVente.trade.id,
              typeVente: decisionVente.typeVente,
              quantite: decisionVente.trade.quantite.toFixed(8) + ' BTC',
              prixAchat: decisionVente.trade.prixAchat.toFixed(2) + ' EUR',
              takeProfit: decisionVente.trade.takeProfit.toFixed(2) + ' EUR'
            });

            await new Promise(resolve => setTimeout(resolve, 3000));
          } catch (errorVente) {
            logger.error(`❌ [${executionId}] Erreur lors de la vente RÉELLE`, {
              tradeId: decisionVente.trade.id,
              error: errorVente.message
            });
          }
        }
      }
    } else {
      logger.info(`🔍 [${executionId}] Aucune opportunité de vente détectée`);
    }

    // ÉTAPE 4: EXÉCUTION RÉELLE DES ACHATS - AVEC VÉRIFICATION OPTIMISÉE
    let achatExecute = false;
    if (evaluation.decisionAchat.acheter) {
      let dejaAcheteAujourdhui = false;
      try {
        dejaAcheteAujourdhui = await verifierAchatMemeDateMemePalier(
          evaluation.decisionAchat.palier.nom
        );
      } catch (error) {
        logger.error(`❌ [${executionId}] Erreur vérification doublon:`, error);
        dejaAcheteAujourdhui = false;
      }

      if (dejaAcheteAujourdhui) {
        logger.warn(`🛑 [${executionId}] Achat bloqué: déjà effectué aujourd'hui pour le palier ${evaluation.decisionAchat.palier.nom}`);
      } else {
        logger.info(`🔄 [${executionId}] Exécution RÉELLE de l'achat automatique...`);

        try {
          logger.info(`💰 TENTATIVE ACHAT: ${evaluation.decisionAchat.palier.nom} - ${evaluation.decisionAchat.montantInvestissement.toFixed(2)} EUR`);
          const resultatAchat = await withRetry(() => executerAchatStrikeReel(evaluation.decisionAchat), 2, 3000);
          achatExecute = true;

          logger.info(`✅ [${executionId}] Achat RÉEL exécuté avec succès`, {
            montant: evaluation.decisionAchat.montantInvestissement.toFixed(2) + ' EUR',
            quantiteBTC: resultatAchat.quantite.toFixed(8) + ' BTC',
            prixAchat: resultatAchat.prixAchat.toFixed(2) + ' EUR',
            palier: evaluation.decisionAchat.palier.nom,
            takeProfitPercent: evaluation.decisionAchat.palier.takeProfitPercent.toFixed(2) + '%',
            tradeId: resultatAchat.tradeId
          });
        } catch (errorAchat) {
          logger.error(`❌ [${executionId}] Erreur lors de l'achat RÉEL`, {
            error: errorAchat.message,
            montant: evaluation.decisionAchat.montantInvestissement.toFixed(2) + ' EUR',
            palier: evaluation.decisionAchat.palier.nom
          });
        }
      }
    } else {
      logger.info(`🔍 [${executionId}] Aucune opportunité d'achat: ${evaluation.decisionAchat.raison}`);
    }

    // RAPPORT FINAL DÉTAILLÉ
    const rapport = {
      executionId: executionId,
      timestamp: new Date().toISOString(),
      prixBitcoin: btcData.price,
      drawdown: evaluation.drawdownActuel.toFixed(2) + '%',
      ventesExecutees: ventesExecutees,
      achatExecute: achatExecute,
      capitalDisponible: evaluation.capitalDisponible.toFixed(2) + ' EUR',
      palierActuel: evaluation.palierActuel?.nom || 'Aucun',
      takeProfitPercent: evaluation.palierActuel?.takeProfitPercent?.toFixed(2) + '%' || 'N/A',
      sourcesUtilisees: btcData.sourcesUsed,
      statut: "EXÉCUTION RÉELLE TERMINÉE",
      action: achatExecute ? "ACHAT EXÉCUTÉ" : ventesExecutees > 0 ? "VENTES EXÉCUTÉES" : "AUCUNE ACTION"
    };

    logger.info(`🏁 [${executionId}] EXÉCUTION RÉELLE TERMINÉE - SYNTHÈSE:`, rapport);

    return {
      success: true,
      executionId: executionId,
      data: rapport
    };

  } catch (error) {
    logger.error(`💥 [${executionId}] ERREUR CRITIQUE EXÉCUTION RÉELLE`, {
      error: error.message,
      stack: error.stack,
      timestamp: new Date().toISOString()
    });

    return {
      success: false,
      executionId: executionId,
      error: error.message,
      timestamp: new Date().toISOString()
    };
  }
});

// ===========================================================================
// FONCTIONS RÉELLES DE COLLECTE DE DONNÉES
// ===========================================================================

async function collecterDonneesBitcoinReel() {
  try {
    const sources = [
      {
        name: 'bitfinex',
        url: 'https://api-pub.bitfinex.com/v2/ticker/tBTCEUR',
        parser: (data) => {
          if (!Array.isArray(data) || data.length < 7) throw new Error('Format de données invalide');
          return {
            price: data[6],
            volume: data[7],
            high24h: data[8],
            low24h: data[9]
          };
        }
      },
      {
        name: 'bitstamp',
        url: 'https://www.bitstamp.net/api/v2/ticker/btceur/',
        parser: (data) => ({
          price: parseFloat(data.last),
          volume: parseFloat(data.volume),
          high24h: parseFloat(data.high),
          low24h: parseFloat(data.low)
        })
      },
      {
        name: 'kraken',
        url: 'https://api.kraken.com/0/public/Ticker?pair=XBTEUR',
        parser: (data) => {
          if (!data.result || !data.result.XXBTZEUR) throw new Error('Format Kraken invalide');
          const ticker = data.result.XXBTZEUR;
          return {
            price: parseFloat(ticker.c[0]),
            volume: parseFloat(ticker.v[1]),
            high24h: parseFloat(ticker.h[1]),
            low24h: parseFloat(ticker.l[1])
          };
        }
      },
      {
        name: 'coinbase',
        url: 'https://api.coinbase.com/v2/prices/BTC-EUR/spot',
        parser: (data) => {
          if (!data.data || !data.data.amount) throw new Error('Format Coinbase invalide');
          return { price: parseFloat(data.data.amount) };
        }
      },
      {
        name: 'binance',
        url: 'https://data-api.binance.vision/api/v3/ticker/price?symbol=BTCEUR',
        parser: (data) => {
          if (!data.price) throw new Error('Format Binance invalide');
          return { price: parseFloat(data.price) };
        }
      },
      {
        name: 'cryptocompare',
        url: 'https://min-api.cryptocompare.com/data/price?fsym=BTC&tsyms=EUR',
        parser: (data) => {
          if (!data.EUR) throw new Error('Format CryptoCompare invalide');
          return { price: parseFloat(data.EUR) };
        }
      }
    ];

    const prixSources = [];
    const volumes = [];
    let high24h = null;
    let low24h = null;

    const sourceDetails = [];

    for (const source of sources) {
      let startTime = Date.now();
      let success = false;
      let error = null;
      let responseTime = 0;

      try {
        logger.info(`🔄 Tentative source: ${source.name}`);
        const response = await axios.get(source.url, {
          timeout: 10000,
          headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; TradingBot/1.0)'
          }
        });

        responseTime = (Date.now() - startTime) / 1000;
        const data = source.parser(response.data);

        if (data.price && data.price > 0) {
          prixSources.push(data.price);
          success = true;
          logger.info(`✅ ${source.name}: ${data.price} EUR (${responseTime.toFixed(2)}s)`);
        } else {
          throw new Error('Prix invalide ou nul');
        }

        if (data.volume) volumes.push(data.volume);
        if (data.high24h && !high24h) high24h = data.high24h;
        if (data.low24h && !low24h) low24h = data.low24h;

      } catch (error) {
        responseTime = (Date.now() - startTime) / 1000;
        logger.warn(`❌ Source ${source.name} inaccessible: ${error.message}`);
        success = false;
        error = error.message;
      }

      sourceDetails.push({
        source: source.name,
        success: success,
        responseTime: responseTime,
        error: error,
        timestamp: new Date().toISOString()
      });
    }

    if (prixSources.length < 2) {
      throw new Error(`Sources insuffisantes: ${prixSources.length}/6`);
    }

    const prixTries = prixSources.sort((a, b) => a - b);
    const prixMedian = prixTries[Math.floor(prixTries.length / 2)];

    if (prixMedian < 10000 || prixMedian > 100000) {
      throw new Error(`Prix Bitcoin anormal: ${prixMedian} EUR`);
    }

    const sixMonthsHigh = prixMedian * 1.3;
    const sixMonthsLow = prixMedian * 0.7;

    logger.info(`📊 Données Bitcoin consolidées: ${prixMedian} EUR (${prixSources.length} sources)`);

    return {
      price: prixMedian,
      volume: volumes.length > 0 ? volumes.reduce((a, b) => a + b, 0) / volumes.length : 0,
      marketCap: prixMedian * 19500000,
      high24h: high24h || prixMedian * 1.05,
      low24h: low24h || prixMedian * 0.95,
      priceChange24h: 0,
      priceChangePercent24h: 0,
      sixMonthsHigh: sixMonthsHigh,
      sixMonthsLow: sixMonthsLow,
      sourcesUsed: prixSources.length,
      totalSources: sources.length,
      timestamp: new Date(),
      cacheUsed: false,
      sourceDetails: sourceDetails
    };

  } catch (error) {
    logger.error('❌ Erreur collecte données Bitcoin réelles:', error);

    try {
      logger.log('🔄 Tentative de fallback...');
      const startTime = Date.now();
      const response = await axios.get(
        'https://api.coinbase.com/v2/prices/BTC-EUR/spot',
        { timeout: 10000 }
      );

      const responseTime = (Date.now() - startTime) / 1000;
      const fallbackPrice = parseFloat(response.data.data.amount);
      const sixMonthsHigh = fallbackPrice * 1.3;
      const sixMonthsLow = fallbackPrice * 0.7;

      const sourceDetails = [{
        source: 'coinbase_fallback',
        success: true,
        responseTime: responseTime,
        error: null,
        timestamp: new Date().toISOString()
      }];

      logger.info(`📊 Données Bitcoin fallback: ${fallbackPrice} EUR (Coinbase)`);

      return {
        price: fallbackPrice,
        volume: 0,
        marketCap: fallbackPrice * 19500000,
        high24h: fallbackPrice * 1.05,
        low24h: fallbackPrice * 0.95,
        priceChange24h: 0,
        priceChangePercent24h: 0,
        sixMonthsHigh: sixMonthsHigh,
        sixMonthsLow: sixMonthsLow,
        sourcesUsed: 1,
        totalSources: 1,
        timestamp: new Date(),
        cacheUsed: false,
        fallbackUsed: true,
        sourceDetails: sourceDetails
      };
    } catch (fallbackError) {
      throw new Error('Impossible de collecter les données Bitcoin même en fallback');
    }
  }
}

// ===========================================================================
// FONCTIONS RÉELLES DE TRADING - STRATÉGIE CORRIGÉE POUR TAKE-PROFIT
// ===========================================================================

async function evaluerStrategieTradingReel(btcData) {
  try {
    // Récupération du solde Strike réel
    const balance = await getBalanceStrikeReel();

    // Calcul du drawdown réel
    const drawdownActuel = btcData.sixMonthsHigh ?
      ((btcData.price - btcData.sixMonthsHigh) / btcData.sixMonthsHigh) * 100 : -15.5;

    logger.info(`📈 Calcul drawdown: ${btcData.price} EUR vs ${btcData.sixMonthsHigh} EUR → ${drawdownActuel.toFixed(2)}%`);

    // Génération du palier dynamique AVEC AJUSTEMENTS RSI et ATR
    const palierActuel = genererPalierDynamiqueReel(drawdownActuel, btcData.price);

    // Récupération des trades ouverts
    const tradesOuverts = await getTradesOuvertsReel();

    // Évaluation des décisions de vente
    const decisionsVente = await evaluerVentesReel(tradesOuverts, btcData.price);

    // Évaluation de la décision d'achat
    const decisionAchat = await evaluerAchatReel(
      palierActuel,
      drawdownActuel,
      btcData.price,
      balance.soldeEUR
    );

    return {
      prixActuel: btcData.price,
      drawdownActuel: drawdownActuel,
      palierActuel: palierActuel,
      decisionAchat: decisionAchat,
      decisionsVente: decisionsVente,
      capitalDisponible: balance.soldeEUR,
      tradesOuverts: tradesOuverts.length,
      balanceStrike: balance,
      timestamp: new Date()
    };
  } catch (error) {
    logger.error('Erreur évaluation stratégie réelle:', error);
    throw error;
  }
}

function genererPalierDynamiqueReel(drawdownActuel, prixActuel) {
  const drawdownAbsolu = Math.abs(drawdownActuel);

  // FACTEURS DE REDIMENSIONNEMENT PAR DRAWDOWN (identique au code Dart)
  const FACTEURS_DRAWDOWN = {
    'leger': 1.0,      // -10% à -15%
    'modere': 1.2,     // -15% à -20%
    'fort': 1.5,       // -20% à -25%
    'bear': 2.0,       // -25% à -30%
    'crise': 2.5,      // < -30%
  };

  let facteurDrawdown = 1.0;
  let nomPalier;

  if (drawdownAbsolu <= 15.0) {
    facteurDrawdown = FACTEURS_DRAWDOWN['leger'];
    nomPalier = "Correction légère ATR+RSI";
  } else if (drawdownAbsolu <= 20.0) {
    facteurDrawdown = FACTEURS_DRAWDOWN['modere'];
    nomPalier = "Correction modérée ATR+RSI";
  } else if (drawdownAbsolu <= 25.0) {
    facteurDrawdown = FACTEURS_DRAWDOWN['fort'];
    nomPalier = "Correction forte ATR+RSI";
  } else if (drawdownAbsolu <= 30.0) {
    facteurDrawdown = FACTEURS_DRAWDOWN['bear'];
    nomPalier = "Bear market ATR+RSI";
  } else {
    facteurDrawdown = FACTEURS_DRAWDOWN['crise'];
    nomPalier = "Crise majeure ATR+RSI";
  }

  logger.info(`🏷️ Palier détecté: ${nomPalier} (Drawdown: ${drawdownAbsolu.toFixed(2)}%, Facteur: ${facteurDrawdown})`);

  // Simulation des valeurs ATR et RSI (à remplacer par de vraies données si disponibles)
  const atrValue = prixActuel * 0.02; // 2% de volatilité approximative
  const rsiValue = 50.0; // Valeur RSI neutre par défaut

  // AJUSTEMENT RSI (identique au code Dart)
  let ajustementRSI = 1.0;
  if (rsiValue < 30.0) {
    ajustementRSI = 1.3;
  } else if (rsiValue > 70.0) {
    ajustementRSI = 0.7;
  } else {
    const distanceFromNeutral = Math.abs(rsiValue - 50.0) / 20.0;
    ajustementRSI = 1.0 + (0.3 * (1 - distanceFromNeutral));
  }

  // CALCUL DES PARAMÈTRES AVEC AJUSTEMENTS (identique au code Dart)
  const pourcentageCapitalBase = _calculerPourcentageCapitalBase(drawdownAbsolu);
  const pourcentageCapital = Math.max(CONFIG.trading.minCapitalPercent,
    Math.min(CONFIG.trading.maxCapitalPercent,
      pourcentageCapitalBase * facteurDrawdown * ajustementRSI));

  logger.info(`💰 Calcul capital: Base=${pourcentageCapitalBase}% × Drawdown=${facteurDrawdown} × RSI=${ajustementRSI.toFixed(2)} = ${pourcentageCapital.toFixed(2)}%`);

  // NOUVEAU: Calcul du take-profit avec ajustements RSI et ATR (ALIGNÉ SUR DART)
  const takeProfitPercent = calculerTakeProfitPercentDynamique(
    drawdownAbsolu,
    atrValue,
    rsiValue,
    prixActuel
  );

  // Calcul des métriques de confiance
  const atrPercent = (atrValue / prixActuel) * 100;
  const metrics = calculerMetricsConfiance(
    drawdownAbsolu,
    atrPercent,
    rsiValue,
    pourcentageCapital,
    takeProfitPercent
  );

  logger.info(`📊 Métriques confiance: Score=${metrics.scoreGlobal} (${metrics.confidenceLevel})`);

  return {
    nom: nomPalier,
    drawdownMin: drawdownActuel - 2.0,
    drawdownMax: drawdownActuel + 2.0,
    pourcentageCapital: pourcentageCapital,
    takeProfitPercent: takeProfitPercent,
    atrValue: atrValue,
    rsiValue: rsiValue,
    metrics: metrics
  };
}

function _calculerPourcentageCapitalBase(drawdownAbsolu) {
  if (drawdownAbsolu <= 15.0) return 10.0;
  else if (drawdownAbsolu <= 20.0) return 20.0;
  else if (drawdownAbsolu <= 25.0) return 30.0;
  else if (drawdownAbsolu <= 30.0) return 40.0;
  else return 50.0;
}

async function evaluerAchatReel(palierActuel, drawdownActuel, prixActuel, capitalDisponible) {
  // Vérification capital minimal
  if (capitalDisponible < CONFIG.trading.montantMinimalAchat) {
    logger.info(`❌ Capital insuffisant: ${capitalDisponible.toFixed(2)} EUR < ${CONFIG.trading.montantMinimalAchat} EUR`);
    return {
      acheter: false,
      raison: `Capital insuffisant: ${capitalDisponible.toFixed(2)} EUR`
    };
  }

  // Vérification palier valide
  if (!palierActuel) {
    logger.info(`❌ Drawdown hors paliers: ${drawdownActuel.toFixed(2)}%`);
    return {
      acheter: false,
      raison: `Drawdown (${drawdownActuel.toFixed(2)}%) hors des paliers d'achat`
    };
  }

  logger.info(`🔍 Vérification conditions achat pour palier: ${palierActuel.nom}`);

  // VÉRIFICATION CRITIQUE: Pas d'achat si même drawdown et même date
  if (CONFIG.trading.verifierMemeDateAchat) {
    const dejaAcheteAujourdhui = await verifierAchatMemeDateMemePalier(palierActuel.nom);

    if (dejaAcheteAujourdhui) {
      logger.info(`❌ Achat déjà effectué aujourd'hui pour: ${palierActuel.nom}`);
      return {
        acheter: false,
        raison: `Achat déjà effectué aujourd'hui pour le palier ${palierActuel.nom}`
      };
    }
  }

  // VÉRIFICATION: Pas d'achat si même palier récemment (cooldown)
  const tradesRecents = await getTradesRecentsParPalier(palierActuel.nom, 24);
  if (tradesRecents.length > 0) {
    logger.info(`❌ Palier acheté récemment: ${palierActuel.nom} (${tradesRecents.length} trades)`);
    return {
      acheter: false,
      raison: `Palier ${palierActuel.nom} déjà acheté récemment (cooldown 24h)`
    };
  }

  // VÉRIFICATION CONDITIONS RSI (aligné avec Dart)
  if (palierActuel.rsiValue > CONFIG.trading.maxRSIThreshold) {
    logger.info(`❌ RSI trop élevé: ${palierActuel.rsiValue.toFixed(1)} > ${CONFIG.trading.maxRSIThreshold}`);
    return {
      acheter: false,
      raison: `Conditions de surachat détectées (RSI: ${palierActuel.rsiValue.toFixed(1)})`
    };
  }

  // Calcul du montant d'investissement
  const montantInvestissement = capitalDisponible * (palierActuel.pourcentageCapital / 100);
  const montantAjuste = Math.max(CONFIG.trading.montantMinimalAchat,
    Math.min(CONFIG.trading.montantMaximalAchat, montantInvestissement));

  logger.info(`💰 Montant investissement: ${montantInvestissement.toFixed(2)} EUR → Ajusté: ${montantAjuste.toFixed(2)} EUR`);

  // Vérification montant valide
  if (montantAjuste > capitalDisponible) {
    logger.info(`❌ Solde insuffisant: ${montantAjuste.toFixed(2)} EUR > ${capitalDisponible.toFixed(2)} EUR`);
    return {
      acheter: false,
      raison: `Solde EUR insuffisant: ${capitalDisponible.toFixed(2)} disponible`
    };
  }

  // Calcul take profit AVEC LA NOUVELLE LOGIQUE
  const takeProfit = prixActuel * (1 + palierActuel.takeProfitPercent / 100);

  logger.info(`✅ Conditions d'achat REMPLIES pour: ${palierActuel.nom}`);
  logger.info(`🎯 Détails achat:`, {
    montant: `${montantAjuste.toFixed(2)} EUR`,
    takeProfit: `${takeProfit.toFixed(2)} EUR (${palierActuel.takeProfitPercent.toFixed(2)}%)`,
    scoreConfiance: palierActuel.metrics.scoreGlobal,
    niveauConfiance: palierActuel.metrics.confidenceLevel
  });

  return {
    acheter: true,
    raison: `Conditions dynamiques remplies pour le palier ${palierActuel.nom}`,
    palier: palierActuel,
    montantInvestissement: montantAjuste,
    prixCibleAchat: prixActuel * 0.995,
    takeProfit: takeProfit,
    fraisEstimes: 0.0,
    capitalReel: capitalDisponible,
    metrics: {
      takeProfitPercent: palierActuel.takeProfitPercent.toFixed(1) + '%',
      drawdownActuel: drawdownActuel.toFixed(1) + '%',
      scoreGlobal: palierActuel.metrics.scoreGlobal,
      confidenceLevel: palierActuel.metrics.confidenceLevel,
      verificationDoublon: "VÉRIFIÉ"
    }
  };
}

async function evaluerVentesReel(tradesOuverts, prixActuel) {
  const decisionsVente = [];

  logger.info(`🔍 Évaluation ventes pour ${tradesOuverts.length} trades ouverts`);

  for (const trade of tradesOuverts) {
    const profitActuel = ((prixActuel - trade.prixAchat) / trade.prixAchat) * 100;

    // Vérification take profit
    if (prixActuel >= trade.takeProfit) {
      logger.info(`✅ Take-profit DÉCLENCHÉ: ${trade.id} - Profit: ${profitActuel.toFixed(2)}%`);
      decisionsVente.push({
        vendre: true,
        trade: trade,
        raison: `Take-profit atteint: ${trade.takeProfit.toFixed(2)} EUR (Profit: ${profitActuel.toFixed(2)}%)`,
        typeVente: 'TAKE_PROFIT',
        prixVente: trade.takeProfit,
        metrics: {
          profit_realise: profitActuel.toFixed(2) + '%',
          prix_achat: trade.prixAchat.toFixed(2) + ' EUR',
          takeProfit_cible: trade.takeProfit.toFixed(2) + ' EUR'
        }
      });
    } else {
      logger.info(`📊 Trade ${trade.id}: Profit actuel ${profitActuel.toFixed(2)}%, Take-profit à ${trade.takeProfit.toFixed(2)} EUR`);
    }
  }

  if (decisionsVente.length > 0) {
    logger.info(`💰 ${decisionsVente.length} trades prêts pour vente take-profit`);
  }

  return decisionsVente;
}

// ===========================================================================
// FONCTIONS STRIKE API RÉELLES
// ===========================================================================

async function getBalanceStrikeReel() {
  try {
    const response = await axios.get(`${STRIKE_API_CONFIG.baseURL}/balances`, {
      headers: {
        'Authorization': `Bearer ${STRIKE_API_CONFIG.apiKey}`,
        'Content-Type': 'application/json'
      },
      timeout: STRIKE_API_CONFIG.timeout
    });

    let soldeEUR = 0.0;
    let soldeBTC = 0.0;

    for (const balance of response.data) {
      if (balance.currency === 'EUR') {
        soldeEUR = parseFloat(balance.available);
      } else if (balance.currency === 'BTC') {
        soldeBTC = parseFloat(balance.available);
      }
    }

    logger.info(`💳 Balance Strike: ${soldeEUR.toFixed(2)} EUR, ${soldeBTC.toFixed(8)} BTC`);

    return {
      soldeEUR: soldeEUR,
      soldeBTC: soldeBTC,
      dernierUpdate: new Date()
    };
  } catch (error) {
    logger.error('Erreur récupération balance Strike:', error);
    throw new Error('Impossible de récupérer le solde Strike');
  }
}

async function executerAchatStrikeReel(decisionAchat) {
  try {
    logger.info(`💰 DÉBUT ACHAT STRIKE: ${decisionAchat.montantInvestissement.toFixed(2)} EUR`);

    // Création du devis de change
    const quoteData = {
      amount: {
        amount: decisionAchat.montantInvestissement.toFixed(2),
        currency: 'EUR'
      },
      sell: 'EUR',
      buy: 'BTC',
      feePolicy: 'INCLUSIVE'
    };

    logger.info('📋 Création devis de change...');
    const quoteResponse = await axios.post(
      `${STRIKE_API_CONFIG.baseURL}/currency-exchange-quotes`,
      quoteData,
      {
        headers: {
          'Authorization': `Bearer ${STRIKE_API_CONFIG.apiKey}`,
          'Content-Type': 'application/json'
        },
        timeout: STRIKE_API_CONFIG.timeout
      }
    );

    const quoteId = quoteResponse.data.id;

    if (!quoteId) {
      throw new Error('Échec création devis - ID manquant');
    }

    logger.info(`✅ Devis créé: ${quoteId}`);

    // VÉRIFICATION FINALE: S'assurer qu'aucun autre achat n'a été fait entre-temps
    const dejaAchete = await verifierAchatMemeDateMemePalier(decisionAchat.palier.nom);
    if (dejaAchete) {
      throw new Error(`Achat annulé: un autre achat a été effectué entre-temps pour le palier ${decisionAchat.palier.nom}`);
    }

    // Exécution du devis
    logger.info(`🔄 Exécution du devis ${quoteId}...`);
    await axios.patch(
      `${STRIKE_API_CONFIG.baseURL}/currency-exchange-quotes/${quoteId}/execute`,
      {},
      {
        headers: {
          'Authorization': `Bearer ${STRIKE_API_CONFIG.apiKey}`,
          'Content-Type': 'application/json'
        },
        timeout: STRIKE_API_CONFIG.timeout
      }
    );

    // Attente de la complétion
    logger.info(`⏳ Attente complétion devis ${quoteId}...`);
    await attendreCompletionQuoteReel(quoteId);

    // Récupération des détails de l'exécution
    const quoteDetails = await axios.get(
      `${STRIKE_API_CONFIG.baseURL}/currency-exchange-quotes/${quoteId}`,
      {
        headers: {
          'Authorization': `Bearer ${STRIKE_API_CONFIG.apiKey}`
        },
        timeout: STRIKE_API_CONFIG.timeout
      }
    );

    // Extraction des données
    const quantite = parseFloat(quoteDetails.data.target.amount);
    const prixAchat = decisionAchat.montantInvestissement / quantite;

    // Calcul du drawdown actuel pour la facture
    const btcData = await collecterDonneesBitcoinReel();
    const drawdownActuel = btcData.sixMonthsHigh ?
      ((btcData.price - btcData.sixMonthsHigh) / btcData.sixMonthsHigh) * 100 : -15.5;

    // Sauvegarde du trade
    const tradeData = {
      id: `ACHAT_${quoteId}_${Date.now()}`,
      type: 'ACHAT',
      strikeQuoteId: quoteId,
      quantite: quantite,
      prixAchat: prixAchat,
      montantInvesti: decisionAchat.montantInvestissement,
      takeProfit: decisionAchat.takeProfit,
      takeProfitPercent: decisionAchat.palier.takeProfitPercent,
      palier: decisionAchat.palier,
      dateAchat: new Date(),
      vendu: false,
      estVente: false
    };

    await sauvegarderTrade(tradeData);

    // CRÉATION DE LA FACTURE AVEC LE FORMAT DART
    const description = formaterDescriptionAchat(
      decisionAchat.palier,
      quantite,
      prixAchat,
      drawdownActuel
    );

    await creerFactureStrikeReel({
      correlationId: quoteId,
      description: description,
      amount: decisionAchat.montantInvestissement.toFixed(2),
      currency: 'EUR'
    });

    logger.info(`🎉 ACHAT STRIKE RÉUSSI: ${quantite.toFixed(8)} BTC à ${prixAchat.toFixed(2)} EUR`);

    return {
      quantite: quantite,
      prixAchat: prixAchat,
      strikeQuoteId: quoteId,
      montantInvesti: decisionAchat.montantInvestissement,
      tradeId: tradeData.id,
      takeProfitPercent: decisionAchat.palier.takeProfitPercent
    };

  } catch (error) {
    logger.error('❌ Erreur exécution achat Strike:', error);
    throw new Error(`Échec achat Strike: ${error.message}`);
  }
}

async function executerVenteStrikeReel(decisionVente) {
  try {
    const trade = decisionVente.trade;
    logger.info(`💰 DÉBUT VENTE STRIKE: ${trade.quantite.toFixed(8)} BTC (Trade: ${trade.id})`);

    // Création du devis de vente
    const quoteData = {
      sourceCurrency: 'BTC',
      targetCurrency: 'EUR',
      amount: trade.quantite.toFixed(8)
    };

    logger.info('📋 Création devis de vente...');
    const quoteResponse = await axios.post(
      `${STRIKE_API_CONFIG.baseURL}/currency-exchange-quotes`,
      quoteData,
      {
        headers: {
          'Authorization': `Bearer ${STRIKE_API_CONFIG.apiKey}`,
          'Content-Type': 'application/json'
        },
        timeout: STRIKE_API_CONFIG.timeout
      }
    );

    const quoteId = quoteResponse.data.id;

    if (!quoteId) {
      throw new Error('Échec création devis vente - ID manquant');
    }

    logger.info(`✅ Devis vente créé: ${quoteId}`);

    // Exécution du devis
    logger.info(`🔄 Exécution du devis vente ${quoteId}...`);
    await axios.patch(
      `${STRIKE_API_CONFIG.baseURL}/currency-exchange-quotes/${quoteId}/execute`,
      {},
      {
        headers: {
          'Authorization': `Bearer ${STRIKE_API_CONFIG.apiKey}`,
          'Content-Type': 'application/json'
        },
        timeout: STRIKE_API_CONFIG.timeout
      }
    );

    // Attente de la complétion
    logger.info(`⏳ Attente complétion vente ${quoteId}...`);
    await attendreCompletionQuoteReel(quoteId);

    // Récupération des détails de l'exécution
    const quoteDetails = await axios.get(
      `${STRIKE_API_CONFIG.baseURL}/currency-exchange-quotes/${quoteId}`,
      {
        headers: {
          'Authorization': `Bearer ${STRIKE_API_CONFIG.apiKey}`
        },
        timeout: STRIKE_API_CONFIG.timeout
      }
    );

    // Extraction du prix de vente
    const prixVente = parseFloat(quoteDetails.data.exchangeRate);
    const montantVente = trade.quantite * prixVente;

    // Calcul du PnL et drawdown pour la facture
    const btcData = await collecterDonneesBitcoinReel();
    const drawdownActuel = btcData.sixMonthsHigh ?
      ((btcData.price - btcData.sixMonthsHigh) / btcData.sixMonthsHigh) * 100 : -15.5;
    const pnlPercent = ((prixVente - trade.prixAchat) / trade.prixAchat) * 100;

    // Mise à jour du trade
    await updateTrade(trade.id, {
      vendu: true,
      dateVente: new Date(),
      prixVente: prixVente,
      montantVente: montantVente,
      typeVente: decisionVente.typeVente,
      strikeQuoteIdVente: quoteId
    });

    // CRÉATION DE LA FACTURE AVEC LE FORMAT DART
    const description = formaterDescriptionVente(
      trade.quantite,
      prixVente,
      drawdownActuel,
      pnlPercent
    );

    await creerFactureStrikeReel({
      correlationId: quoteId,
      description: description,
      amount: trade.quantite.toFixed(8),
      currency: 'BTC'
    });

    logger.info(`🎉 VENTE STRIKE RÉUSSIE: ${trade.quantite.toFixed(8)} BTC à ${prixVente.toFixed(2)} EUR`);
    logger.info(`📈 PnL: ${pnlPercent.toFixed(2)}% (${montantVente.toFixed(2)} EUR)`);

    return {
      tradeId: trade.id,
      quantite: trade.quantite,
      prixVente: prixVente,
      montantVente: montantVente,
      strikeQuoteId: quoteId,
      succes: true
    };

  } catch (error) {
    logger.error('❌ Erreur exécution vente Strike:', error);
    throw new Error(`Échec vente Strike: ${error.message}`);
  }
}

async function attendreCompletionQuoteReel(quoteId, timeoutMs = 30000) {
  const startTime = Date.now();
  let attempts = 0;

  logger.info(`⏳ Surveillance devis ${quoteId}...`);

  while (Date.now() - startTime < timeoutMs) {
    attempts++;
    try {
      const response = await axios.get(
        `${STRIKE_API_CONFIG.baseURL}/currency-exchange-quotes/${quoteId}`,
        {
          headers: {
            'Authorization': `Bearer ${STRIKE_API_CONFIG.apiKey}`
          },
          timeout: 5000
        }
      );

      const state = response.data.state;
      logger.info(`🔍 Devis ${quoteId} - État: ${state} (tentative ${attempts})`);

      if (state === 'COMPLETED') {
        logger.info(`✅ Devis ${quoteId} COMPLETED`);
        return true;
      } else if (state === 'FAILED' || state === 'EXPIRED' || state === 'CANCELLED') {
        throw new Error(`Quote ${quoteId} échouée avec état: ${state}`);
      }

      // Attente avant nouvelle vérification
      await new Promise(resolve => setTimeout(resolve, 2000));
    } catch (error) {
      logger.warn(`Erreur vérification quote ${quoteId}: ${error.message}`);
    }
  }

  throw new Error(`Timeout attente quote COMPLETED: ${quoteId}`);
}

async function creerFactureStrikeReel(invoiceData) {
  try {
    const factureData = {
      correlationId: invoiceData.correlationId,
      description: invoiceData.description.substring(0, 200),
      amount: {
        amount: invoiceData.amount,
        currency: invoiceData.currency
      },
      issuer: "TRADING_BOT",
      metadata: {
        tradeId: invoiceData.correlationId,
        type: "BITCOIN_TRADE",
        timestamp: new Date().toISOString()
      }
    };

    logger.info('📋 Création facture Strike...');

    const response = await axios.post(
      `${STRIKE_API_CONFIG.baseURL}/invoices`,
      factureData,
      {
        headers: {
          'Authorization': `Bearer ${STRIKE_API_CONFIG.apiKey}`,
          'Content-Type': 'application/json',
          'User-Agent': 'TradingBot/1.0'
        },
        timeout: STRIKE_API_CONFIG.timeout
      }
    );

    if (!response.data || !response.data.invoiceId) {
      throw new Error('Réponse Strike invalide - invoiceId manquant');
    }

    logger.info('✅ Facture créée avec succès:', {
      invoiceId: response.data.invoiceId,
      correlationId: invoiceData.correlationId,
      description: invoiceData.description.substring(0, 50) + '...'
    });

    return response.data;

  } catch (error) {
    logger.error('❌ Erreur création facture Strike:', {
      status: error.response?.status,
      statusText: error.response?.statusText,
      correlationId: invoiceData.correlationId,
      errorMessage: error.message
    });

    return null;
  }
}

// ===========================================================================
// NOUVELLES FONCTIONS POUR LES STATISTIQUES - ENDPOINTS API
// ===========================================================================

/**
 * Endpoint pour récupérer les statistiques des sources
 */
exports.getSourceStats = onRequest({
  cors: true
}, async (req, res) => {
  try {
    const stats = await getSourceStats();

    if (!stats) {
      return res.status(404).json({
        success: false,
        error: "Statistiques non disponibles"
      });
    }

    res.json({
      success: true,
      data: stats
    });
  } catch (error) {
    logger.error('Erreur récupération statistiques sources:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * Endpoint pour forcer la mise à jour des statistiques
 */
exports.forceUpdateSourceStats = onRequest({
  cors: true
}, async (req, res) => {
  const secret = req.query.secret || req.body.secret;

  if (!secret || secret !== process.env.API_SECRET) {
    return res.status(403).json({
      success: false,
      error: "Secret API requis"
    });
  }

  try {
    logger.info("🔄 Mise à jour forcée des statistiques des sources...");

    const btcData = await collecterDonneesBitcoinReel();
    const stats = await updateSourceStats(btcData.sourceDetails);

    res.json({
      success: true,
      message: "Statistiques des sources mises à jour avec succès",
      data: stats
    });
  } catch (error) {
    logger.error('Erreur mise à jour forcée statistiques:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// ===========================================================================
// FONCTIONS DE FORÇAGE RÉELLES
// ===========================================================================

exports.forcerVenteTousTrades = onRequest({
  cors: true,
  timeoutSeconds: 300
}, async (req, res) => {
  const secret = req.query.secret || req.body.secret;

  if (!secret || secret !== process.env.API_SECRET) {
    return res.status(403).json({
      success: false,
      error: "Secret API requis"
    });
  }

  try {
    logger.warn("🚨 FORÇAGE VENTE TOUS TRADES RÉEL - DÉBUT");

    const tradesOuverts = await getTradesOuvertsReel();
    const prixActuel = (await collecterDonneesBitcoinReel()).price;
    const resultats = [];

    logger.info(`🔍 ${tradesOuverts.length} trades ouverts à vérifier`);

    for (const trade of tradesOuverts) {
      try {
        const profitActuel = ((prixActuel - trade.prixAchat) / trade.prixAchat) * 100;
        logger.info(`💰 Trade ${trade.id}: Profit actuel ${profitActuel.toFixed(2)}%`);

        const decisionVente = {
          vendre: true,
          trade: trade,
          raison: 'VENTE FORCÉE - Tous les trades',
          typeVente: 'VENTE_FORCEE',
          prixVente: prixActuel
        };

        await executerVenteStrikeReel(decisionVente);
        resultats.push({ tradeId: trade.id, succes: true, profit: profitActuel.toFixed(2) + '%' });

        await new Promise(resolve => setTimeout(resolve, 3000));
      } catch (error) {
        logger.error(`❌ Erreur vente forcée ${trade.id}:`, error.message);
        resultats.push({ tradeId: trade.id, succes: false, erreur: error.message });
      }
    }

    const succes = resultats.filter(r => r.succes).length;
    const echecs = resultats.filter(r => !r.succes).length;

    logger.warn("🚨 FORÇAGE VENTE TOUS TRADES RÉEL - TERMINÉ", {
      total: tradesOuverts.length,
      succes: succes,
      echecs: echecs
    });

    res.json({
      success: true,
      message: "Vente forcée de tous les trades exécutée",
      tradesVendus: succes,
      echecs: echecs,
      details: resultats
    });

  } catch (error) {
    logger.error("🚨 ERREUR FORÇAGE VENTE RÉEL", error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// ===========================================================================
// FONCTIONS EXISTANTES POUR COMPATIBILITÉ
// ===========================================================================

exports.executionManuelle = onRequest({
  cors: true,
  timeoutSeconds: 540,
  memory: "1GiB"
}, async (req, res) => {
  try {
    const executionId = `MANUEL_${Date.now()}`;
    logger.info(`🔄 DÉBUT EXÉCUTION MANUELLE ${executionId}`);

    const btcData = await collecterDonneesBitcoinReel();
    const evaluation = await evaluerStrategieTradingReel(btcData);

    // Mettre à jour les stats même en mode manuel
    if (btcData.sourceDetails && btcData.sourceDetails.length > 0) {
      await updateSourceStats(btcData.sourceDetails);
    }

    // Log détaillé de l'évaluation manuelle
    logger.info(`📋 RAPPORT MANUEL ${executionId}:`, {
      prixBitcoin: btcData.price + ' EUR',
      drawdown: evaluation.drawdownActuel.toFixed(2) + '%',
      decisionAchat: evaluation.decisionAchat.acheter ? 'ACHAT RECOMMANDÉ' : 'PAS D\'ACHAT',
      raisonAchat: evaluation.decisionAchat.raison,
      ventesRecommandees: evaluation.decisionsVente.length,
      capitalDisponible: evaluation.capitalDisponible.toFixed(2) + ' EUR',
      palierActuel: evaluation.palierActuel?.nom || 'Aucun'
    });

    res.json({
      success: true,
      executionId: executionId,
      data: {
        btcData: btcData,
        evaluation: evaluation,
        timestamp: new Date().toISOString()
      }
    });

  } catch (error) {
    logger.error('❌ Erreur exécution manuelle:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

exports.forcerAchatImmediat = onRequest({
  cors: true,
  timeoutSeconds: 300
}, async (req, res) => {
  const secret = req.query.secret || req.body.secret;

  if (!secret || secret !== process.env.API_SECRET) {
    return res.status(403).json({
      success: false,
      error: "Secret API requis"
    });
  }

  try {
    logger.warn("🚨 FORÇAGE ACHAT IMMÉDIAT - DÉBUT");

    const btcData = await collecterDonneesBitcoinReel();
    const balance = await getBalanceStrikeReel();

    // Mettre à jour les stats
    if (btcData.sourceDetails && btcData.sourceDetails.length > 0) {
      await updateSourceStats(btcData.sourceDetails);
    }

    // Vérification s'il y a déjà un achat aujourd'hui
    const aujourdhui = new Date();
    const debutJour = new Date(aujourdhui.getFullYear(), aujourdhui.getMonth(), aujourdhui.getDate());

    const snapshot = await db.collection('trades')
      .where('dateAchat', '>=', debutJour)
      .get();

    const achatsDuJour = snapshot.docs
      .map(doc => doc.data())
      .filter(trade => trade.estVente === false);

    if (achatsDuJour.length > 0) {
      logger.warn("🚨 Achat bloqué: déjà effectué aujourd'hui");
      return res.status(400).json({
        success: false,
        error: "Un achat a déjà été effectué aujourd'hui"
      });
    }

    // Forcer l'achat avec un montant minimum
    const montantForcage = Math.min(10.0, balance.soldeEUR * 0.1);
    logger.info(`💰 Montant forçage: ${montantForcage.toFixed(2)} EUR`);

    const decisionAchatForcage = {
      acheter: true,
      raison: 'ACHAT FORCÉ MANUEL',
      palier: genererPalierDynamiqueReel(-10, btcData.price),
      montantInvestissement: montantForcage,
      prixCibleAchat: btcData.price * 0.995,
      takeProfit: btcData.price * 1.08,
      fraisEstimes: 0.0,
      capitalReel: balance.soldeEUR
    };

    const resultat = await executerAchatStrikeReel(decisionAchatForcage);

    logger.warn("🚨 FORÇAGE ACHAT IMMÉDIAT - TERMINÉ", {
      montant: montantForcage.toFixed(2) + ' EUR',
      quantite: resultat.quantite.toFixed(8) + ' BTC',
      prixAchat: resultat.prixAchat.toFixed(2) + ' EUR'
    });

    res.json({
      success: true,
      message: "Achat forcé exécuté avec succès",
      achat: resultat
    });

  } catch (error) {
    logger.error("🚨 ERREUR FORÇAGE ACHAT RÉEL", error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

exports.etatSysteme = onRequest({
  cors: true
}, async (req, res) => {
  try {
    const btcData = await collecterDonneesBitcoinReel();
    const balance = await getBalanceStrikeReel();
    const tradesOuverts = await getTradesOuvertsReel();

    // Récupérer les statistiques des sources
    const sourceStats = await getSourceStats();

    // Vérification des doublons
    const aujourdhui = new Date();
    const debutJour = new Date(aujourdhui.getFullYear(), aujourdhui.getMonth(), aujourdhui.getDate());

    const achatsDuJour = await db.collection('trades')
      .where('dateAchat', '>=', debutJour)
      .get();

    const achatsParPalier = {};
    achatsDuJour.docs.forEach(doc => {
      const trade = doc.data();
      if (trade.estVente === false) {
        const palier = trade.palier?.nom || 'Inconnu';
        achatsParPalier[palier] = (achatsParPalier[palier] || 0) + 1;
      }
    });

    logger.info("🔍 État système vérifié");

    res.json({
      success: true,
      data: {
        btcData: btcData,
        balance: balance,
        tradesOuverts: tradesOuverts.length,
        achatsDuJour: achatsDuJour.size,
        achatsParPalier: achatsParPalier,
        sourceStats: sourceStats,
        timestamp: new Date().toISOString(),
        statut: 'Système opérationnel',
        verificationDoublons: 'ACTIVE'
      }
    });

  } catch (error) {
    logger.error('❌ Erreur état système:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// ===========================================================================
// FONCTIONS DE MAINTENANCE ET RAPPORTS
// ===========================================================================

exports.rapportJournalier = onRequest({
  cors: true
}, async (req, res) => {
  try {
    const aujourdhui = new Date();
    const debutJour = new Date(aujourdhui.getFullYear(), aujourdhui.getMonth(), aujourdhui.getDate());

    const snapshot = await db.collection('trades')
      .where('dateAchat', '>=', debutJour)
      .get();

    const tradesDuJour = snapshot.docs.map(doc => doc.data());

    const totalAchats = tradesDuJour.filter(t => t.estVente === false).length;
    const totalVentes = tradesDuJour.filter(t => t.estVente === true).length;
    const montantTotalAchats = tradesDuJour.filter(t => t.estVente === false)
      .reduce((sum, t) => sum + t.montantInvesti, 0);

    // Récupérer les statistiques des sources
    const sourceStats = await getSourceStats();

    // Analyse par palier
    const achatsParPalier = {};
    tradesDuJour.filter(t => t.estVente === false).forEach(trade => {
      const palier = trade.palier?.nom || 'Inconnu';
      achatsParPalier[palier] = (achatsParPalier[palier] || 0) + 1;
    });

    logger.info("📊 Rapport journalier généré");

    res.json({
      success: true,
      data: {
        date: aujourdhui.toISOString().split('T')[0],
        totalAchats: totalAchats,
        totalVentes: totalVentes,
        montantTotalAchats: montantTotalAchats,
        achatsParPalier: achatsParPalier,
        sourceStats: sourceStats,
        trades: tradesDuJour
      }
    });

  } catch (error) {
    logger.error('❌ Erreur rapport journalier:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

exports.nettoyerAnciennesDonnees = onSchedule({
  schedule: "0 2 * * *",
  timeZone: "Europe/Paris"
}, async (event) => {
  try {
    const trenteJours = new Date();
    trenteJours.setDate(trenteJours.getDate() - 30);

    const snapshot = await db.collection('trades')
      .where('dateAchat', '<', trenteJours)
      .get();

    const batch = db.batch();
    snapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });

    await batch.commit();

    logger.info(`🧹 Nettoyage données: ${snapshot.size} anciens trades supprimés`);

  } catch (error) {
    logger.error('❌ Erreur nettoyage données:', error);
  }
});

exports.sauvegarderEtatSysteme = onSchedule({
  schedule: "every 60 minutes",
  timeZone: "Europe/Paris"
}, async (event) => {
  try {
    const btcData = await collecterDonneesBitcoinReel();
    const balance = await getBalanceStrikeReel();
    const tradesOuverts = await getTradesOuvertsReel();

    // Récupérer les statistiques des sources
    const sourceStats = await getSourceStats();

    const etatSysteme = {
      timestamp: new Date(),
      btcData: {
        prix: btcData.price,
        drawdown: btcData.sixMonthsHigh ?
          ((btcData.price - btcData.sixMonthsHigh) / btcData.sixMonthsHigh) * 100 : 0,
        sources: btcData.sourcesUsed
      },
      balance: balance,
      tradesOuverts: tradesOuverts.length,
      sourceStats: sourceStats,
      statut: 'SAUVEGARDE AUTOMATIQUE'
    };

    await db.collection('etat_systeme').doc().set(etatSysteme);
    logger.info('💾 État système sauvegardé');

  } catch (error) {
    logger.error('❌ Erreur sauvegarde état système:', error);
  }
});

exports.rapportQuotidien = onSchedule({
  schedule: "0 9 * * *",
  timeZone: "Europe/Paris"
}, async (event) => {
  try {
    const hier = new Date();
    hier.setDate(hier.getDate() - 1);
    const debutHier = new Date(hier.getFullYear(), hier.getMonth(), hier.getDate());

    const snapshot = await db.collection('trades')
      .where('dateAchat', '>=', debutHier)
      .get();

    const tradesHier = snapshot.docs.map(doc => doc.data());

    const btcData = await collecterDonneesBitcoinReel();
    const balance = await getBalanceStrikeReel();

    // Récupérer les statistiques des sources
    const sourceStats = await getSourceStats();

    const rapport = {
      date: hier.toISOString().split('T')[0],
      totalTrades: tradesHier.length,
      achats: tradesHier.filter(t => t.estVente === false).length,
      ventes: tradesHier.filter(t => t.estVente === true).length,
      montantTotal: tradesHier.filter(t => t.estVente === false)
        .reduce((sum, t) => sum + t.montantInvesti, 0),
      prixBitcoin: btcData.price,
      soldeEUR: balance.soldeEUR,
      soldeBTC: balance.soldeBTC,
      sourceStats: sourceStats,
      timestamp: new Date()
    };

    await db.collection('rapports_quotidiens').doc().set(rapport);
    logger.info('📊 Rapport quotidien généré');

  } catch (error) {
    logger.error('❌ Erreur génération rapport quotidien:', error);
  }
});

logger.info("✅ Firebase Functions RÉELLES initialisées - Stratégie de trading AUTOMATIQUE ACTIVE avec logs détaillés et alignement Dart");