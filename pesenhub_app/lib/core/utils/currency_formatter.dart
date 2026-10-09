import 'package:flutter/services.dart';

/// Utilities for Indonesian Rupiah (IDR) currency formatting, parsing,
/// and thousands-separator text input.
class CurrencyFormatter {
  CurrencyFormatter._();

  /// Formats an integer or number into standard Indonesian Rupiah format.
  /// E.g. `20000` -> `'Rp 20.000'`.
  /// `0` -> `'Rp 0'`.
  /// `-5000` -> `'-Rp 5.000'`.
  /// If [amount] is null, returns `'Rp 0'`.
  static String formatRupiah(num? amount) {
    if (amount == null) return 'Rp 0';
    final isNegative = amount < 0;
    final absAmount = amount.abs().round();
    final formatted = formatThousands(absAmount);
    return isNegative ? '-Rp $formatted' : 'Rp $formatted';
  }

  /// Formats an integer or number with thousand dots separator without currency prefix.
  /// E.g. `20000` -> `'20.000'`.
  /// `0` -> `'0'`.
  /// `-5000` -> `'-5.000'`.
  /// If [amount] is null, returns `'0'`.
  static String formatThousands(num? amount) {
    if (amount == null) return '0';
    final isNegative = amount < 0;
    final digits = amount.abs().round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(digits[i]);
    }
    final result = buffer.toString();
    return isNegative ? '-$result' : result;
  }

  /// Parses a string containing thousand separators (e.g. `'20.000'`, `'20,000'`, `'20000'`) into an `int`.
  /// Returns `null` if the text cannot be parsed or is empty.
  static int? parseThousands(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final isNegative = trimmed.startsWith('-');
    final digits = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;
    final value = int.tryParse(digits);
    if (value == null) return null;
    return isNegative ? -value : value;
  }

  /// Calculates online price from offline price and markup percentage according to Yoga's formula:
  /// `Harga Online = Harga Offline + (Harga Offline × persen / 100)`
  /// Rounded to nearest whole rupiah (integer).
  static int calculateOnlinePrice(int offlinePrice, double markupPercent) {
    if (offlinePrice <= 0) return 0;
    final markup = (offlinePrice * markupPercent / 100.0).round();
    return offlinePrice + markup;
  }

  /// Calculates online price for a specific channel using custom or master generator rate.
  static int calculateChannelPrice(
    int offlinePrice,
    String channel, {
    double? customPercent,
  }) {
    final percent = customPercent ?? ChannelGeneratorConfig.getRate(channel);
    return calculateOnlinePrice(offlinePrice, percent);
  }
}

/// Master data / configuration for online channel markup generator rates.
class ChannelGeneratorConfig {
  ChannelGeneratorConfig._();

  static const List<String> onlineChannels = [
    'GOFOOD',
    'GRABFOOD',
    'SHOPEEFOOD',
  ];

  static const Map<String, String> channelLabels = {
    'OFFLINE': 'Offline/Kasir',
    'GOFOOD': 'GoFood',
    'GRABFOOD': 'GrabFood',
    'SHOPEEFOOD': 'ShopeeFood',
  };

  static final Map<String, double> defaultPercentages = {
    'GOFOOD': 20.0,
    'GRABFOOD': 20.0,
    'SHOPEEFOOD': 20.0,
  };

  static final Map<String, double> _currentPercentages = Map.from(
    defaultPercentages,
  );

  /// Formats rate as integer string if whole number, else string with decimal.
  static String formatRate(double rate) {
    if (rate == rate.roundToDouble()) {
      return rate.toInt().toString();
    }
    return rate.toString();
  }

  /// Returns active markup percentage rate for given channel.
  static double getRate(String channel) {
    return _currentPercentages[channel.toUpperCase()] ?? 20.0;
  }

  /// Sets active markup percentage rate for given channel.
  static void setRate(String channel, double rate) {
    _currentPercentages[channel.toUpperCase()] = rate;
  }

  /// Returns a copy of all channel rates.
  static Map<String, double> getAllRates() {
    return Map.unmodifiable(_currentPercentages);
  }

  /// Resets all channel rates to system defaults.
  static void resetToDefaults() {
    _currentPercentages
      ..clear()
      ..addAll(defaultPercentages);
  }
}

/// A [TextInputFormatter] that automatically formats numeric input with thousands separators (dots)
/// as the user types, pastes, or deletes numbers.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    var textToFormat = newValue.text;
    var selectionIndex = newValue.selection.end;

    // If backspacing directly over a dot, remove the preceding digit as well
    if (oldValue.text.length > newValue.text.length) {
      final deletedIndex = newValue.selection.end;
      if (deletedIndex < oldValue.text.length &&
          oldValue.text[deletedIndex] == '.') {
        final beforeDot = oldValue.text.substring(0, deletedIndex);
        final afterDot = oldValue.text.substring(deletedIndex + 1);
        if (beforeDot.isNotEmpty) {
          textToFormat =
              beforeDot.substring(0, beforeDot.length - 1) + afterDot;
          selectionIndex = (deletedIndex - 1).clamp(0, textToFormat.length);
        }
      }
    }

    final cleanDigits = textToFormat.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanDigits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Parse to BigInt to normalize leading zeros (e.g. "05" -> "5", but "0" -> "0")
    final parsedInt = BigInt.tryParse(cleanDigits);
    final rawDigits = (parsedInt != null) ? parsedInt.toString() : cleanDigits;

    var digitsBeforeCursor = 0;
    final safeSelectionIndex = selectionIndex.clamp(0, textToFormat.length);
    for (var i = 0; i < safeSelectionIndex; i++) {
      if (RegExp(r'\d').hasMatch(textToFormat[i])) {
        digitsBeforeCursor++;
      }
    }

    final trimmedZerosCount = cleanDigits.length - rawDigits.length;
    digitsBeforeCursor = (digitsBeforeCursor - trimmedZerosCount).clamp(
      0,
      rawDigits.length,
    );

    final buffer = StringBuffer();
    for (var i = 0; i < rawDigits.length; i++) {
      if (i > 0 && (rawDigits.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(rawDigits[i]);
    }
    final formattedText = buffer.toString();

    var newCursor = 0;
    var countedDigits = 0;
    for (var i = 0; i < formattedText.length; i++) {
      if (countedDigits >= digitsBeforeCursor) {
        break;
      }
      if (RegExp(r'\d').hasMatch(formattedText[i])) {
        countedDigits++;
      }
      newCursor = i + 1;
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }
}
