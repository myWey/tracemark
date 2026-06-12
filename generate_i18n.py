import os
import json

base_dir = "/Users/zerohsueh/Gemini/screenshot/Sources/Screenshot/Resources"
os.makedirs(base_dir, exist_ok=True)

langs = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]

translations = {
    "历史记录": {"en": "History", "zh-Hans": "历史记录", "zh-Hant": "歷史記錄", "ja": "履歴", "ko": "기록"},
    "偏好设置": {"en": "Preferences", "zh-Hans": "偏好设置", "zh-Hant": "偏好設定", "ja": "環境設定", "ko": "환경설정"},
    "跟随系统": {"en": "System Default", "zh-Hans": "跟随系统", "zh-Hant": "跟隨系統", "ja": "システムデフォルト", "ko": "시스템 기본값"},
    "全局快捷键": {"en": "Global Shortcuts", "zh-Hans": "全局快捷键", "zh-Hant": "全域快捷鍵", "ja": "グローバルショートカット", "ko": "글로벌 단축키"},
    "截图快捷键:": {"en": "Screenshot Shortcut:", "zh-Hans": "截图快捷键:", "zh-Hant": "截圖快捷鍵:", "ja": "スクリーンショットのショートカット:", "ko": "스크린샷 단축키:"},
    "请按下新快捷键...": {"en": "Press new shortcut...", "zh-Hans": "请按下新快捷键...", "zh-Hant": "請按下新快捷鍵...", "ja": "新しいショートカットを押してください...", "ko": "새 단축키를 누르세요..."},
    "快捷键冲突或无效，请尝试其他组合。": {"en": "Shortcut conflict or invalid, please try another.", "zh-Hans": "快捷键冲突或无效，请尝试其他组合。", "zh-Hant": "快捷鍵衝突或無效，請嘗試其他組合。", "ja": "ショートカットが競合または無効です。別の組み合わせをお試しください。", "ko": "단축키 충돌 또는 유효하지 않습니다. 다른 조합을 시도해 보세요."},
    "点击上方按钮后直接按下组合键即可设置。": {"en": "Click the button above and press keys to set.", "zh-Hans": "点击上方按钮后直接按下组合键即可设置。", "zh-Hant": "點擊上方按鈕後直接按下組合鍵即可設置。", "ja": "上のボタンをクリックして、キーを押して設定してください。", "ko": "위의 버튼을 클릭하고 키를 눌러 설정하십시오."},
    "注意：部分快捷键（如 Cmd+Space）被 macOS 系统全局保留，录制时若无反应请更换组合。": {"en": "Note: Some shortcuts (e.g. Cmd+Space) are reserved by macOS. If no response, please use another combination.", "zh-Hans": "注意：部分快捷键（如 Cmd+Space）被 macOS 系统全局保留，录制时若无反应请更换组合。", "zh-Hant": "注意：部分快捷鍵（如 Cmd+Space）被 macOS 系統全域保留，錄製時若無反應請更換組合。", "ja": "注意: Cmd+Spaceなどの一部のショートカットはmacOSで予約されています。反応がない場合は別の組み合わせをご使用ください。", "ko": "참고: Cmd+Space와 같은 일부 단축키는 macOS에 예약되어 있습니다. 반응이 없으면 다른 조합을 사용하세요."},
    "多语言支持": {"en": "Multilingual Support", "zh-Hans": "多语言支持", "zh-Hant": "多語言支援", "ja": "多言語サポート", "ko": "다국어 지원"},
    "显示语言:": {"en": "Display Language:", "zh-Hans": "显示语言:", "zh-Hant": "顯示語言:", "ja": "表示言語:", "ko": "표시 언어:"},
    "TraceMark 默认跟随您的 macOS 系统语言。支持实时切换多种语言。": {"en": "TraceMark defaults to your macOS system language. Real-time language switching is supported.", "zh-Hans": "TraceMark 默认跟随您的 macOS 系统语言。支持实时切换多种语言。", "zh-Hant": "TraceMark 預設跟隨您的 macOS 系統語言。支援即時切換多種語言。", "ja": "TraceMarkはmacOSのシステム言語にデフォルト設定されています。リアルタイムでの言語切り替えに対応しています。", "ko": "TraceMark는 macOS 시스템 언어를 기본으로 따릅니다. 실시간 언어 전환을 지원합니다."},
    
    # Tool names
    "矩形": {"en": "Rectangle", "zh-Hans": "矩形", "zh-Hant": "矩形", "ja": "長方形", "ko": "직사각형"},
    "实心矩形": {"en": "Filled Rectangle", "zh-Hans": "实心矩形", "zh-Hant": "實心矩形", "ja": "塗りつぶし長方形", "ko": "채워진 직사각형"},
    "圆形": {"en": "Circle", "zh-Hans": "圆形", "zh-Hant": "圓形", "ja": "円", "ko": "원"},
    "直线": {"en": "Line", "zh-Hans": "直线", "zh-Hant": "直線", "ja": "直線", "ko": "선"},
    "箭头": {"en": "Arrow", "zh-Hans": "箭头", "zh-Hant": "箭頭", "ja": "矢印", "ko": "화살표"},
    "文字": {"en": "Text", "zh-Hans": "文字", "zh-Hant": "文字", "ja": "テキスト", "ko": "텍스트"},
    "序号文字": {"en": "Numbered Text", "zh-Hans": "序号文字", "zh-Hant": "序號文字", "ja": "番号付きテキスト", "ko": "번호가 매겨진 텍스트"},
    "计数器": {"en": "Counter", "zh-Hans": "计数器", "zh-Hant": "計數器", "ja": "カウンター", "ko": "카운터"},
    "画笔": {"en": "Pencil", "zh-Hans": "画笔", "zh-Hant": "畫筆", "ja": "鉛筆", "ko": "연필"},
    "荧光笔": {"en": "Highlighter", "zh-Hans": "荧光笔", "zh-Hant": "螢光筆", "ja": "蛍光ペン", "ko": "형광펜"},
    "模糊": {"en": "Blur", "zh-Hans": "模糊", "zh-Hant": "模糊", "ja": "ぼかし", "ko": "흐림"},
    "马赛克": {"en": "Mosaic", "zh-Hans": "马赛克", "zh-Hant": "馬賽克", "ja": "モザイク", "ko": "모자이크"},
    "聚焦": {"en": "Spotlight", "zh-Hans": "聚焦", "zh-Hant": "聚焦", "ja": "スポットライト", "ko": "스포트라이트"},
    "清空屏幕": {"en": "Clear Screen", "zh-Hans": "清空屏幕", "zh-Hant": "清空螢幕", "ja": "画面をクリア", "ko": "화면 지우기"},
    "固定窗口": {"en": "Pin Window", "zh-Hans": "固定窗口", "zh-Hant": "固定視窗", "ja": "ウィンドウを固定", "ko": "창 고정"},
    "保存并退出": {"en": "Save & Exit", "zh-Hans": "保存并退出", "zh-Hant": "儲存並退出", "ja": "保存して終了", "ko": "저장 및 종료"},
    
    # App menu
    "区域截图 (Ctrl + Cmd + A)": {"en": "Area Screenshot (Ctrl + Cmd + A)", "zh-Hans": "区域截图 (Ctrl + Cmd + A)", "zh-Hant": "區域截圖 (Ctrl + Cmd + A)", "ja": "範囲スクリーンショット (Ctrl + Cmd + A)", "ko": "영역 스크린샷 (Ctrl + Cmd + A)"},
    "关闭所有贴图": {"en": "Close All Pins", "zh-Hans": "关闭所有贴图", "zh-Hant": "關閉所有貼圖", "ja": "すべてのピンを閉じる", "ko": "모든 핀 닫기"},
    "退出": {"en": "Quit", "zh-Hans": "退出", "zh-Hant": "退出", "ja": "終了", "ko": "종료"},
    "历史标注再编辑": {"en": "Edit Previous Annotation", "zh-Hans": "历史标注再编辑", "zh-Hant": "歷史標註再編輯", "ja": "以前の注釈を編集", "ko": "이전 주석 편집"},
    "标注与编辑": {"en": "Annotation & Edit", "zh-Hans": "标注与编辑", "zh-Hant": "標註與編輯", "ja": "注釈と編集", "ko": "주석 및 편집"},
    
    # History
    "今天": {"en": "Today", "zh-Hans": "今天", "zh-Hant": "今天", "ja": "今日", "ko": "오늘"},
    "昨天": {"en": "Yesterday", "zh-Hans": "昨天", "zh-Hant": "昨天", "ja": "昨日", "ko": "어제"},
    "更早": {"en": "Earlier", "zh-Hans": "更早", "zh-Hant": "更早", "ja": "以前", "ko": "이전"},
    "历史记录": {"en": "History", "zh-Hans": "历史记录", "zh-Hant": "歷史記錄", "ja": "履歴", "ko": "기록"},
    "偏好设置": {"en": "Preferences", "zh-Hans": "偏好设置", "zh-Hant": "偏好設定", "ja": "環境設定", "ko": "환경설정"}
}

for lang in langs:
    lproj_path = os.path.join(base_dir, f"{lang}.lproj")
    os.makedirs(lproj_path, exist_ok=True)
    
    strings_file = os.path.join(lproj_path, "Localizable.strings")
    with open(strings_file, "w", encoding="utf-8") as f:
        for k, v in translations.items():
            f.write(f'"{k}" = "{v[lang]}";\n')
print("Generated strings")
