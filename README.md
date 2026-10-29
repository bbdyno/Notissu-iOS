# 노티쓔 (Notissu) — iOS

숭실대학교 학부·대학원·학교 게시판의 공지를 한곳에 모아 보는 앱입니다.

![License](https://img.shields.io/badge/license-Apache%202.0-red.svg?style=flat)
![Version](https://img.shields.io/badge/version-3.0-blue.svg?style=flat)
![iOS](https://img.shields.io/badge/iOS-17.0%2B-green.svg?style=flat)

- 앱스토어: https://apps.apple.com/kr/app/notissu/id1488050194
- 소개·개인정보 처리방침·지원: https://bbdyno.github.io/Notissu-Site/

## 무엇을 하나요

- **소식:** 구독한 게시판의 글을 날짜순으로 한 화면에 모읍니다. 안 읽은 글에 점이 찍히고, 고정 공지는 따로 묶습니다.
- **마감 표시:** 제목에 적힌 마감일("~11/6(금) 15시" 등)을 찾아 남은 날을 보여 줍니다.
- **본문:** 게시판·등록 부서·날짜를 정리해 보여 주고, 첨부파일을 앱 안에서 엽니다. 글을 저장해 둘 수 있습니다.
- **게시판 101곳:** 학부 55곳, 대학원 38곳, 학교 공통 8곳.
- **넓은 화면:** 아이패드와 펼친 아이폰 듀오에서는 목록과 본문을 나란히 봅니다.

## 짜임

| 위치 | 내용 |
| --- | --- |
| `SoongsilNotice/` | 앱(SwiftUI). `UI/` 화면, `Store/` 상태·저장, `Ads/` 광고 |
| `Packages/NoticeKit/` | 게시판 설정만으로 공지를 모으는 스위프트 패키지 |
| `Packages/NoticeKit/Sources/NoticeKit/Resources/boards.json` | 게시판 101곳의 엔진·주소 설정 |
| `Packages/NoticeKit/Sources/board-check/` | 모든 게시판을 실제로 불러 보는 점검 도구 |
| `.github/workflows/board-check.yml` | 매일 아침 모든 게시판 점검 |
| `tooling/asc.rb` | 앱스토어 커넥트 판·문구·스크린샷·빌드·심사 제출 |
| `store/` | 판별 스토어 문구와 스크린샷 |

게시판 설정은 앱에 들어 있는 것을 기본으로 쓰고, 이 저장소 `master`의 `boards.json`이 더 새 판이면 받아 씁니다. 학과 사이트 주소가 바뀌어도 이 파일만 고치면 앱을 업데이트하지 않고 이어집니다.

## 빌드와 시험

```bash
open SoongsilNotice.xcodeproj
```

```bash
cd Packages/NoticeKit && swift test
```

```bash
cd Packages/NoticeKit && swift run -c release board-check --report board-check.md
```

제출 전에는 출시 설정으로 빌드한 앱을 직접 켜서 목록이 뜨는지 확인합니다.

## 만든 사람

- 김태인 — iOS 개발 ([della.kimko@gmail.com](mailto:della.kimko@gmail.com))
- 김봉균 — iOS 개발(기여)

2.x까지는 [ju-djangun/Notissu](https://github.com/ju-djangun/Notissu)에서 관리했습니다. 3.0부터 이 저장소에서 이어 갑니다.

## 라이선스

Apache 2.0
