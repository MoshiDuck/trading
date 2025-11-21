// lib/utils/safe_convert.dart

/// Fournit des méthodes pour convertir de manière sûre des valeurs dynamiques en int ou double.
class SafeConvert {
  /// Convertit une valeur dynamique en double.
  /// Renvoie 0.0 si la conversion échoue ou si la valeur est nulle.
  static double toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value);
      } catch (e) {
        return 0.0;
      }
    }
    return 0.0;
  }

  /// Convertit une valeur dynamique en int.
  /// Renvoie 0 si la conversion échoue ou si la valeur est nulle.
  static int toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      try {
        return int.parse(value);
      } catch (e) {
        return 0;
      }
    }
    return 0;
  }
}
