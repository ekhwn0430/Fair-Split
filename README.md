# Fair-Split
> 참석 시간·음주 여부·개인 주문을 반영하는 술자리 정산 앱

## 프로젝트 소개
술자리 정산은 보통 1/n로 끝나지만, 늦게 온 사람·술을 안 마신 사람·혼자 비싼 메뉴를 시킨 사람이 같은 돈을 내는 문제가 있습니다.
Fair-Split은 영수증을 촬영하면 메뉴를 자동으로 분류하고, 모임방에 기록된 도착·퇴장 시각과 음식·음주 여부를 반영해 각자 낼 금액과 그 근거를 계산합니다.

## 팀원
| 이름 | 역할 |
|------|------|
| 엄기환 (팀장) | 계산 파트, 파트 통합, 문서 |
| 고상혁 | 서버 파트 (Firebase 인증·모임) |
| 채지인 | 입력 파트 (영수증 인식·입력 화면) |

---

## 실행 방법

### 필수 설치
- Flutter (Dart SDK 3.13 이상)
- Android Studio 또는 VS Code
- Gemini API 키 (영수증 인식용, 없으면 직접 입력만 가능)

### 실행
```bash
git clone https://github.com/ekhwn0430/Fair-Split.git
cd Fair-Split
flutter pub get

# Gemini 키는 저장소에 올리지 않고 실행할 때 전달
flutter run --dart-define=GEMINI_API_KEY=발급받은키

# 테스트
flutter test
```

### Firebase
별도 설정 없이 clone 후 바로 실행됩니다. 콘솔 접근이 필요하면 고상혁에게 구글 이메일을 알려주세요.
- Auth: 이메일·비밀번호
- Firestore: 서울 리전 (asia-northeast3)

---

## 사용 흐름
```
[총무] 모임 생성 → 6자리 코드 공유 → '술자리 시작' (시작 시각 기록)
[참여자] 코드로 참여 → '도착했어요' (도착 시각 + 음식·음주·개인 주문 체크)
        → 먼저 가면 '먼저 가요' (퇴장 시각 기록)
[총무] '영수증으로 정산하기' → 영수증 촬영·인식 → 항목 확인·수정
      → 참여자 정보 자동 채움 확인 → 정산 결과
```

---

## 정산 규칙

| 항목 | 부담하는 사람 | 나누는 방식 |
|---|---|---|
| 음식·안주 | '음식 먹음' 체크한 사람 | 참석 시간 비례 |
| 소주·병맥주 등 일반 주류 | '소주·맥주 마심' 체크한 사람 | 참석 시간 비례 |
| 생맥주·하이볼·와인 등 고가 주류 | 주문한 사람 | 배정 수량만큼 |
| 개인 주문·음료수 | 주문한 사람 | 배정 수량만큼 |

- **참석 시간** = max(도착, 시작) ~ min(퇴장, 영수증 결제 시각). 자정을 넘겨도 처리합니다.
- **할인**: 영수증 총액과 항목 합계가 다르면 그 차이를 각자 부담 비율대로 나눕니다.
- **단위 정리**: 개인 부담액을 100원 단위로 내리고, 남은 금액은 룰렛으로 뽑힌 1명이 냅니다.
- **정산 차단**: 술 항목이 있는데 음주자가 0명이거나, 고가 주류·개인 주문의 주문자를 다 지정하지 않으면 정산할 수 없습니다.
- **총액 보존**: 모든 계산을 정수로 처리하므로 참여자 부담액의 합은 항상 결제 금액과 같습니다.

---

## 구현 기능

### 서버 파트 (고상혁)
- 이메일 회원가입·로그인, 자동 로그인, 게스트 참여(이름만 입력)
- 프로필·마이페이지: 이름, 은행·예금주·계좌번호 저장 및 수정
- 모임 생성(6자리 코드 발급·복사·공유), 코드로 참여
- 모임방: 술자리 시작, 도착 체크, 음식·음주·음료수 개수·개인 주문 입력, 참여자 현황 실시간 표시

### 입력 파트 (채지인)
- 영수증 촬영·갤러리 선택 → Gemini API로 메뉴·가격·수량·결제 시각·총액 추출 및 분류
- 이미지 전송 전 외부 전송 안내·동의 팝업
- 인식 결과 확인·수정 화면 (항목 합계 ≠ 총액이면 경고), 메뉴명 기반 주류 분류 보정
- 인식 실패 시 직접 입력
- 영수증 보관함: 기기 내부에 사진과 확인된 항목 저장, 저장된 영수증으로 재정산
- 참여자 입력, 개인 주문 수량 배정

### 계산 파트 (엄기환)
- 정산 계산기 `FairSettlementCalculator` (위 정산 규칙 전체)
- 정산 결과 화면: 사람별 참석 시간, 항목별 금액, 할인, 단위 정리·룰렛 근거 표시
- 파트 통합: 모임방 기록 → 참여자 입력 자동 채움, 개인 주문 메뉴명 → 영수증 항목 자동 배정, '먼저 가요' 퇴장 기록
- 검증: 단위 테스트 + 파이썬 참조 구현(`docs/calculator_reference.py`)으로 무작위 2만 건 교차 검증

---

## 폴더 구조
```
lib/
├── main.dart                         # 앱 시작, 로그인 상태에 따라 화면 분기
├── config.dart                       # GEMINI_API_KEY (--dart-define)
├── firebase_options.dart
├── models/
│   └── settlement_models.dart        # 항목·참여자·정산 결과 모델
├── services/
│   ├── auth_service.dart             # Firebase Auth·프로필
│   ├── gemini_receipt_service.dart   # 영수증 인식
│   ├── alcohol_category_classifier.dart  # 주류 분류 보정
│   ├── receipt_storage_service.dart  # 영수증 보관함 (기기 내부)
│   ├── settlement_calculator.dart    # 계산기 인터페이스
│   └── fair_settlement_calculator.dart   # 정산 계산기
└── screens/
    ├── login_screen.dart / signup_screen.dart / my_page_screen.dart
    ├── home_screen.dart
    ├── create_meeting_screen.dart / join_meeting_screen.dart / guest_join_screen.dart
    ├── meeting_room_screen.dart      # 모임방, '영수증으로 정산하기'
    ├── receipt_upload_screen.dart    # 촬영·갤러리·직접 입력
    ├── receipt_edit_screen.dart      # 인식 결과 확인·수정
    ├── receipt_manual_entry_screen.dart
    ├── receipt_list_screen.dart / receipt_detail_screen.dart  # 보관함
    ├── participant_input_screen.dart # 참여자·시간·개인 주문 배정
    └── settlement_result_screen.dart # 정산 결과
test/                                 # 계산기·모델·화면 테스트
docs/calculator_reference.py          # 계산 알고리즘 파이썬 참조 구현
```

---

## Firestore 데이터 구조
```
users/{uid}
  - name: String
  - email: String
  - accountNumber: String   # "은행|예금주|계좌번호"
  - createdAt: Timestamp

meetings/{meetingId}
  - name: String
  - code: String            # 6자리
  - hostId: String
  - hostName: String
  - status: String          # waiting / started
  - createdAt: Timestamp
  - startedAt: Timestamp
  - members:
      {uid 또는 guestId}:
        - name: String
        - joinedAt: Timestamp
        - arrivedAt: Timestamp
        - leftAt: Timestamp       # 먼저 간 경우만
        - eatFood: Boolean
        - drinkAlcohol: Boolean
        - drinkSoftDrink: Boolean
        - softDrinkCount: int
        - personalOrders: List [{name, price}]
        - personalTotal: int
        - isGuest: Boolean
```

---

## 남은 작업
- 송금 요청·송금 완료 체크 및 실시간 동기화
- 정산 결과·영수증 항목 Firestore 저장(모임 이력)
- 정산 결과 공유(카카오톡 등)
- 1차·2차 영수증 분리 정산
- Firestore 보안 규칙
- 영수증 인식 정확도·정산 정확도 평가

## 협업 규칙
- `main`은 팀장만 merge합니다. 직접 push하지 않습니다.
- 작업은 `git checkout -b feature/작업명 origin/main`으로 main에서 브랜치를 따서 진행합니다.
- 완료되면 Pull Request를 올리고, 검토 후 merge합니다.
