import 'package:flutter/material.dart';

import '../data/money.dart';
import '../main.dart';
import '../state/control_store.dart';
import 'control_page.dart';
import 'controls.dart';
import 'money_charts.dart';
import 'money_sheets.dart';
import 'theme.dart';
import 'widgets.dart';

enum _MoneyView {
  overview('Overview'),
  stats('Stats'),
  manage('Manage');

  const _MoneyView(this.label);

  final String label;
}

/// Money: a month-by-month income and expense log, what it adds up to, and
/// the longer-lived things around it, budgets, investments and loans.
///
/// Every month opens with the balance the last one closed on, so the log
/// reads as one running account rather than twelve that each start at zero.
class MoneyPage extends StatefulWidget {
  const MoneyPage({super.key});

  @override
  State<MoneyPage> createState() => _MoneyPageState();
}

class _MoneyPageState extends State<MoneyPage> {
  _MoneyView _view = _MoneyView.overview;

  /// The month being looked at, or null to follow the current one.
  DateTime? _month;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final now = store.wallNow();
    final thisMonth = DateTime(now.year, now.month);
    final month = _month ?? thisMonth;
    // Nothing to show in the future.
    final canGoNext = month.isBefore(thisMonth);

    void shift(int delta) {
      final next = DateTime(month.year, month.month + delta);
      setState(() => _month = next == thisMonth ? null : next);
    }

    return ControlPage(
      title: 'Where it goes',
      eyebrow: 'Money',
      subtitle: 'Income and spending, month by month.',
      children: [
        _MonthBar(
          month: month,
          onPrevious: () => shift(-1),
          onNext: canGoNext ? () => shift(1) : null,
        ),
        const SizedBox(height: 12),
        ControlSegmented<_MoneyView>(
          expand: true,
          options: [for (final view in _MoneyView.values) (view, view.label)],
          value: _view,
          onChanged: (view) => setState(() => _view = view),
        ),
        const SizedBox(height: 20),
        ...switch (_view) {
          _MoneyView.overview => _overview(context, store, month),
          _MoneyView.stats => _stats(context, store, month),
          _MoneyView.manage => _manage(context, store),
        },
      ],
    );
  }

  List<Widget> _overview(
    BuildContext context,
    ControlStore store,
    DateTime month,
  ) {
    final book = store.moneyBook;
    final entries = book.entriesIn(month);
    // Last month's totals open this one as "brought forward" rows, so a fresh
    // month still starts from where the last left off.
    final previous = DateTime(month.year, month.month - 1);
    final carriedSpend = book.expenseIn(previous);
    final carriedIncome = book.incomeIn(previous);

    if (entries.isEmpty && carriedSpend <= 0 && carriedIncome <= 0) {
      return const [
        _MoneyEmpty(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Nothing tracked yet',
          body: 'Tap New entry to log income or an expense.',
        ),
      ];
    }

    return [
      _SummaryCard(book: book, month: month),
      const SizedBox(height: 24),
      const SectionLabel('This month'),
      _MonthColumns(
        book: book,
        entries: entries,
        today: store.wallNow(),
        carriedSpend: carriedSpend,
        carriedIncome: carriedIncome,
      ),
    ];
  }

  List<Widget> _stats(
    BuildContext context,
    ControlStore store,
    DateTime month,
  ) {
    final book = store.moneyBook;
    if (book.isEmpty) {
      return const [
        _MoneyEmpty(
          icon: Icons.insights_rounded,
          title: 'No stats yet',
          body: 'Log a few entries to see trends.',
        ),
      ];
    }

    final tones = MoneyTones.of(context);
    final income = book.incomeIn(month);
    final spent = book.expenseIn(month);
    final saved = income - spent;

    return [
      Row(
        children: [
          Expanded(
            child: _StatBox(
              label: 'Saved this month',
              value: book.formatSigned(saved),
              color: saved < 0 ? tones.expense : tones.income,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatBox(
              label: 'Savings rate',
              value: income > 0 ? '${(saved / income * 100).round()}%' : '–',
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const SectionLabel('Income vs expense'),
      LayoutBuilder(
        builder: (context, constraints) {
          final expense = _DonutCard(
            title: 'Expense',
            type: EntryType.expense,
            totals: book.expenseByCategory(month),
            total: spent,
            accent: tones.expense,
            book: book,
          );
          final earned = _DonutCard(
            title: 'Income',
            type: EntryType.income,
            totals: book.incomeByCategory(month),
            total: income,
            accent: tones.income,
            book: book,
          );
          // Side by side while each still fits its ring, stacked after.
          if (constraints.maxWidth < 340) {
            return Column(
              children: [expense, const SizedBox(height: 12), earned],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: expense),
                const SizedBox(width: 12),
                Expanded(child: earned),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 24),
      const SectionLabel('Daily spending'),
      ControlCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: MoneyHeatmap(
          book: book,
          today: store.wallNow(),
          spendColor: tones.expense,
          incomeColor: tones.income,
          onSelect: (day) => MoneyDaySheet.show(context, day),
        ),
      ),
      const SizedBox(height: 24),
      const SectionLabel('Where it went this month'),
      _CategoryBreakdown(book: book, month: month),
    ];
  }

  List<Widget> _manage(BuildContext context, ControlStore store) {
    final book = store.moneyBook;
    final tones = MoneyTones.of(context);
    final today = store.wallNow();

    return [
      const SectionLabel('Investments'),
      _Investments(book: book, today: today),
      const SizedBox(height: 24),
      _SectionHeader(
        'Budgets',
        action: 'Budget',
        onPressed: () => BudgetSheet.show(context),
      ),
      if (book.budgets.isEmpty)
        const _Hint(
          icon: Icons.pie_chart_outline_rounded,
          text:
              'Set a budget for any stretch of days: a week, a trip, a month.',
        )
      else
        for (final budget in book.budgets)
          _BudgetCard(budget: budget, book: book),
      const SizedBox(height: 24),
      _SectionHeader(
        'Lend / Loan',
        action: 'Record',
        onPressed: () => LoanSheet.show(context),
      ),
      Row(
        children: [
          Expanded(
            child: _LoanTotal(
              label: 'Owed to you',
              amount: book.format(book.owedToYou),
              color: tones.income,
              icon: Icons.south_west_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _LoanTotal(
              label: 'You owe',
              amount: book.format(book.youOwe),
              color: tones.expense,
              icon: Icons.north_east_rounded,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (book.loans.isEmpty)
        const _Hint(
          icon: Icons.handshake_outlined,
          text: 'Track money you lent out or borrowed, and settle it later.',
        )
      else
        for (final loan in book.loans)
          _LoanTile(loan: loan, book: book, today: today),
    ];
  }
}

/// ‹ › September 2026, and the currency on the right.
class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;

  /// Null at the current month, which disables the arrow.
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'Previous month',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton.filledTonal(
          tooltip: 'Next month',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            MaterialLocalizations.of(context).formatMonthYear(month),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(width: 8),
        const _CurrencyButton(),
      ],
    );
  }
}

class _CurrencyButton extends StatelessWidget {
  const _CurrencyButton();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = store.currency;

    return PopupMenuButton<Currency>(
      tooltip: 'Currency',
      position: PopupMenuPosition.under,
      initialValue: selected,
      constraints: const BoxConstraints(minWidth: 160, maxHeight: 420),
      onSelected: store.setCurrency,
      itemBuilder: (context) => [
        for (final currency in Currency.all)
          PopupMenuItem(
            value: currency,
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    currency.symbol,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
                Expanded(child: Text(currency.code)),
                if (currency.code == selected.code)
                  Icon(Icons.check_rounded, size: 18, color: scheme.primary),
              ],
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: Shapes.chip,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${selected.symbol}  ${selected.code}',
              style: theme.textTheme.labelLarge,
            ),
            Icon(Icons.arrow_drop_down_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// Overview ------------------------------------------------------------------

/// The month's balance, what it opened and closed on, and income against
/// spending.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.book, required this.month});

  final MoneyBook book;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = MoneyTones.of(context);
    final on = scheme.onPrimaryContainer;
    final muted = on.withValues(alpha: 0.72);
    final income = book.incomeIn(month);
    final spent = book.expenseIn(month);
    final balance = income - spent;
    final carried = book.broughtForwardTo(month);
    final closing = carried + balance;
    final monthName = MaterialLocalizations.of(
      context,
    ).formatMonthYear(month).split(' ').first;
    final figures = const [FontFeature.tabularFigures()];

    return HeroCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 22,
                  color: on,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Balance · $monthName',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        book.formatSigned(balance),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: balance < 0 ? tones.expense : on,
                          fontFeatures: figures,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Pill(
                balance >= 0 ? 'Surplus' : 'Deficit',
                color: balance >= 0 ? tones.income : tones.expense,
                background: scheme.surface.withValues(alpha: 0.6),
              ),
            ],
          ),
          if (carried.abs() > 0.005) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Text.rich(
                    TextSpan(
                      text: 'Brought forward  ',
                      children: [
                        TextSpan(
                          text: book.formatSigned(carried),
                          style: TextStyle(
                            color: carried < 0 ? tones.expense : on,
                            fontWeight: FontWeight.w700,
                            fontFeatures: figures,
                          ),
                        ),
                      ],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  Text.rich(
                    TextSpan(
                      text: 'Closing  ',
                      children: [
                        TextSpan(
                          text: book.formatSigned(closing),
                          style: TextStyle(
                            color: closing < 0 ? tones.expense : tones.income,
                            fontWeight: FontWeight.w700,
                            fontFeatures: figures,
                          ),
                        ),
                      ],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _SplitBar(
            income: income,
            expense: spent,
            incomeColor: tones.income,
            expenseColor: tones.expense,
            track: scheme.surface.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Tally(
                  label: 'Income',
                  amount: book.format(income),
                  color: tones.income,
                  icon: Icons.south_west_rounded,
                  textColor: on,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Tally(
                  label: 'Expenses',
                  amount: book.format(spent),
                  color: tones.expense,
                  icon: Icons.north_east_rounded,
                  textColor: on,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Income against spending, in proportion. A plain track when nothing has
/// moved yet.
class _SplitBar extends StatelessWidget {
  const _SplitBar({
    required this.income,
    required this.expense,
    required this.incomeColor,
    required this.expenseColor,
    required this.track,
  });

  final double income;
  final double expense;
  final Color incomeColor;
  final Color expenseColor;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final total = income + expense;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        width: double.infinity,
        child: total <= 0
            ? ColoredBox(color: track)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: (income / total * 1000).round(),
                    child: ColoredBox(color: incomeColor),
                  ),
                  if (income > 0 && expense > 0) const SizedBox(width: 3),
                  Expanded(
                    flex: (expense / total * 1000).round(),
                    child: ColoredBox(color: expenseColor),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
    this.textColor,
  });

  final String label;
  final String amount;
  final Color color;
  final IconData icon;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = textColor ?? theme.colorScheme.onSurface;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: text.withValues(alpha: 0.72),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  amount,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: text,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The month's entries split into expenses and income: side by side when
/// there is room, one above the other on a phone.
class _MonthColumns extends StatelessWidget {
  const _MonthColumns({
    required this.book,
    required this.entries,
    required this.today,
    required this.carriedSpend,
    required this.carriedIncome,
  });

  final MoneyBook book;
  final List<ExpenseEntry> entries;
  final DateTime today;
  final double carriedSpend;
  final double carriedIncome;

  @override
  Widget build(BuildContext context) {
    final tones = MoneyTones.of(context);
    final spending = _EntryColumn(
      label: 'Expenses',
      color: tones.expense,
      entries: [
        for (final e in entries)
          if (e.type.isExpense) e,
      ],
      carried: carriedSpend,
      book: book,
      today: today,
    );
    final earning = _EntryColumn(
      label: 'Income',
      color: tones.income,
      entries: [
        for (final e in entries)
          if (!e.type.isExpense) e,
      ],
      carried: carriedIncome,
      book: book,
      today: today,
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 640
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: spending),
                const SizedBox(width: 16),
                Expanded(child: earning),
              ],
            )
          : Column(children: [spending, const SizedBox(height: 20), earning]),
    );
  }
}

class _EntryColumn extends StatelessWidget {
  const _EntryColumn({
    required this.label,
    required this.color,
    required this.entries,
    required this.carried,
    required this.book,
    required this.today,
  });

  final String label;
  final Color color;
  final List<ExpenseEntry> entries;

  /// Last month's total for this column, opening it as a brought-forward row.
  final double carried;
  final MoneyBook book;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.titleSmall),
              const SizedBox(width: 6),
              Text(
                '${entries.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (carried > 0.005)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 20, color: colors.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Brought forward',
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        'Last month',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  book.format(carried),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        if (entries.isEmpty && carried <= 0.005)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'None yet',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textMuted,
              ),
            ),
          )
        else
          for (final entry in entries)
            MoneyEntryTile(entry: entry, book: book, today: today),
      ],
    );
  }
}

/// One income or expense: tap to edit, or the menu to edit or delete.
class MoneyEntryTile extends StatelessWidget {
  const MoneyEntryTile({
    required this.entry,
    required this.book,
    required this.today,
    super.key,
  });

  final ExpenseEntry entry;
  final MoneyBook book;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final store = StoreScope.of(context);
    final category = ExpenseCategory.resolve(entry.type, entry.category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => EntryEditorSheet.show(context, existing: entry),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
            child: Row(
              children: [
                CategoryTile(category: category),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.heading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${entry.displayCategory} · '
                        '${moneyDayLabel(context, entry.date, today)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.type.isExpense ? '-' : '+'}'
                  '${book.format(entry.amount)}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: MoneyTones.of(context).of(entry.type),
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                _RowMenu(
                  actions: [
                    (
                      Icons.edit_outlined,
                      'Edit',
                      () => EntryEditorSheet.show(context, existing: entry),
                    ),
                    (
                      Icons.delete_outline_rounded,
                      'Delete',
                      () => removeWithUndo(
                        context,
                        message: 'Entry deleted',
                        remove: () => store.removeMoneyEntry(entry.id),
                        restore: () => store.restoreMoneyEntry(entry),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The three-dot menu on a row.
class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.actions});

  final List<(IconData, String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: 'More',
    icon: const Icon(Icons.more_vert_rounded),
    position: PopupMenuPosition.under,
    onSelected: (index) => actions[index].$3(),
    itemBuilder: (context) => [
      for (final (index, (icon, label, _)) in actions.indexed)
        PopupMenuItem(
          value: index,
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: label == 'Delete'
                    ? ControlColors.of(context).heavy
                    : null,
              ),
              const SizedBox(width: 12),
              Text(label),
            ],
          ),
        ),
    ],
  );
}

// Stats ---------------------------------------------------------------------

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ControlCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ControlColors.of(context).textMuted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One side's categories as a ring, the month's total inside it, and the
/// biggest four beneath.
class _DonutCard extends StatelessWidget {
  const _DonutCard({
    required this.title,
    required this.type,
    required this.totals,
    required this.total,
    required this.accent,
    required this.book,
  });

  final String title;
  final EntryType type;
  final List<MapEntry<String, double>> totals;
  final double total;
  final Color accent;
  final MoneyBook book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final segments = [
      for (final entry in totals)
        (ExpenseCategory.resolve(type, entry.key), entry.value),
    ];

    return ControlCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: MoneyDonut(
              segments: [for (final (c, v) in segments) (c.color, v)],
              track: theme.colorScheme.surfaceContainerHighest,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      book.format(total),
                      maxLines: 1,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Text(
                    'total',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (segments.isEmpty)
            Text(
              'No ${title.toLowerCase()} this month.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textMuted,
              ),
            )
          else
            for (final (category, value) in segments.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: category.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      book.format(value),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// The month's spending by category, a bar and a share each.
class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.book, required this.month});

  final MoneyBook book;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final totals = book.expenseByCategory(month);
    if (totals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'No expenses this month.',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted),
        ),
      );
    }
    final grand = totals.fold(0.0, (sum, entry) => sum + entry.value);

    return ControlCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          for (final entry in totals)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _CategoryLine(
                category: ExpenseCategory.resolve(EntryType.expense, entry.key),
                amount: book.format(entry.value),
                share: grand > 0 ? entry.value / grand : 0,
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryLine extends StatelessWidget {
  const _CategoryLine({
    required this.category,
    required this.amount,
    required this.share,
  });

  final ExpenseCategory category;
  final String amount;
  final double share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    return Row(
      children: [
        CategoryTile(category: category),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    amount,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _Bar(
                      fraction: share,
                      color: category.color,
                      track: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(share * 100).round()}%',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(
      height: 8,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: track),
          FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fraction.clamp(0.0, 1.0),
            child: ColoredBox(color: color),
          ),
        ],
      ),
    ),
  );
}

// Manage --------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
    this.text, {
    required this.action,
    required this.onPressed,
  });

  final String text;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                text.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(action),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textMuted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything filed under Investment, gathered in one place with the
/// all-time total and any returns.
class _Investments extends StatelessWidget {
  const _Investments({required this.book, required this.today});

  final MoneyBook book;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final invested = book.totalInvested;
    final returns = book.investmentReturns;
    if (invested <= 0 && returns <= 0) {
      return const _Hint(
        icon: Icons.trending_up_rounded,
        text: 'Log an expense under Investment to track it here.',
      );
    }
    final category = ExpenseCategory.resolve(
      EntryType.expense,
      ExpenseCategory.investmentName,
    );
    final figures = const [FontFeature.tabularFigures()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ControlCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CategoryTile(category: category, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total invested',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        book.format(invested),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontFeatures: figures,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (returns > 0) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Returns',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    Text(
                      book.format(returns),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: MoneyTones.of(context).income,
                        fontWeight: FontWeight.w700,
                        fontFeatures: figures,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in book.investments)
          MoneyEntryTile(entry: entry, book: book, today: today),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.budget, required this.book});

  final Budget budget;
  final MoneyBook book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final store = StoreScope.of(context);
    final localizations = MaterialLocalizations.of(context);
    final spent = book.spentFor(budget);
    final fraction = budget.amount > 0
        ? (spent / budget.amount).clamp(0.0, 1.0)
        : 0.0;
    final over = spent > budget.amount;
    final tones = MoneyTones.of(context);
    final barColor = over || fraction > 0.85 ? tones.expense : tones.income;
    final sameYear = budget.start.year == budget.end.year;
    final range =
        '${localizations.formatShortMonthDay(budget.start)} – '
        '${sameYear ? localizations.formatShortMonthDay(budget.end) : localizations.formatMediumDate(budget.end)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => BudgetSheet.show(context, existing: budget),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 0, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            budget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            budget.allCategories
                                ? range
                                : '$range · ${budget.category}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${book.format(spent)} / ${book.format(budget.amount)}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: over ? tones.expense : null,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    _RowMenu(
                      actions: [
                        (
                          Icons.edit_outlined,
                          'Edit',
                          () => BudgetSheet.show(context, existing: budget),
                        ),
                        (
                          Icons.delete_outline_rounded,
                          'Delete',
                          () => removeWithUndo(
                            context,
                            message: 'Budget deleted',
                            remove: () => store.removeBudget(budget.id),
                            restore: () => store.restoreBudget(budget),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _Bar(
                    fraction: fraction,
                    color: barColor,
                    track: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  over
                      ? 'Over by ${book.format(spent - budget.amount)}'
                      : '${book.format(budget.amount - spent)} left · '
                            '${(fraction * 100).round()}% used',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: over ? tones.expense : colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoanTotal extends StatelessWidget {
  const _LoanTotal({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String label;
  final String amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ControlCard(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: _Tally(label: label, amount: amount, color: color, icon: icon),
  );
}

class _LoanTile extends StatelessWidget {
  const _LoanTile({
    required this.loan,
    required this.book,
    required this.today,
  });

  final LoanEntry loan;
  final MoneyBook book;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final store = StoreScope.of(context);
    final tones = MoneyTones.of(context);
    final lent = loan.type == LoanType.lent;
    final settleLabel = loan.settled ? 'Mark unsettled' : 'Mark settled';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => LoanSheet.show(context, existing: loan),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: settleLabel,
                  onPressed: () => store.toggleLoanSettled(loan.id),
                  icon: Icon(
                    loan.settled
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: loan.settled
                        ? theme.colorScheme.primary
                        : colors.textMuted,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loan.person.isEmpty ? 'Someone' : loan.person,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: loan.settled ? colors.textMuted : null,
                          decoration: loan.settled
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: colors.textMuted,
                        ),
                      ),
                      Text(
                        [
                          lent ? 'Lent' : 'Borrowed',
                          moneyDayLabel(context, loan.date, today),
                          if (loan.note.isNotEmpty) loan.note,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${lent ? '+' : '-'}${book.format(loan.amount)}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: loan.settled
                        ? colors.textMuted
                        : (lent ? tones.income : tones.expense),
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                _RowMenu(
                  actions: [
                    (
                      Icons.check_rounded,
                      settleLabel,
                      () => store.toggleLoanSettled(loan.id),
                    ),
                    (
                      Icons.edit_outlined,
                      'Edit',
                      () => LoanSheet.show(context, existing: loan),
                    ),
                    (
                      Icons.delete_outline_rounded,
                      'Delete',
                      () => removeWithUndo(
                        context,
                        message: 'Record deleted',
                        remove: () => store.removeLoan(loan.id),
                        restore: () => store.restoreLoan(loan),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoneyEmpty extends StatelessWidget {
  const _MoneyEmpty({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: scheme.onSecondaryContainer),
          ),
          const SizedBox(height: 14),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ControlColors.of(context).textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
