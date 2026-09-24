import 'models.dart';

/// Pure decision layer. Given a block, a snapshot of measured [Signals] and the
/// current time, it says whether the selected apps are blocked right now.
///
/// The engine performs no I/O and mutates nothing. Minting and persisting
/// unlock grants belongs to the caller, via [mintGrantIfEarned], so that
/// evaluation stays replayable and testable.
class RuleEngine {
  const RuleEngine();

  BlockDecision evaluate({
    required Block block,
    required Signals signals,
    required DateTime now,
  }) {
    if (!block.enabled) {
      return BlockDecision(
        blockId: block.id,
        blocked: false,
        reason: BlockReason.disabled,
      );
    }
    if (!block.hasTargets) {
      return BlockDecision(
        blockId: block.id,
        blocked: false,
        reason: BlockReason.noTargets,
      );
    }

    return switch (block.mode) {
      LimitMode.time => _evaluateTime(block, now),
      LimitMode.place => _evaluatePlace(block, signals),
      LimitMode.device => _evaluateDevice(block, signals),
      LimitMode.condition => _evaluateCondition(block, signals, now),
    };
  }

  /// Union of every active block, ready to hand to a platform enforcer.
  EnforcementPlan plan({
    required Iterable<Block> blocks,
    required Signals signals,
    required DateTime now,
  }) {
    final decisions = <BlockDecision>[];
    final apps = <AppId>{};
    final categories = <String>{};
    final domains = <String>{};
    DateTime? nextWake;

    for (final block in blocks) {
      final decision = evaluate(block: block, signals: signals, now: now);
      decisions.add(decision);
      if (decision.blocked) {
        apps.addAll(decision.blockedApps);
        categories.addAll(decision.blockedCategories);
        domains.addAll(decision.blockedDomains);
      }
      final next = decision.nextEvaluationAt;
      if (next != null && (nextWake == null || next.isBefore(nextWake))) {
        nextWake = next;
      }
    }

    return EnforcementPlan(
      blockedApps: apps,
      blockedCategories: categories,
      blockedDomains: domains,
      nextWakeAt: nextWake,
      decisions: decisions,
    );
  }

  /// Returns a grant when every condition on [block] is currently satisfied.
  ///
  /// Call this before [evaluate] and persist the result; the grant is what
  /// actually frees the apps, and its expiry is what re-arms the block.
  UnlockGrant? mintGrantIfEarned({
    required Block block,
    required Signals signals,
    required DateTime now,
  }) {
    if (!block.enabled || block.mode != LimitMode.condition) return null;
    if (block.conditions.isEmpty) return null;

    final existing = signals.grants[block.id];
    if (existing != null && existing.isActive(now)) return null;
    // Daily cumulative signals cannot buy the same allowance repeatedly.
    if (existing != null &&
        existing.grantedAt.year == now.year &&
        existing.grantedAt.month == now.month &&
        existing.grantedAt.day == now.day) {
      return null;
    }

    final allMet = block.conditions.every((c) => c.isMet(signals));
    if (!allMet) return null;

    final after = block.blockAgainAfter;
    return UnlockGrant(
      grantedAt: now,
      expiresAt: after == null ? null : now.add(after),
    );
  }

  // -------------------------------------------------------------------------

  BlockDecision _evaluateTime(Block block, DateTime now) {
    if (block.schedule.isEmpty) {
      return BlockDecision(
        blockId: block.id,
        blocked: false,
        reason: BlockReason.noTargets,
      );
    }

    final inWindow = block.schedule.any((range) => range.contains(now));
    final blocked = block.schedulePolarity == RulePolarity.blockDuring
        ? inWindow
        : !inWindow;

    DateTime? nextBoundary;
    for (final range in block.schedule) {
      final candidate = range.nextBoundary(now);
      if (nextBoundary == null || candidate.isBefore(nextBoundary)) {
        nextBoundary = candidate;
      }
    }

    return _decision(
      block,
      blocked: blocked,
      reason: BlockReason.schedule,
      nextEvaluationAt: nextBoundary,
    );
  }

  BlockDecision _evaluatePlace(Block block, Signals signals) {
    final zone = block.zone;
    if (zone == null) {
      return BlockDecision(
        blockId: block.id,
        blocked: false,
        reason: BlockReason.noTargets,
      );
    }

    final reading = signals.location;
    if (reading == null) {
      // Fail closed: without a fix we can prove neither presence nor absence,
      // and a bypass is worse than an over-block.
      return _decision(
        block,
        blocked: true,
        reason: BlockReason.signalUnavailable,
      );
    }

    // Pick the predicate that keeps apps blocked while the fix is too coarse to
    // decide: "might be in the blocked zone" blocks, "might be outside the
    // allowed zone" also blocks.
    final blocked = block.zonePolarity == RulePolarity.blockDuring
        ? zone.possiblyInside(reading)
        : !zone.certainlyInside(reading);
    return _decision(block, blocked: blocked, reason: BlockReason.zone);
  }

  BlockDecision _evaluateDevice(Block block, Signals signals) {
    if (block.devices.isEmpty) {
      return BlockDecision(
        blockId: block.id,
        blocked: false,
        reason: BlockReason.noTargets,
      );
    }

    final present = block.devices
        .any((device) => signals.connectedDevices.contains(device.id));
    final blocked =
        block.devicePolarity == RulePolarity.blockDuring ? present : !present;
    return _decision(block, blocked: blocked, reason: BlockReason.device);
  }

  BlockDecision _evaluateCondition(
    Block block,
    Signals signals,
    DateTime now,
  ) {
    if (block.conditions.isEmpty) {
      return BlockDecision(
        blockId: block.id,
        blocked: false,
        reason: BlockReason.noTargets,
      );
    }

    final progress = [
      for (final condition in block.conditions)
        ConditionProgress(
          conditionId: condition.id,
          progress: condition.progress(signals),
          met: condition.isMet(signals),
        ),
    ];

    final grant = signals.grants[block.id];
    if (grant != null && grant.isActive(now)) {
      final expiry = grant.effectiveExpiry();
      return _decision(
        block,
        blocked: false,
        reason: BlockReason.grantActive,
        nextEvaluationAt: expiry,
        grantExpiresAt: expiry,
        conditionProgress: progress,
      );
    }

    return _decision(
      block,
      blocked: true,
      reason: BlockReason.conditionUnmet,
      conditionProgress: progress,
    );
  }

  BlockDecision _decision(
    Block block, {
    required bool blocked,
    required BlockReason reason,
    DateTime? nextEvaluationAt,
    DateTime? grantExpiresAt,
    List<ConditionProgress> conditionProgress = const [],
  }) {
    return BlockDecision(
      blockId: block.id,
      blocked: blocked,
      reason: reason,
      blockedApps: blocked ? block.apps : const {},
      blockedCategories: blocked ? block.categories : const {},
      blockedDomains: blocked ? block.blockedDomains : const {},
      nextEvaluationAt: nextEvaluationAt,
      grantExpiresAt: grantExpiresAt,
      conditionProgress: conditionProgress,
    );
  }
}

/// What the platform enforcer should be shielding right now.
class EnforcementPlan {
  const EnforcementPlan({
    required this.blockedApps,
    required this.blockedCategories,
    required this.decisions,
    this.blockedDomains = const {},
    this.nextWakeAt,
  });

  final Set<AppId> blockedApps;
  final Set<String> blockedCategories;

  /// Hosts the browser guard should turn away.
  final Set<String> blockedDomains;

  final List<BlockDecision> decisions;

  /// Earliest moment any decision can flip without an external signal. Null
  /// means nothing is time-driven and the enforcer can stay idle until an event.
  final DateTime? nextWakeAt;

  bool get isEmpty =>
      blockedApps.isEmpty && blockedCategories.isEmpty && blockedDomains.isEmpty;
}
