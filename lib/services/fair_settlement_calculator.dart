import 'dart:math';

import 'package:flutter/material.dart' show TimeOfDay;

import '../models/settlement_models.dart';
import 'settlement_calculator.dart';

/// 정산을 진행할 수 없는 입력일 때 던지는 예외. [message]는 화면에 그대로
/// 보여줄 수 있는 문장이다.
class SettlementInputException implements Exception {
  const SettlementInputException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Fair-Split 정산 계산기.
///
/// 1. 음식: '음식 섭취'를 체크한 사람끼리 참석 시간에 비례해 나눈다.
/// 2. 일반 주류(소주·병맥주): '음주'를 체크한 사람끼리 참석 시간에 비례해 나눈다.
/// 3. 고가 주류·개인 주문: 배정된 사람이 배정 수량만큼 부담한다.
/// 4. 영수증 총액과 항목 합계가 다르면(할인 등) 그 차이를 각자 부담 비율대로 나눈다.
/// 5. 개인 부담액을 [roundingUnit] 단위로 내리고, 남은 금액은 룰렛 당첨자 1명이 낸다.
///
/// 모든 단계를 정수로 계산하므로 참여자 부담액의 합은 항상 결제 금액과 같다.
class FairSettlementCalculator implements SettlementCalculator {
  FairSettlementCalculator({
    this.startedAt,
    this.endedAt,
    this.roundingUnit = 100,
    this.remainderPayerId,
    int? rouletteSeed,
  }) : rouletteSeed = rouletteSeed ?? 0;

  /// 술자리 시작 시각(시작 버튼 로그). 없으면 가장 이른 도착 시각을 쓴다.
  final DateTime? startedAt;

  /// 술자리 종료 시각. 보통 영수증 결제 시각이다. 없으면 시간 가중치 없이
  /// 체크한 사람끼리 1/n 한다.
  final DateTime? endedAt;

  /// 개인 부담액 단위(원). 1이면 반올림하지 않는다.
  final int roundingUnit;

  /// 룰렛 당첨자를 이미 정했다면 그 참여자 id(총무 기기에서 한 번 정해 저장한 값).
  final String? remainderPayerId;

  /// [remainderPayerId]가 없을 때 당첨자를 뽑는 시드. 같은 시드면 항상 같은
  /// 사람이 뽑히므로 화면을 다시 그려도 결과가 바뀌지 않는다.
  final int rouletteSeed;

  /// 정산을 막아야 하는 입력 문제를 모두 찾아 화면에 보여줄 문장으로 돌려준다.
  /// 빈 목록이면 [calculate]를 호출해도 된다.
  static List<String> validate({
    required List<SettlementItem> items,
    required List<Participant> participants,
  }) {
    final problems = <String>[];
    if (participants.isEmpty) {
      problems.add('참여자를 1명 이상 추가해야 합니다.');
      return problems;
    }

    bool has(ItemCategory category) =>
        items.any((item) => item.category == category && item.price > 0);

    if (has(ItemCategory.food) && !participants.any((p) => p.ateFood)) {
      problems.add('음식 항목이 있지만 음식을 먹은 참여자가 없습니다.');
    }
    if (has(ItemCategory.regularAlcohol) &&
        !participants.any((p) => p.drankAlcohol)) {
      problems.add('소주·맥주 항목이 있지만 음주한 참여자가 없습니다. '
          '음주 체크를 확인하거나 항목 분류를 바꿔 주세요.');
    }

    final ids = participants.map((p) => p.id).toSet();
    for (final item in items) {
      if (!_isAssignedCategory(item.category)) continue;
      final assigned = item.assignments
          .where((a) => ids.contains(a.participantId))
          .fold<int>(0, (sum, a) => sum + a.quantity);
      if (assigned != item.quantity) {
        problems.add('${item.name}: ${item.quantity}개 중 $assigned개만 '
            '배정됐습니다. 주문한 사람을 모두 지정해 주세요.');
      }
    }
    return problems;
  }

  @override
  SettlementResult calculate({
    required List<SettlementItem> items,
    required List<Participant> participants,
    int? receiptTotalAmount,
  }) {
    final problems = validate(items: items, participants: participants);
    if (problems.isNotEmpty) {
      throw SettlementInputException(problems.first);
    }

    final ids = [for (final p in participants) p.id];
    final minutes = _attendedMinutes(participants);
    final weights = {
      for (final p in participants) p.id: minutes?[p.id] ?? 1,
    };

    int sumOf(ItemCategory category) => items
        .where((item) => item.category == category)
        .fold(0, (sum, item) => sum + item.price);

    final foodTotal = sumOf(ItemCategory.food);
    final regularTotal = sumOf(ItemCategory.regularAlcohol);
    final premiumTotal = sumOf(ItemCategory.premiumAlcohol);
    final personalTotal = sumOf(ItemCategory.personalOrder);

    // 1·2. 공용 항목: 체크한 사람끼리 시간 비례.
    final eaters = [for (final p in participants) if (p.ateFood) p.id];
    final drinkers = [for (final p in participants) if (p.drankAlcohol) p.id];
    final food = splitWeighted(
      foodTotal,
      eaters,
      [for (final id in eaters) weights[id]!],
    );
    final regular = splitWeighted(
      regularTotal,
      drinkers,
      [for (final id in drinkers) weights[id]!],
    );

    // 3. 배정 항목: 배정 수량만큼.
    final premium = {for (final id in ids) id: 0};
    final personal = {for (final id in ids) id: 0};
    for (final item in items) {
      if (!_isAssignedCategory(item.category)) continue;
      final target =
          item.category == ItemCategory.premiumAlcohol ? premium : personal;
      final unitPrices = splitAmountByQuantity(item.price, item.quantity);
      var cursor = 0;
      for (final assignment in item.assignments) {
        if (!target.containsKey(assignment.participantId)) continue;
        final share = unitPrices
            .skip(cursor)
            .take(assignment.quantity)
            .fold<int>(0, (sum, unit) => sum + unit);
        cursor += assignment.quantity;
        target[assignment.participantId] =
            target[assignment.participantId]! + share;
      }
    }

    final itemShares = {
      for (final id in ids)
        id: (food[id] ?? 0) +
            (regular[id] ?? 0) +
            premium[id]! +
            personal[id]!,
    };

    // 4. 할인·추가금: 각자 항목 몫에 비례.
    final itemsTotal = foodTotal + regularTotal + premiumTotal + personalTotal;
    final payable = receiptTotalAmount != null && receiptTotalAmount > 0
        ? receiptTotalAmount
        : itemsTotal;
    final difference = payable - itemsTotal;
    final discountAbs = splitWeighted(
      difference.abs(),
      ids,
      [for (final id in ids) itemShares[id]!],
    );
    final discount = {
      for (final id in ids)
        id: difference < 0 ? -discountAbs[id]! : discountAbs[id]!,
    };

    // 5. 단위 내림 + 룰렛.
    final unit = roundingUnit < 1 ? 1 : roundingUnit;
    final beforeRounding = {
      for (final id in ids) id: itemShares[id]! + discount[id]!,
    };
    final rounded = {
      for (final id in ids) id: _floorTo(beforeRounding[id]!, unit),
    };
    final remainder =
        payable - rounded.values.fold<int>(0, (sum, value) => sum + value);

    String? winner;
    if (remainder > 0) {
      winner = _pickRemainderPayer(ids, beforeRounding);
      rounded[winner] = rounded[winner]! + remainder;
    }

    return SettlementResult(
      breakdowns: [
        for (final p in participants)
          ParticipantBreakdown(
            participantId: p.id,
            participantName: p.name,
            foodShare: food[p.id] ?? 0,
            regularAlcoholShare: regular[p.id] ?? 0,
            premiumAlcoholShare: premium[p.id]!,
            personalOrderShare: personal[p.id]!,
            discountShare: discount[p.id]!,
            roundingAdjustment: rounded[p.id]! - beforeRounding[p.id]!,
            attendedMinutes: minutes?[p.id],
          ),
      ],
      foodTotal: foodTotal,
      regularAlcoholTotal: regularTotal,
      premiumAlcoholTotal: premiumTotal,
      personalOrderTotal: personalTotal,
      receiptTotalAmount: receiptTotalAmount,
      roundingUnit: unit,
      remainder: remainder,
      remainderPayerId: winner,
      isTimeWeighted: minutes != null,
    );
  }

  String _pickRemainderPayer(List<String> ids, Map<String, int> amounts) {
    final fixed = remainderPayerId;
    if (fixed != null && ids.contains(fixed)) return fixed;
    // 낼 돈이 있는 사람 중에서만 뽑는다(아무것도 안 먹은 사람은 제외).
    final candidates = [for (final id in ids) if (amounts[id]! > 0) id];
    final pool = candidates.isEmpty ? ids : candidates;
    return pool[Random(rouletteSeed).nextInt(pool.length)];
  }

  /// 참여자별 참석 시간(분). 종료 시각이 없으면 null(시간 가중치 미적용).
  ///
  /// 참석 구간 = [max(도착, 시작), min(퇴장, 종료)]. 도착을 모르면 시작부터,
  /// 퇴장을 모르면 종료까지 있었던 것으로 본다.
  Map<String, int>? _attendedMinutes(List<Participant> participants) {
    final end = endedAt;
    if (end == null) return null;

    DateTime? resolve(DateTime? exact, TimeOfDay? time) =>
        exact ?? (time == null ? null : resolveTimeOfDay(time, end));

    final arrivals = {
      for (final p in participants) p.id: resolve(p.arrivedAt, p.joinTime),
    };
    var start = startedAt;
    if (start == null) {
      final known = arrivals.values.whereType<DateTime>().toList()..sort();
      start = known.isEmpty ? null : known.first;
    }
    if (start == null || !start.isBefore(end)) return null;

    return {
      for (final p in participants)
        p.id: _minutesBetween(
          _latest(arrivals[p.id] ?? start, start),
          _earliest(resolve(p.leftAt, p.leaveTime) ?? end, end),
        ),
    };
  }

  static bool _isAssignedCategory(ItemCategory category) =>
      category == ItemCategory.premiumAlcohol ||
      category == ItemCategory.personalOrder;

  static int _floorTo(int amount, int unit) =>
      amount <= 0 ? 0 : (amount ~/ unit) * unit;

  static DateTime _latest(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  static DateTime _earliest(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  static int _minutesBetween(DateTime from, DateTime to) =>
      to.isAfter(from) ? to.difference(from).inMinutes : 0;
}

/// 날짜 없는 [time]을 [end] 이전의 가장 가까운 시각으로 해석한다.
/// 예: 종료가 01:30이고 도착이 23:10이면 전날 23:10으로 본다.
DateTime resolveTimeOfDay(TimeOfDay time, DateTime end) {
  var candidate =
      DateTime(end.year, end.month, end.day, time.hour, time.minute);
  if (candidate.isAfter(end)) {
    candidate = candidate.subtract(const Duration(days: 1));
  }
  return candidate;
}

/// [amount]를 [weights] 비율대로 정수 분배한다(최대 나머지 방식).
///
/// 반환값의 합은 항상 [amount]이고, 나머지 1원들은 소수점 이하가 큰 사람부터,
/// 같으면 목록 앞사람부터 받는다. 가중치 합이 0이면 똑같이 나눈다.
Map<String, int> splitWeighted(
  int amount,
  List<String> ids,
  List<int> weights,
) {
  if (ids.isEmpty) return const {};
  if (amount == 0) return {for (final id in ids) id: 0};

  var effective = weights;
  var total = effective.fold<int>(0, (sum, w) => sum + w);
  if (total <= 0) {
    effective = List.filled(ids.length, 1);
    total = ids.length;
  }

  final base = [for (final w in effective) amount * w ~/ total];
  final fraction = [for (final w in effective) amount * w % total];
  var left = amount - base.fold<int>(0, (sum, v) => sum + v);

  final order = List.generate(ids.length, (i) => i)
    ..sort((a, b) {
      final byFraction = fraction[b].compareTo(fraction[a]);
      return byFraction != 0 ? byFraction : a.compareTo(b);
    });
  for (final index in order) {
    if (left == 0) break;
    base[index] += 1;
    left -= 1;
  }
  return {for (var i = 0; i < ids.length; i++) ids[i]: base[i]};
}
