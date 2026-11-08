# Fair-Split 🍻
> 시간·음주 가중치 기반 공정 정산 앱

## 프로젝트 소개
회식·술자리에서 음주 여부, 참석 시간, 개인 주문을 반영한 공정한 정산을 자동으로 계산해주는 Flutter 앱입니다.

## 팀원
| 이름 | 역할 |
|------|------|
| 엄기환 (팀장) | 계산·문서 파트 |
| 고상혁 | 서버 파트 |
| 채지인 | 입력 파트 |

---

## 개발 환경 설정

### 필수 설치
- Flutter 3.x 이상
- Android Studio
- Firebase 계정 (고상혁에게 문의)

### 프로젝트 세팅
\```bash
# 1. 클론
git clone https://github.com/ekhwn0430/Fair-Split.git
cd Fair-Split

# 2. 패키지 설치
flutter pub get

# 3. 실행 (Gemini 키는 저장소에 올리지 않음)
flutter run --dart-define=GEMINI_API_KEY=발급받은키

# 4. 테스트
flutter test
\```

---

## 구현 완료 기능 (고상혁 - 서버 파트)

### 🔐 인증
- 이메일·비밀번호 회원가입·로그인
- 자동 로그인 (Firebase Auth)
- 게스트 모드 (이름만 입력하고 참여)

### 👤 프로필·마이페이지
- 회원가입 시 이름·이메일·은행·계좌번호 저장
- 마이페이지에서 언제든 수정 가능
- 주요 은행·추가 은행 드롭다운 선택

### 🏠 모임 생성 (총무)
- 모임 이름 입력 후 6자리 랜덤 코드 발급
- 코드 복사·카톡 공유 기능
- 술자리 시작 버튼 → 시작 시간 Firestore 기록

### 🚪 모임 참여
- 6자리 코드 입력으로 참여
- 게스트도 이름만 입력하고 참여 가능

### ✅ 모임 방 (참여자)
- 도착 버튼 → 도착 시간 Firestore 기록
- 체크박스 선택:
  - 🍖 음식 (안주류 - 시간 비례 분담)
  - 🍺 일반 주류 (소주·병맥주 - 음주자끼리 시간 비례)
  - 🥤 음료수 (개수 선택)
- 개인 주문 추가 (메뉴 이름 + 금액 직접 입력 → 본인 전액 부담)
- 참여자 현황 실시간 표시

---

## 구현 완료 기능 (엄기환 - 계산 파트)

### 🧮 정산 계산 (`lib/services/fair_settlement_calculator.dart`)
- 음식: 먹은 사람끼리 참석 시간 비례 / 소주·맥주: 마신 사람끼리 참석 시간 비례
- 고가 주류·개인 주문·음료수: 주문한 사람이 수량만큼 부담
- 참석 시간 = max(도착, 시작) ~ min(퇴장, 결제 시각), 자정 넘김 처리
- 영수증 총액 ≠ 항목 합계(할인)면 차이를 각자 부담 비율대로 배분
- 100원 단위 내림, 남은 금액은 룰렛 당첨자 1명 부담(시드 고정으로 결과 불변)
- 음주자 0명인데 술 항목 존재 등 예외 입력은 정산 차단
- 검증: `test/fair_settlement_calculator_test.dart`, 파이썬 참조 구현 `docs/calculator_reference.py`

### 🔗 모임방 → 정산 연결
- 총무: 술자리 시작 후 '영수증으로 정산하기' → 영수증 인식 → 참여자 정보 자동 채움
- 참여자가 모임방에 적은 개인 주문 메뉴명을 영수증 항목과 맞춰 자동 배정

---

## Firestore 데이터 구조

### users 컬렉션
\```
users/{uid}
  - name: String
  - email: String
  - accountNumber: String (은행|예금주|계좌번호)
  - createdAt: Timestamp
\```

### meetings 컬렉션
\```
meetings/{meetingId}
  - name: String
  - code: String (6자리)
  - hostId: String
  - hostName: String
  - status: String (waiting / started)
  - createdAt: Timestamp
  - startedAt: Timestamp
  - members:
      {uid}:
        - name: String
        - joinedAt: Timestamp
        - arrivedAt: Timestamp
        - eatFood: Boolean
        - drinkAlcohol: Boolean
        - drinkSoftDrink: Boolean
        - softDrinkCount: int
        - personalOrders: List [{name, price}]
        - personalTotal: int
        - leftAt: Timestamp (먼저 간 경우만, '먼저 가요' 버튼)
        - isGuest: Boolean
\```

---

## 화면 구조
\```
lib/
├── main.dart
├── firebase_options.dart
├── screens/
│   ├── login_screen.dart        # 로그인
│   ├── signup_screen.dart       # 회원가입
│   ├── home_screen.dart         # 홈 (모임 생성·참여)
│   ├── my_page_screen.dart      # 마이페이지
│   ├── create_meeting_screen.dart  # 모임 생성
│   ├── join_meeting_screen.dart    # 모임 참여
│   ├── guest_join_screen.dart      # 게스트 참여
│   └── meeting_room_screen.dart    # 모임 방
└── services/
    └── auth_service.dart        # Firebase Auth·Firestore
\```

---



## Firebase 접근 권한
별도 설정 없이 clone 후 바로 실행 가능합니다.
Firebase 콘솔 직접 접근이 필요하면 고상혁에게 구글 이메일 알려주세요.
- 프로젝트: fair-split
- Auth: 이메일·비밀번호 활성화
- Firestore: 서울 리전 (asia-northeast3)

---

## 개발 일정
| 주차 | 고상혁 (서버) |
|------|--------------|
| 7주 | 로그인·프로필 ✅ |
| 7주 | 모임 생성·코드 참여 ✅ |
| 11주 | 송금 상태 동기화 |
| 12주 | 모임 이력 |
