# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Xcode 경로 설정 (최초 1회)
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Release 아카이브 빌드
xcodebuild -project AxlFile.xcodeproj -scheme AxlFile -configuration Release \
  -archivePath build/AxlFile.xcarchive archive CODE_SIGN_IDENTITY="-"

# DMG 생성 (배경 이미지 + 드래그-to-Applications 설치 방식)
APP=$(find build/AxlFile.xcarchive -name "AxlFile.app" -type d | head -1)

# 배경 이미지 생성 (Swift)
swift /tmp/make_dmg_bg.swift   # /tmp/dmg_background.png 생성

# 스테이징 구성
rm -rf build/dmg_staging && mkdir -p build/dmg_staging/.background
cp /tmp/dmg_background.png build/dmg_staging/.background/background.png
cp -R "$APP" build/dmg_staging/
ln -s /Applications build/dmg_staging/Applications

# 읽기-쓰기 DMG 생성 후 마운트
hdiutil create -volname "AxlFile" -srcfolder build/dmg_staging -ov -format UDRW -size 200m build/AxlFile_rw.dmg
MOUNT=$(hdiutil attach build/AxlFile_rw.dmg -readwrite -noverify -noautoopen 2>&1 | awk '/\/Volumes/ {print $NF}')

# Finder 윈도우 레이아웃 (배경, 아이콘 위치)
osascript << 'APPLESCRIPT'
tell application "Finder"
    tell disk "AxlFile"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 940, 460}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "AxlFile.app" to {150, 185}
        set position of item "Applications" to {390, 185}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

chmod -Rf go-w "$MOUNT"
hdiutil detach "$MOUNT" -force
hdiutil convert build/AxlFile_rw.dmg -format UDZO -o build/AxlFile.dmg -ov
rm -f build/AxlFile_rw.dmg && rm -rf build/dmg_staging
```

테스트 타겟 없음. Xcode에서 Cmd+R로 Debug 빌드 실행.

## Architecture

Nexus File 스타일 macOS 듀얼패널 파일 매니저. SwiftUI + `@Observable`.

### 상태 계층

```
AppState (@Observable)          — 앱 전체 싱글턴, @Environment로 주입
  ├── leftPane / rightPane: PaneState   — 패널별 탭 목록
  │     └── tabs: [TabInfo]             — 탭별 현재 디렉토리·파일 목록·커서
  │           └── files: [FileItem]     — 표시 파일 (displayFiles()로 정렬)
  └── 작업 상태 (isWorking, workProgress 등)
```

- `AppState`가 navigate/loadTab/복사/이동/삭제 등 모든 파일 작업을 담당
- `TabInfo.displayFiles(showHidden:)` — 정렬 + `..` 항목 prepend 후 반환
- `TabInfo.driveCursorIndex` — 드라이브 목록 커서 (cursorID와 같은 객체에서 관리해야 SwiftUI가 원자적으로 렌더)

### 뷰 계층

```
ContentView
  └── DualPaneView          — 좌우 패널을 드래그 가능한 분할선으로 배치
        └── PaneView (×2)   — 탭바 / 경로바 / 파일목록 / 드라이브바 / 파일정보바
              └── FileListView  — 파일 수에 따라 1~4열 자동 전환
                    ├── LazyVStack (1~2열): FileRowView (상세)
                    └── LazyVGrid  (3~4열): FileGridCellView (컴팩트)
```

### 컬럼 전환 기준 (`FileListView.columnCount`)
| 파일 수 | 열 수 | 헤더 | 뷰 타입 |
|---------|-------|------|---------|
| ≤50 | 1 | O | FileRowView |
| 51–150 | 2 | O | FileRowView |
| 151–300 | 3 | X | FileGridCellView |
| 301+ | 4 | X | FileGridCellView |

### SFTP

`SFTPClient` — SSH ControlMaster로 연결 유지. `scp` / `ssh` 프로세스를 직접 실행.  
업로드/다운로드 시 디렉토리를 재귀 열거해 파일 단위로 전송 (진행 표시 목적).

### 파일 작업 흐름

- 로컬 복사/이동: `FileOperationManager` (actor) — 파일 단위 열거 후 비동기 처리
- 완료·취소 시 모두 대상 패널 `reload()` 호출
- 작업 진행: `AppState.workCurrentFile / workFileCount / workTotalCount / workProgress`

## 주요 파일

| 파일 | 역할 |
|------|------|
| `Models.swift` | FileItem, TabInfo, PaneState, SortField, PaneID |
| `AppState.swift` | 모든 파일 작업·네비게이션·SFTP 전송 로직 |
| `FileListView.swift` | 파일 목록 UI, 키보드 핸들링, 드라이브 목록 |
| `PaneView.swift` | 경로바, 탭바, 폴더정보바, VolumeInfo/DriveRowView |
| `FileOperations.swift` | 로컬 복사/이동/삭제 actor |
| `FTPClient.swift` | SFTP 연결·전송 (scp/ssh 래퍼) |
| `Theme.swift` | `NX` 네임스페이스에 모든 색상 상수 |

## 색상 (Theme.swift `NX`)

선택: `#505050` / 커서: `#1E3D6B` / 커서+선택: `#3468B0`  
폴더명: `#C8C8C8` / 파일명: `#C8C8C8` / 드라이브명: `#4A9EFF`

## 키보드 단축키

| 키 | 동작 |
|----|------|
| ↑↓ | 1~2열: 1칸, 3~4열: columnCount칸 이동 |
| ←→ | 3~4열 모드에서 1칸 이동 |
| Shift+↑↓ | 범위 선택 |
| Shift+Home/End | 처음/끝까지 선택 |
| Space | 토글 선택 후 다음으로 |
| Backspace | 상위 폴더 (이전 폴더 커서 복원) |
| Tab | 반대 패널로 포커스 이동 |
| F2 | 이름 변경 |
| F3 | 반대 패널로 복사 |
| F4 | 반대 패널로 이동 |
| F5 | 새로고침 |
| F7 | 새 폴더 |
| F8 / fn+Del | 삭제 |
| F9 | SFTP 연결 |
