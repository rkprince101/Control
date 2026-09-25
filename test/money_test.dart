import 'dart:io';

import 'package:control/data/money.dart';
import 'package:control/data/page_lock.dart';
import 'package:control/state/control_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ExpenseEntry _entry(
  String id,
  EntryType type,
  double amount,
  DateTime date, {
  String category = 'Food',
}) => ExpenseEntry(
  id: id,
  type: type,
  title: id,
  amount: amount,
  category: category,
  date: date,
  createdAt: date,
);

void main() {
  group('the ledger', () {
    final september = DateTime(2026, 9);
    final book = MoneyBook(
      currency: Currency.byCode('INR'),
      entries: [
        _entry(
          'jul pay',
          EntryType.income,
          1000,
          DateTime(2026, 7, 1),
          category: 'Salary',
        ),
        _entry(
          'aug pay',
          EntryType.income,
          1000,
          DateTime(2026, 8, 1),
          category: 'Salary',
        ),
        _entry(
          'aug rent',
          EntryType.expense,
          1500,
          DateTime(2026, 8, 2),
          category: 'Bills',
        ),
        _entry(
          'sep pay',
          EntryType.income,
          2000,
          DateTime(2026, 9, 1),
          category: 'Salary',
        ),
        _entry('lunch', EntryType.expense, 120, DateTime(2026, 9, 3)),
        _entry('dinner', EntryType.expense, 380, DateTime(2026, 9, 3)),
        _entry(
          'fund',
          EntryType.expense,
          450,
          DateTime(2026, 9, 4),
          category: 'Investment',
        ),
        _entry(
          'dividend',
          EntryType.income,
          40,
          DateTime(2026, 9, 20),
          category: 'Investment',
        ),
      ],
      budgets: [
        Budget(
          id: 'food',
          label: '',
          amount: 400,
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 9, 30),
          category: 'Food',
        ),
        Budget(
          id: 'all',
          label: 'Trip',
          amount: 10000,
          start: DateTime(2026, 9, 3),
          end: DateTime(2026, 9, 4),
        ),
      ],
      loans: [
        LoanEntry(
          id: 'a',
          type: LoanType.lent,
          person: 'A',
          amount: 300,
          date: DateTime(2026, 9, 1),
        ),
        LoanEntry(
          id: 'b',
          type: LoanType.borrowed,
          person: 'B',
          amount: 700,
          date: DateTime(2026, 9, 2),
        ),
        LoanEntry(
          id: 'c',
          type: LoanType.lent,
          person: 'C',
          amount: 999,
          date: DateTime(2026, 9, 5),
          settled: true,
        ),
      ],
    );

    test('each month opens on the balance the last one closed on', () {
      // July +1000, August +1000 -1500: September opens on 500.
      expect(book.broughtForwardTo(september), 500);
      expect(book.incomeIn(september), 2040);
      expect(book.expenseIn(september), 950);
      expect(book.balanceIn(september), 1090);
      expect(book.closingBalanceIn(september), 1590);
      expect(book.broughtForwardTo(DateTime(2026, 7)), 0);
    });

    test('days add up for the heatmap and its day sheet', () {
      expect(book.expenseOn(DateTime(2026, 9, 3)), 500);
      expect(book.incomeOn(DateTime(2026, 9, 1)), 2000);
      expect(book.busiestDaySpend, 1500);
      expect(
        {for (final e in book.entriesOn(DateTime(2026, 9, 3))) e.id},
        {'lunch', 'dinner'},
      );
    });

    test('investments stand apart, with what came back', () {
      expect([for (final e in book.investments) e.id], ['fund']);
      expect(book.totalInvested, 450);
      expect(book.investmentReturns, 40);
    });

    test('categories rank largest first', () {
      final spent = book.expenseByCategory(september);
      expect(spent.first.key, 'Food');
      expect(spent.first.value, 500);
      expect(spent.last.key, 'Investment');
    });

    test('budgets count their own dates and category', () {
      final food = book.budgets.firstWhere((b) => b.id == 'food');
      final trip = book.budgets.firstWhere((b) => b.id == 'all');
      expect(book.spentFor(food), 500);
      // The whole of the 3rd and 4th, whatever the category.
      expect(book.spentFor(trip), 950);
      expect(food.title, 'Food');
      expect(trip.title, 'Trip');
    });

    test('loans: unsettled first, and only the unsettled are owed', () {
      expect(book.loans.last.id, 'c');
      expect(book.owedToYou, 300);
      expect(book.youOwe, 700);
    });

    test('amounts read like money', () {
      final rupees = Currency.byCode('INR');
      expect(rupees.format(1234567), '₹1,234,567');
      expect(rupees.format(12.5), '₹12.50');
      expect(rupees.format(-80), '₹80');
      expect(rupees.formatSigned(-80), '-₹80');
      expect(Currency.byCode('nope').code, 'USD');
      expect(parseAmount('1,250.5'), 1250.5);
      expect(parseAmount('0'), isNull);
      expect(parseAmount('abc'), isNull);
      expect(amountText(12), '12');
      expect(amountText(12.5), '12.50');
    });

    test('an Other entry shows what it was, and survives JSON', () {
      final pet = ExpenseEntry(
        id: 'pet',
        type: EntryType.expense,
        title: '',
        amount: 12,
        category: 'Other',
        detail: 'Pet food',
        date: DateTime(2026, 9, 3),
        createdAt: DateTime(2026, 9, 3, 10),
      );
      expect(pet.displayCategory, 'Pet food');
      expect(pet.heading, 'Pet food');
      expect(ExpenseEntry.fromJson(pet.toJson()), pet);
      expect(ExpenseEntry.fromJson({'id': 'x'}), isNull);
      expect(
        ExpenseCategory.resolve(EntryType.income, 'Food').name,
        'Other',
        reason: 'an unknown category still renders',
      );
    });
  });

  group('the page lock', () {
    test('a PIN is salted, never stored, and checks exactly', () {
      final lock = const PageLock().withPin('2468');
      expect(lock.enabled, isTrue);
      // Only a salt and a digest are kept.
      expect(lock.toJson().keys, {'hash', 'salt', 'pages'});
      expect(lock.hash, hasLength(64));
      expect(lock.verify('2468'), isTrue);
      expect(lock.verify('24680'), isFalse);
      expect(lock.verify('1111'), isFalse);
      // Same PIN, new salt: a different hash.
      expect(const PageLock().withPin('2468').hash, isNot(lock.hash));

      final back = PageLock.fromJson(
        lock.withPage('money', locked: true).toJson(),
      );
      expect(back.verify('2468'), isTrue);
      expect(back.pages, {'money'});
      expect(PageLock.fromJson(null).enabled, isFalse);
    });
  });

  group('store', () {
    late Directory storage;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      storage = Directory.systemTemp.createTempSync('control_money');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.control/enforcement'),
            (call) async => switch (call.method) {
              'isAccessibilityEnabled' => false,
              'hasUsageAccess' => false,
              'stepsStatus' => <String, Object?>{
                'granted': false,
                'available': false,
              },
              'protectionStatus' => <String, Object?>{
                'adminActive': false,
                'deviceOwner': false,
                'uninstallBlocked': false,
              },
              'shortcutCounts' => <String, Object?>{},
              _ => null,
            },
          );
    });

    tearDown(() => storage.deleteSync(recursive: true));

    ControlStore newStore() => ControlStore(storageDirectory: storage);

    test('entries, budgets, loans and currency survive a restart', () async {
      final first = newStore();
      await first.init();
      await first.setCurrency(Currency.byCode('EUR'));
      await first.addMoneyEntry(
        type: EntryType.expense,
        amount: 42,
        category: 'Other',
        detail: 'Stamps',
        date: DateTime(2026, 9, 3, 18, 30),
      );
      await first.addMoneyEntry(
        type: EntryType.expense,
        amount: 0,
        category: 'Food',
        date: DateTime(2026, 9, 3),
      );
      expect(first.moneyBook.entries, hasLength(1), reason: 'zero is ignored');
      await first.addBudget(
        label: '  Trip ',
        amount: 300,
        // Picked backwards; stored the right way round.
        start: DateTime(2026, 9, 10),
        end: DateTime(2026, 9, 1),
      );
      await first.addLoan(
        type: LoanType.borrowed,
        person: 'Sam',
        amount: 60,
        date: DateTime(2026, 9, 2),
      );
      first.dispose();

      final second = newStore();
      await second.init();
      final book = second.moneyBook;
      expect(second.currency.code, 'EUR');
      expect(book.format(42), '€42');
      expect(book.entries.single.date, DateTime(2026, 9, 3));
      expect(book.entries.single.displayCategory, 'Stamps');
      expect(book.budgets.single.label, 'Trip');
      expect(book.budgets.single.start, DateTime(2026, 9, 1));
      expect(book.budgets.single.end, DateTime(2026, 9, 10));
      expect(book.youOwe, 60);
      second.dispose();
    });

    test('edits, settling, and taking a delete back', () async {
      final store = newStore();
      await store.init();
      await store.addMoneyEntry(
        type: EntryType.expense,
        amount: 10,
        category: 'Other',
        detail: 'Stamps',
        date: DateTime(2026, 9, 3),
      );
      final entry = store.moneyBook.entries.single;
      // Moving away from Other drops the detail.
      await store.updateMoneyEntry(entry.id, category: 'Food', amount: 12);
      final edited = store.moneyBook.byId(entry.id)!;
      expect(edited.category, 'Food');
      expect(edited.detail, isEmpty);
      expect(edited.amount, 12);

      await store.removeMoneyEntry(entry.id);
      expect(store.moneyBook.isEmpty, isTrue);
      await store.restoreMoneyEntry(edited);
      expect(store.moneyBook.entries.single.id, entry.id);

      await store.addLoan(
        type: LoanType.lent,
        person: 'Kim',
        amount: 5,
        date: DateTime(2026, 9, 2),
      );
      final loan = store.moneyBook.loans.single;
      await store.toggleLoanSettled(loan.id);
      expect(store.moneyBook.loans.single.settled, isTrue);
      expect(store.moneyBook.owedToYou, 0);
      await store.toggleLoanSettled(loan.id);
      expect(store.moneyBook.loans.single.settledAt, isNull);
      store.dispose();
    });

    test('the PIN persists; what was unlocked does not', () async {
      final first = newStore();
      await first.init();
      expect(first.lockSettingsOpen, isTrue, reason: 'nothing to guard yet');
      await first.setPin('9876');
      await first.setPageLocked('money', locked: true);
      expect(first.isPageLocked('money'), isTrue);
      expect(first.isPageLocked('notes'), isFalse);
      expect(first.unlockPage('money', '1111'), isFalse);
      expect(first.unlockPage('money', '9876'), isTrue);
      expect(first.isPageLocked('money'), isFalse);
      expect(first.hasUnlockedPages, isTrue);
      first.lockPages();
      expect(first.isPageLocked('money'), isTrue);
      expect(first.lockSettingsOpen, isFalse);
      first.dispose();

      final second = newStore();
      await second.init();
      expect(second.isPageLocked('money'), isTrue);
      expect(second.lockSettingsOpen, isFalse);
      expect(second.unlockLockSettings('9876'), isTrue);
      await second.clearPin();
      expect(second.isPageLocked('money'), isFalse);
      second.dispose();

      final third = newStore();
      await third.init();
      expect(third.pageLock.enabled, isFalse);
      third.dispose();
    });
  });
}
