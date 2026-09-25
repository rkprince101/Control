import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/habits.dart' show dateOnly;
import '../data/money.dart';
import '../main.dart';
import 'controls.dart';
import 'sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// Which colour means money in and which means money out, everywhere on the
/// Money page: the theme's own green and red, so it matches the rest of the
/// app.
class MoneyTones {
  const MoneyTones._(this.income, this.expense);

  factory MoneyTones.of(BuildContext context) => MoneyTones._(
    Theme.of(context).colorScheme.primary,
    ControlColors.of(context).heavy,
  );

  final Color income;
  final Color expense;

  Color of(EntryType type) => type.isExpense ? expense : income;
}

/// A category's icon on a tinted square.
class CategoryTile extends StatelessWidget {
  const CategoryTile({required this.category, this.size = 40, super.key});

  final ExpenseCategory category;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: category.color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Icon(category.icon, size: size * 0.5, color: category.color),
  );
}

/// "Today", "Yesterday", otherwise "Sep 3".
String moneyDayLabel(BuildContext context, DateTime day, DateTime today) {
  final days = dateOnly(today).difference(dateOnly(day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return MaterialLocalizations.of(context).formatShortMonthDay(day);
}

/// Removes something straight away, with a moment to take it back.
void removeWithUndo(
  BuildContext context, {
  required String message,
  required Future<void> Function() remove,
  required Future<void> Function() restore,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  remove();
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Undo', onPressed: restore),
      ),
    );
}

/// An income or expense, new or being edited.
class EntryEditorSheet extends StatefulWidget {
  const EntryEditorSheet({this.existing, this.date, super.key});

  final ExpenseEntry? existing;

  /// The day a new entry starts on; today when null.
  final DateTime? date;

  static Future<void> show(
    BuildContext context, {
    ExpenseEntry? existing,
    DateTime? date,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ControlColors.of(context).background,
    builder: (_) => EntryEditorSheet(existing: existing, date: date),
  );

  @override
  State<EntryEditorSheet> createState() => _EntryEditorSheetState();
}

class _EntryEditorSheetState extends State<EntryEditorSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _title;
  late final TextEditingController _detail;
  late EntryType _type;
  late String _category;
  late DateTime _date;

  bool get _editing => widget.existing != null;
  bool get _isOther => _category == ExpenseCategory.otherName;

  @override
  void initState() {
    super.initState();
    final entry = widget.existing;
    _type = entry?.type ?? EntryType.expense;
    _amount = TextEditingController(
      text: entry == null ? '' : amountText(entry.amount),
    );
    _title = TextEditingController(text: entry?.title ?? '');
    _detail = TextEditingController(text: entry?.detail ?? '');
    _category = entry?.category ?? ExpenseCategory.forType(_type).first.name;
    _date =
        entry?.date ??
        dateOnly(widget.date ?? StoreScope.read(context).wallNow());
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _detail.dispose();
    super.dispose();
  }

  void _setType(EntryType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      // Keep the category when both lists have it, as Investment and Other do.
      if (ExpenseCategory.forType(type).every((c) => c.name != _category)) {
        _category = ExpenseCategory.forType(type).first.name;
      }
    });
  }

  Future<void> _pickDate() async {
    final today = StoreScope.read(context).wallNow();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  void _save() {
    final amount = parseAmount(_amount.text);
    if (amount == null) return;
    final store = StoreScope.read(context);
    final detail = _isOther ? _detail.text : '';
    if (_editing) {
      store.updateMoneyEntry(
        widget.existing!.id,
        type: _type,
        amount: amount,
        category: _category,
        date: _date,
        title: _title.text,
        detail: detail,
      );
    } else {
      store.addMoneyEntry(
        type: _type,
        amount: amount,
        category: _category,
        date: _date,
        title: _title.text,
        detail: detail,
      );
    }
    Navigator.pop(context);
  }

  void _delete() {
    final entry = widget.existing!;
    final store = StoreScope.read(context);
    removeWithUndo(
      context,
      message: 'Entry deleted',
      remove: () => store.removeMoneyEntry(entry.id),
      restore: () => store.restoreMoneyEntry(entry),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final canSave = parseAmount(_amount.text) != null;

    return _EditorFrame(
      title: _editing ? 'Edit entry' : 'New entry',
      onSave: canSave ? _save : null,
      children: [
        ControlSegmented<EntryType>(
          expand: true,
          options: const [
            (EntryType.expense, 'Expense'),
            (EntryType.income, 'Income'),
          ],
          value: _type,
          onChanged: _setType,
        ),
        const SizedBox(height: 16),
        ControlCard(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            children: [
              Text(
                store.currency.symbol,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _amount,
                  autofocus: !_editing,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                  ],
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: MoneyTones.of(context).of(_type),
                  ),
                  decoration: const InputDecoration(
                    hintText: '0',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          maxLength: ExpenseEntry.maxTitleLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Note (optional)',
            counterText: '',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
        ),
        const SizedBox(height: 20),
        const _FieldLabel('Category'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in ExpenseCategory.forType(_type))
              CategoryChip(
                label: category.name,
                icon: category.icon,
                color: category.color,
                selected: category.name == _category,
                onTap: () => setState(() => _category = category.name),
              ),
          ],
        ),
        // Only Other needs saying what it actually was.
        if (_isOther) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _detail,
            maxLength: ExpenseEntry.maxTitleLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What was it? (e.g. Pet food)',
              counterText: '',
              prefixIcon: Icon(Icons.edit_note_rounded),
            ),
          ),
          const SizedBox(height: 6),
          const _Hint('Still counts under Other in your stats.'),
        ],
        const SizedBox(height: 20),
        const _FieldLabel('Date'),
        DateField(date: _date, onTap: _pickDate),
        if (_editing) ...[
          const SizedBox(height: 24),
          _DeleteButton(label: 'Delete entry', onPressed: _delete),
        ],
      ],
    );
  }
}

/// A spending limit over any stretch of days.
class BudgetSheet extends StatefulWidget {
  const BudgetSheet({this.existing, super.key});

  final Budget? existing;

  static Future<void> show(BuildContext context, {Budget? existing}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: ControlColors.of(context).background,
        builder: (_) => BudgetSheet(existing: existing),
      );

  @override
  State<BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<BudgetSheet> {
  late final TextEditingController _label;
  late final TextEditingController _amount;

  /// Empty for all spending.
  late String _category;
  late DateTime _start;
  late DateTime _end;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final budget = widget.existing;
    final today = dateOnly(StoreScope.read(context).wallNow());
    _label = TextEditingController(text: budget?.label ?? '');
    _amount = TextEditingController(
      text: budget == null ? '' : amountText(budget.amount),
    );
    _category = budget?.category ?? '';
    _start = budget?.start ?? today;
    _end = budget?.end ?? DateTime(today.year, today.month + 1, today.day);
  }

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final today = StoreScope.read(context).wallNow();
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (picked == null) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  void _save() {
    final amount = parseAmount(_amount.text);
    if (amount == null) return;
    final store = StoreScope.read(context);
    if (_editing) {
      store.updateBudget(
        widget.existing!.id,
        label: _label.text,
        amount: amount,
        start: _start,
        end: _end,
        category: _category,
      );
    } else {
      store.addBudget(
        label: _label.text,
        amount: amount,
        start: _start,
        end: _end,
        category: _category,
      );
    }
    Navigator.pop(context);
  }

  void _delete() {
    final budget = widget.existing!;
    final store = StoreScope.read(context);
    removeWithUndo(
      context,
      message: 'Budget deleted',
      remove: () => store.removeBudget(budget.id),
      restore: () => store.restoreBudget(budget),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return _EditorFrame(
      title: _editing ? 'Edit budget' : 'New budget',
      onSave: parseAmount(_amount.text) == null ? null : _save,
      children: [
        TextField(
          controller: _label,
          maxLength: Budget.maxLabelLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Label (e.g. Goa trip)',
            counterText: '',
            prefixIcon: Icon(Icons.label_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        _AmountField(
          controller: _amount,
          symbol: store.currency.symbol,
          onChanged: () => setState(() {}),
          autofocus: !_editing,
        ),
        const SizedBox(height: 20),
        const _FieldLabel('Date range'),
        Row(
          children: [
            Expanded(
              child: DateField(
                date: _start,
                compact: true,
                onTap: () => _pick(start: true),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded, size: 18),
            ),
            Expanded(
              child: DateField(
                date: _end,
                compact: true,
                onTap: () => _pick(start: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _FieldLabel('Counts'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CategoryChip(
              label: 'All spending',
              icon: Icons.all_inclusive_rounded,
              color: Theme.of(context).colorScheme.primary,
              selected: _category.isEmpty,
              onTap: () => setState(() => _category = ''),
            ),
            for (final category in ExpenseCategory.expense)
              CategoryChip(
                label: category.name,
                icon: category.icon,
                color: category.color,
                selected: category.name == _category,
                onTap: () => setState(() => _category = category.name),
              ),
          ],
        ),
        if (_editing) ...[
          const SizedBox(height: 24),
          _DeleteButton(label: 'Delete budget', onPressed: _delete),
        ],
      ],
    );
  }
}

/// Money lent out or borrowed.
class LoanSheet extends StatefulWidget {
  const LoanSheet({this.existing, super.key});

  final LoanEntry? existing;

  static Future<void> show(BuildContext context, {LoanEntry? existing}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: ControlColors.of(context).background,
        builder: (_) => LoanSheet(existing: existing),
      );

  @override
  State<LoanSheet> createState() => _LoanSheetState();
}

class _LoanSheetState extends State<LoanSheet> {
  late final TextEditingController _person;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late LoanType _type;
  late DateTime _date;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final loan = widget.existing;
    _person = TextEditingController(text: loan?.person ?? '');
    _amount = TextEditingController(
      text: loan == null ? '' : amountText(loan.amount),
    );
    _note = TextEditingController(text: loan?.note ?? '');
    _type = loan?.type ?? LoanType.lent;
    _date = loan?.date ?? dateOnly(StoreScope.read(context).wallNow());
  }

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final today = StoreScope.read(context).wallNow();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  void _save() {
    final amount = parseAmount(_amount.text);
    if (amount == null) return;
    final store = StoreScope.read(context);
    if (_editing) {
      store.updateLoan(
        widget.existing!.id,
        type: _type,
        person: _person.text,
        amount: amount,
        date: _date,
        note: _note.text,
      );
    } else {
      store.addLoan(
        type: _type,
        person: _person.text,
        amount: amount,
        date: _date,
        note: _note.text,
      );
    }
    Navigator.pop(context);
  }

  void _delete() {
    final loan = widget.existing!;
    final store = StoreScope.read(context);
    removeWithUndo(
      context,
      message: 'Record deleted',
      remove: () => store.removeLoan(loan.id),
      restore: () => store.restoreLoan(loan),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final lent = _type == LoanType.lent;
    return _EditorFrame(
      title: _editing ? 'Edit record' : 'Lend / Loan',
      onSave: parseAmount(_amount.text) == null ? null : _save,
      children: [
        ControlSegmented<LoanType>(
          expand: true,
          options: const [
            (LoanType.lent, 'I lent'),
            (LoanType.borrowed, 'I borrowed'),
          ],
          value: _type,
          onChanged: (type) => setState(() => _type = type),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _person,
          maxLength: LoanEntry.maxNameLength,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: lent ? 'Who owes you?' : 'Who did you borrow from?',
            counterText: '',
            prefixIcon: const Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        _AmountField(
          controller: _amount,
          symbol: store.currency.symbol,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        DateField(date: _date, onTap: _pick),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Note (optional)',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
        ),
        if (_editing) ...[
          const SizedBox(height: 24),
          _DeleteButton(label: 'Delete record', onPressed: _delete),
        ],
      ],
    );
  }
}

/// What came in and went out on one day, opened from the spending heatmap.
class MoneyDaySheet extends StatelessWidget {
  const MoneyDaySheet({required this.day, super.key});

  final DateTime day;

  static Future<void> show(BuildContext context, DateTime day) =>
      showControlSheet<void>(context, builder: (_) => MoneyDaySheet(day: day));

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final book = store.moneyBook;
    final tones = MoneyTones.of(context);
    final entries = book.entriesOn(day);
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SheetScaffold(
        title: MaterialLocalizations.of(context).formatMediumDate(day),
        leading: SheetAction('Close', onPressed: () => Navigator.pop(context)),
        trailing: SheetAction(
          'Add',
          primary: true,
          onPressed: () {
            Navigator.pop(context);
            EntryEditorSheet.show(context, date: day);
          },
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: _DayTally(
                    label: 'In',
                    amount: book.format(book.incomeOn(day)),
                    color: tones.income,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DayTally(
                    label: 'Out',
                    amount: book.format(book.expenseOn(day)),
                    color: tones.expense,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nothing on this day.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              )
            else
              for (final entry in entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CategoryTile(
                    category: ExpenseCategory.resolve(
                      entry.type,
                      entry.category,
                    ),
                  ),
                  title: Text(
                    entry.heading,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: entry.title.isEmpty
                      ? null
                      : Text(entry.displayCategory),
                  trailing: Text(
                    '${entry.type.isExpense ? '-' : '+'}'
                    '${book.format(entry.amount)}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: tones.of(entry.type),
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    EntryEditorSheet.show(context, existing: entry);
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _DayTally extends StatelessWidget {
  const _DayTally({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ControlCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: ControlColors.of(context).textMuted,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              amount,
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

/// The frame every money editor shares: grabber, Cancel and Save, and a
/// scrolling form that clears the keyboard.
class _EditorFrame extends StatelessWidget {
  const _EditorFrame({
    required this.title,
    required this.onSave,
    required this.children,
  });

  final String title;
  final VoidCallback? onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.92,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        children: [
          const SheetGrabber(),
          SheetHeader(
            title: title,
            leading: SheetAction(
              'Cancel',
              onPressed: () => Navigator.pop(context),
            ),
            trailing: SheetAction('Save', primary: true, onPressed: onSave),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: children,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.symbol,
    required this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String symbol;
  final VoidCallback onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    onChanged: (_) => onChanged(),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.,]'))],
    decoration: InputDecoration(
      hintText: 'Amount',
      prefixIcon: SizedBox(
        width: 48,
        child: Center(
          child: Text(symbol, style: Theme.of(context).textTheme.titleMedium),
        ),
      ),
    ),
  );
}

/// A tappable date in the field style, opening the date picker.
class DateField extends StatelessWidget {
  const DateField({
    required this.date,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final DateTime date;
  final VoidCallback onTap;

  /// The short form, for two fields side by side.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final colors = ControlColors.of(context);
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: Shapes.field,
      child: InkWell(
        onTap: onTap,
        borderRadius: Shapes.field,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 18,
                color: colors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  compact
                      ? localizations.formatMediumDate(date)
                      : localizations.formatFullDate(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!compact)
                Icon(Icons.chevron_right_rounded, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A filter chip in a category's own colour.
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? color.withValues(alpha: 0.2)
              : scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: Shapes.chip,
            side: BorderSide(
              color: selected ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: RoundedRectangleBorder(borderRadius: Shapes.chip),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? color : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: ControlColors.of(context).textMuted,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text,
      style: TextStyle(
        color: ControlColors.of(context).textMuted,
        fontSize: 12,
        height: 1.4,
      ),
    ),
  );
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(color: colors.heavy, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
