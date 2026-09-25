import 'package:flutter/material.dart';

import 'habits.dart' show dateOnly, dayKey;

/// Whether an entry adds to or subtracts from the balance.
enum EntryType {
  income,
  expense;

  bool get isExpense => this == EntryType.expense;

  static EntryType byName(String? name) =>
      values.firstWhere((type) => type.name == name, orElse: () => expense);
}

/// A spending or earning category, with the icon and colour it shows as.
///
/// A fixed list rather than user-editable categories: enough to see where the
/// money goes without a settings screen for the categories themselves.
class ExpenseCategory {
  const ExpenseCategory(this.name, this.icon, this.color);

  final String name;
  final IconData icon;
  final Color color;

  /// The catch-all category, present in both lists. An entry filed here can
  /// carry a free-text [ExpenseEntry.detail] saying what it really was.
  static const otherName = 'Other';

  /// Money put into investments. Filed as an expense, since it leaves the
  /// spendable balance, but gathered on its own under Manage so it can be
  /// seen apart from day-to-day spending.
  static const investmentName = 'Investment';

  static const expense = [
    ExpenseCategory('Food', Icons.restaurant_rounded, Color(0xFFFF8A65)),
    ExpenseCategory(
      'Transport',
      Icons.directions_car_rounded,
      Color(0xFF4FC3F7),
    ),
    ExpenseCategory('Shopping', Icons.shopping_bag_rounded, Color(0xFFBA68C8)),
    ExpenseCategory('Fun', Icons.movie_rounded, Color(0xFFF06292)),
    ExpenseCategory('Bills', Icons.receipt_long_rounded, Color(0xFFFFB74D)),
    ExpenseCategory('Health', Icons.favorite_rounded, Color(0xFFE57373)),
    ExpenseCategory('Learning', Icons.school_rounded, Color(0xFF7986CB)),
    ExpenseCategory('Investment', Icons.trending_up_rounded, Color(0xFF66BB6A)),
    ExpenseCategory('Other', Icons.category_rounded, Color(0xFF90A4AE)),
  ];

  static const income = [
    ExpenseCategory('Salary', Icons.payments_rounded, Color(0xFF4DB6AC)),
    ExpenseCategory('Freelance', Icons.work_rounded, Color(0xFF4DD0E1)),
    ExpenseCategory('Investment', Icons.trending_up_rounded, Color(0xFF81C784)),
    ExpenseCategory('Gift', Icons.card_giftcard_rounded, Color(0xFFF06292)),
    ExpenseCategory('Refund', Icons.replay_rounded, Color(0xFF9575CD)),
    ExpenseCategory('Other', Icons.category_rounded, Color(0xFF90A4AE)),
  ];

  static List<ExpenseCategory> forType(EntryType type) =>
      type.isExpense ? expense : income;

  /// Looks a category up by name within [type], falling back to Other so an
  /// unknown or renamed category still renders.
  static ExpenseCategory resolve(EntryType type, String name) {
    final list = forType(type);
    for (final category in list) {
      if (category.name == name) return category;
    }
    return list.last;
  }
}

/// A single income or expense record.
@immutable
class ExpenseEntry {
  const ExpenseEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.createdAt,
    this.detail = '',
  });

  static const maxTitleLength = 80;

  /// A ceiling so a fat-fingered amount cannot produce nonsense totals.
  static const double maxAmount = 1000000000;

  final String id;
  final EntryType type;
  final String title;

  /// Always positive; [type] decides the sign in totals and on screen.
  final double amount;
  final String category;

  /// What an Other entry actually was ("Pet food"). Shown in place of the bare
  /// "Other", but the entry still counts under Other in every total. Empty for
  /// the fixed categories.
  final String detail;

  /// The day the money moved.
  final DateTime date;
  final DateTime createdAt;

  /// The custom [detail] for an Other entry that has one, otherwise the
  /// category itself.
  String get displayCategory =>
      category == ExpenseCategory.otherName && detail.trim().isNotEmpty
      ? detail.trim()
      : category;

  /// The heading on a row: the note, or the category when there is none.
  String get heading => title.isEmpty ? displayCategory : title;

  ExpenseEntry copyWith({
    EntryType? type,
    String? title,
    double? amount,
    String? category,
    String? detail,
    DateTime? date,
  }) => ExpenseEntry(
    id: id,
    type: type ?? this.type,
    title: title ?? this.title,
    amount: amount ?? this.amount,
    category: category ?? this.category,
    detail: detail ?? this.detail,
    date: date ?? this.date,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'amount': amount,
    'category': category,
    if (detail.isNotEmpty) 'detail': detail,
    'date': date.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  static ExpenseEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final amount = raw['amount'];
    if (id is! String || id.isEmpty || amount is! num) return null;

    DateTime parse(Object? value) =>
        (value is String ? DateTime.tryParse(value) : null) ?? DateTime.now();

    final created = parse(raw['createdAt']);
    final type = EntryType.byName(raw['type'] as String?);
    return ExpenseEntry(
      id: id,
      type: type,
      title: raw['title'] is String ? (raw['title'] as String).trim() : '',
      amount: amount.toDouble().abs().clamp(0, maxAmount).toDouble(),
      category: raw['category'] is String
          ? raw['category'] as String
          : ExpenseCategory.forType(type).last.name,
      detail: raw['detail'] is String ? (raw['detail'] as String).trim() : '',
      date: dateOnly(raw['date'] is String ? parse(raw['date']) : created),
      createdAt: created,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExpenseEntry &&
      other.id == id &&
      other.type == type &&
      other.title == title &&
      other.amount == amount &&
      other.category == category &&
      other.detail == detail &&
      other.date == date;

  @override
  int get hashCode =>
      Object.hash(id, type, title, amount, category, detail, date);
}

/// A spending limit over any date range, a trip or a fortnight as much as a
/// month. An empty [category] means all spending.
@immutable
class Budget {
  const Budget({
    required this.id,
    required this.label,
    required this.amount,
    required this.start,
    required this.end,
    this.category = '',
  });

  static const maxLabelLength = 60;

  final String id;
  final String label;
  final double amount;

  /// Inclusive, date-only.
  final DateTime start;
  final DateTime end;

  final String category;

  bool get allCategories => category.trim().isEmpty;

  /// The label, or failing that the category, or failing that "Budget".
  String get title =>
      label.isNotEmpty ? label : (allCategories ? 'Budget' : category);

  bool covers(DateTime day) {
    final date = dateOnly(day);
    return !date.isBefore(dateOnly(start)) && !date.isAfter(dateOnly(end));
  }

  Budget copyWith({
    String? label,
    double? amount,
    DateTime? start,
    DateTime? end,
    String? category,
  }) => Budget(
    id: id,
    label: label ?? this.label,
    amount: amount ?? this.amount,
    start: start ?? this.start,
    end: end ?? this.end,
    category: category ?? this.category,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'amount': amount,
    'start': dateOnly(start).toIso8601String(),
    'end': dateOnly(end).toIso8601String(),
    if (category.isNotEmpty) 'category': category,
  };

  static Budget? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final amount = raw['amount'];
    if (id is! String || id.isEmpty || amount is! num) return null;
    DateTime parse(Object? value) => dateOnly(
      (value is String ? DateTime.tryParse(value) : null) ?? DateTime.now(),
    );
    return Budget(
      id: id,
      label: raw['label'] is String ? (raw['label'] as String).trim() : '',
      amount: amount.toDouble().abs(),
      start: parse(raw['start']),
      end: parse(raw['end']),
      category: raw['category'] is String ? raw['category'] as String : '',
    );
  }
}

/// Which way the money went for a [LoanEntry].
enum LoanType {
  /// You gave money to someone; they owe you.
  lent,

  /// You took money from someone; you owe them.
  borrowed;

  static LoanType byName(String? name) =>
      values.firstWhere((type) => type.name == name, orElse: () => lent);
}

/// Money lent or borrowed: who, how much, which way, and whether it is
/// settled.
@immutable
class LoanEntry {
  const LoanEntry({
    required this.id,
    required this.type,
    required this.person,
    required this.amount,
    required this.date,
    this.note = '',
    this.settled = false,
    this.settledAt,
  });

  static const maxNameLength = 60;

  final String id;
  final LoanType type;
  final String person;
  final double amount;
  final DateTime date;
  final String note;
  final bool settled;
  final DateTime? settledAt;

  LoanEntry copyWith({
    LoanType? type,
    String? person,
    double? amount,
    DateTime? date,
    String? note,
    bool? settled,
    DateTime? settledAt,
    bool clearSettledAt = false,
  }) => LoanEntry(
    id: id,
    type: type ?? this.type,
    person: person ?? this.person,
    amount: amount ?? this.amount,
    date: date ?? this.date,
    note: note ?? this.note,
    settled: settled ?? this.settled,
    settledAt: clearSettledAt ? null : (settledAt ?? this.settledAt),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'person': person,
    'amount': amount,
    'date': date.toIso8601String(),
    if (note.isNotEmpty) 'note': note,
    'settled': settled,
    if (settledAt != null) 'settledAt': settledAt!.toIso8601String(),
  };

  static LoanEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final amount = raw['amount'];
    if (id is! String || id.isEmpty || amount is! num) return null;
    DateTime parse(Object? value) =>
        (value is String ? DateTime.tryParse(value) : null) ?? DateTime.now();
    return LoanEntry(
      id: id,
      type: LoanType.byName(raw['type'] as String?),
      person: raw['person'] is String ? (raw['person'] as String).trim() : '',
      amount: amount.toDouble().abs(),
      date: dateOnly(parse(raw['date'])),
      note: raw['note'] is String ? (raw['note'] as String).trim() : '',
      settled: raw['settled'] == true,
      settledAt: raw['settledAt'] is String
          ? DateTime.tryParse(raw['settledAt'] as String)
          : null,
    );
  }
}

/// A currency amounts can be shown in.
class Currency {
  const Currency(this.code, this.symbol);

  final String code;
  final String symbol;

  /// The common cases rather than every ISO code.
  static const all = [
    Currency('USD', r'$'),
    Currency('INR', '₹'),
    Currency('EUR', '€'),
    Currency('GBP', '£'),
    Currency('JPY', '¥'),
    Currency('CNY', 'CN¥'),
    Currency('AUD', r'A$'),
    Currency('CAD', r'C$'),
    Currency('CHF', 'CHF'),
    Currency('SGD', r'S$'),
    Currency('HKD', r'HK$'),
    Currency('NZD', r'NZ$'),
    Currency('AED', 'د.إ'),
    Currency('SAR', '﷼'),
    Currency('QAR', 'ر.ق'),
    Currency('KWD', 'د.ك'),
    Currency('PKR', '₨'),
    Currency('BDT', '৳'),
    Currency('LKR', 'Rs'),
    Currency('NPR', 'रु'),
    Currency('MYR', 'RM'),
    Currency('IDR', 'Rp'),
    Currency('THB', '฿'),
    Currency('PHP', '₱'),
    Currency('VND', '₫'),
    Currency('KRW', '₩'),
    Currency('TWD', r'NT$'),
    Currency('RUB', '₽'),
    Currency('TRY', '₺'),
    Currency('ZAR', 'R'),
    Currency('NGN', '₦'),
    Currency('EGP', 'E£'),
    Currency('BRL', r'R$'),
    Currency('MXN', r'Mex$'),
    Currency('ARS', r'$'),
    Currency('CLP', r'$'),
    Currency('COP', r'$'),
    Currency('SEK', 'kr'),
    Currency('NOK', 'kr'),
    Currency('DKK', 'kr'),
    Currency('PLN', 'zł'),
    Currency('CZK', 'Kč'),
    Currency('HUF', 'Ft'),
    Currency('ILS', '₪'),
  ];

  static Currency byCode(String? code) => all.firstWhere(
    (currency) => currency.code == code,
    orElse: () => all.first,
  );

  /// [amount] with the symbol and thousands separators: `₹1,250`, `$3.50`.
  /// Whole amounts read cleaner without ".00"; fractional ones keep two
  /// places. Always unsigned: callers add the sign they mean.
  String format(double amount) {
    final value = amount.abs();
    final fractional = (value - value.truncateToDouble()).abs() > 0.005;
    final parts = value.toStringAsFixed(fractional ? 2 : 0).split('.');
    parts[0] = _withThousands(parts[0]);
    return '$symbol${parts.join('.')}';
  }

  /// [format] with a minus sign in front of a negative amount.
  String formatSigned(double amount) =>
      '${amount < 0 ? '-' : ''}${format(amount)}';

  static String _withThousands(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// An amount as typed into a field: `1250` or `12.50`, never `12.5000`.
String amountText(double value) =>
    (value - value.truncateToDouble()).abs() < 0.005
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

/// Reads a typed amount, tolerating thousands separators. Null unless it is a
/// positive number.
double? parseAmount(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', ''));
  if (value == null || value <= 0 || !value.isFinite) return null;
  return value;
}

/// Every question the Money page asks of the ledger, answered from one
/// snapshot of it.
///
/// Built once per change by the store rather than per question: the daily
/// heatmap alone asks about a year of days, and scanning every entry for each
/// one would be thousands of passes.
class MoneyBook {
  MoneyBook({
    required List<ExpenseEntry> entries,
    required List<Budget> budgets,
    required List<LoanEntry> loans,
    required this.currency,
  }) : entries = List.unmodifiable(
         [...entries]..sort((a, b) {
           final byDate = b.date.compareTo(a.date);
           return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
         }),
       ),
       budgets = List.unmodifiable(
         [...budgets]..sort((a, b) => a.end.compareTo(b.end)),
       ),
       loans = List.unmodifiable(
         [...loans]..sort((a, b) {
           if (a.settled != b.settled) return a.settled ? 1 : -1;
           return b.date.compareTo(a.date);
         }),
       ) {
    for (final entry in this.entries) {
      final day = dayKey(entry.date);
      final byDay = entry.type.isExpense ? _spentByDay : _earnedByDay;
      byDay[day] = (byDay[day] ?? 0) + entry.amount;
    }
  }

  /// Newest day first; the same day newest entry first.
  final List<ExpenseEntry> entries;

  /// Soonest ending first.
  final List<Budget> budgets;

  /// Unsettled first, then most recent.
  final List<LoanEntry> loans;

  final Currency currency;

  final Map<int, double> _spentByDay = {};
  final Map<int, double> _earnedByDay = {};

  bool get isEmpty => entries.isEmpty;

  String format(double amount) => currency.format(amount);

  String formatSigned(double amount) => currency.formatSigned(amount);

  ExpenseEntry? byId(String id) =>
      entries.where((entry) => entry.id == id).firstOrNull;

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  /// Entries in [month], newest first.
  List<ExpenseEntry> entriesIn(DateTime month) =>
      entries.where((entry) => _sameMonth(entry.date, month)).toList();

  /// Entries on [day], newest first: what a heatmap day lists.
  List<ExpenseEntry> entriesOn(DateTime day) {
    final key = dayKey(day);
    return entries.where((entry) => dayKey(entry.date) == key).toList();
  }

  /// Spent on [day]: what the heatmap shades a cell by.
  double expenseOn(DateTime day) => _spentByDay[dayKey(day)] ?? 0;

  /// Earned on [day]: the heatmap frames these days.
  double incomeOn(DateTime day) => _earnedByDay[dayKey(day)] ?? 0;

  /// The most spent in any one day, which scales the heatmap so its shades
  /// mean something whatever the currency or spending level.
  double get busiestDaySpend => _spentByDay.values.fold(
    0.0,
    (best, value) => value > best ? value : best,
  );

  double incomeIn(DateTime month) => _sum(month, EntryType.income);
  double expenseIn(DateTime month) => _sum(month, EntryType.expense);
  double balanceIn(DateTime month) => incomeIn(month) - expenseIn(month);

  double _sum(DateTime month, EntryType type) => entries
      .where((entry) => entry.type == type && _sameMonth(entry.date, month))
      .fold(0.0, (total, entry) => total + entry.amount);

  /// The running balance of everything dated before [month], so each month
  /// opens where the last one closed rather than at zero.
  double broughtForwardTo(DateTime month) {
    final start = DateTime(month.year, month.month);
    var balance = 0.0;
    for (final entry in entries) {
      if (entry.date.isBefore(start)) {
        balance += entry.type.isExpense ? -entry.amount : entry.amount;
      }
    }
    return balance;
  }

  /// What was carried in, plus the month's own net.
  double closingBalanceIn(DateTime month) =>
      broughtForwardTo(month) + balanceIn(month);

  bool _isInvestment(ExpenseEntry entry) =>
      entry.category == ExpenseCategory.investmentName;

  /// Money put into investments, newest first.
  List<ExpenseEntry> get investments => entries
      .where((entry) => entry.type.isExpense && _isInvestment(entry))
      .toList();

  double get totalInvested =>
      investments.fold(0.0, (total, entry) => total + entry.amount);

  /// Income filed under Investment: what came back out.
  double get investmentReturns => entries
      .where((entry) => !entry.type.isExpense && _isInvestment(entry))
      .fold(0.0, (total, entry) => total + entry.amount);

  /// Spending per category in [month], largest first.
  List<MapEntry<String, double>> expenseByCategory(DateTime month) =>
      _byCategory(month, EntryType.expense);

  /// Earnings per category in [month], largest first.
  List<MapEntry<String, double>> incomeByCategory(DateTime month) =>
      _byCategory(month, EntryType.income);

  List<MapEntry<String, double>> _byCategory(DateTime month, EntryType type) {
    final totals = <String, double>{};
    for (final entry in entries) {
      if (entry.type != type || !_sameMonth(entry.date, month)) continue;
      totals[entry.category] = (totals[entry.category] ?? 0) + entry.amount;
    }
    return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Spending inside [budget]'s dates, and its category when it has one.
  double spentFor(Budget budget) => entries
      .where(
        (entry) =>
            entry.type.isExpense &&
            budget.covers(entry.date) &&
            (budget.allCategories || entry.category == budget.category),
      )
      .fold(0.0, (total, entry) => total + entry.amount);

  /// Still owed to you: unsettled money lent.
  double get owedToYou => loans
      .where((loan) => !loan.settled && loan.type == LoanType.lent)
      .fold(0.0, (total, loan) => total + loan.amount);

  /// Still owed by you: unsettled money borrowed.
  double get youOwe => loans
      .where((loan) => !loan.settled && loan.type == LoanType.borrowed)
      .fold(0.0, (total, loan) => total + loan.amount);
}
