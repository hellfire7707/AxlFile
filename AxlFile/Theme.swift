import SwiftUI

// Nexus File 스타일 다크 컬러 팔레트
enum NX {
    // ── Backgrounds ──────────────────────────────────
    static let bg           = Color(hex: "#1C1C1C")  // 윈도우 배경
    static let listBg       = Color(hex: "#000000")  // 파일 목록 배경
    static let rowEven      = Color(hex: "#000000")  // 짝수 행
    static let rowOdd       = Color(hex: "#050505")  // 홀수 행
    static let headerBg     = Color(hex: "#2A2A2A")  // 컬럼 헤더
    static let tabBarBg     = Color(hex: "#181818")  // 탭 바
    static let tabActive    = Color(hex: "#363636")  // 활성 탭
    static let tabInactive  = Color(hex: "#1E1E1E")  // 비활성 탭
    static let activePaneTab = Color(hex: "#1A3B6E") // 활성 패널 탭 배경
    static let pathBg       = Color(hex: "#222222")  // 경로 바
    static let infoBg       = Color(hex: "#1C1C1C")  // 정보 바
    static let dividerBg    = Color(hex: "#262626")  // 가운데 구분선
    static let fkeyBg       = Color(hex: "#1A1A1A")  // F키 바
    static let fkeyBtnBg    = Color(hex: "#333333")  // F키 버튼
    static let fkeyBtnBorder = Color(hex: "#4A4A4A") // F키 버튼 테두리

    // ── Selections ───────────────────────────────────
    static let selected     = Color(hex: "#8B008B")  // 선택 (마젠타)
    static let selectedText = Color(hex: "#FFFFFF")  // 선택된 행 텍스트
    static let cursor       = Color(hex: "#1E3D6B")  // 커서 (다크 블루)
    static let cursorText   = Color(hex: "#E8E8E8")  // 커서 행 텍스트
    static let activeBorder = Color(hex: "#0066CC")  // 활성 패널 상단선

    // ── Text ─────────────────────────────────────────
    static let folderText   = Color(hex: "#D4AA00")  // 폴더 이름 (황금)
    static let fileText     = Color(hex: "#C8C8C8")  // 파일 이름
    static let extText      = Color(hex: "#707070")  // 확장자
    static let sizeText     = Color(hex: "#909090")  // 크기
    static let dateText     = Color(hex: "#787878")  // 날짜
    static let attrText     = Color(hex: "#505050")  // 속성
    static let headerText   = Color(hex: "#909090")  // 헤더
    static let tabText      = Color(hex: "#B0B0B0")  // 탭 텍스트
    static let pathText     = Color(hex: "#C0C0C0")  // 경로 텍스트
    static let infoText     = Color(hex: "#909090")  // 정보 바 텍스트
    static let fkeyText     = Color(hex: "#B0B0B0")  // F키 레이블
    static let fkeyNum      = Color(hex: "#4A80C8")  // F키 숫자 (파랑)

    // ── Icons ────────────────────────────────────────
    static let folderIcon   = Color(hex: "#C8A000")  // 폴더 아이콘 (황금)
    static let imgIcon      = Color(hex: "#A06030")  // 이미지 아이콘
    static let videoIcon    = Color(hex: "#7040A0")  // 동영상 아이콘
    static let audioIcon    = Color(hex: "#904060")  // 음악 아이콘
    static let pdfIcon      = Color(hex: "#A02020")  // PDF 아이콘
    static let archIcon     = Color(hex: "#A08020")  // 압축 아이콘
    static let codeIcon     = Color(hex: "#208040")  // 코드 아이콘
    static let fileIcon     = Color(hex: "#606060")  // 기타 파일 아이콘

    // ── Borders / Separators ─────────────────────────
    static let separator    = Color(hex: "#383838")
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var val: UInt64 = 0
        Scanner(string: h).scanHexInt64(&val)
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8)  & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}
