import Foundation

/// Idiomas da interface. O português é o texto-fonte (as chaves da tabela abaixo).
enum Lang: String, CaseIterable {
    case en, pt, de, es, zh

    var nativeName: String {
        switch self {
        case .en: "English"
        case .pt: "Português"
        case .de: "Deutsch"
        case .es: "Español"
        case .zh: "中文"
        }
    }

    /// "Deutsch (Alemão)": nome nativo + nome no idioma atual da interface.
    /// O idioma atual aparece só com o nome nativo.
    var pickerName: String {
        let current = L10n.current
        guard self != current,
              let translated = current.locale.localizedString(forLanguageCode: rawValue) else { return nativeName }
        return "\(nativeName) (\(translated.prefix(1).uppercased() + translated.dropFirst()))"
    }

    var locale: Locale {
        switch self {
        case .en: Locale(identifier: "en_US")
        case .pt: Locale(identifier: "pt_BR")
        case .de: Locale(identifier: "de_DE")
        case .es: Locale(identifier: "es_ES")
        case .zh: Locale(identifier: "zh_Hans_CN")
        }
    }

    /// Posição na tabela de traduções (en, de, es, zh)
    fileprivate var column: Int? {
        switch self {
        case .pt: nil
        case .en: 0
        case .de: 1
        case .es: 2
        case .zh: 3
        }
    }
}

enum L10n {
    nonisolated(unsafe) private static var cachedSetting: String?
    nonisolated(unsafe) private static var cachedLang: Lang = .en

    /// "auto" segue o sistema; senão, o código do idioma escolhido nos Ajustes
    static var current: Lang {
        let setting = UserDefaults.standard.string(forKey: "language") ?? "auto"
        if setting != cachedSetting {
            cachedSetting = setting
            cachedLang = Lang(rawValue: setting) ?? systemLanguage
        }
        return cachedLang
    }

    static var locale: Locale { current.locale }

    /// Primeiro idioma preferido do macOS que temos (pt-PT → pt, zh-Hant → zh); senão inglês
    static var systemLanguage: Lang {
        for id in Locale.preferredLanguages {
            if let lang = Lang(rawValue: String(id.prefix(2)).lowercased()) { return lang }
        }
        return .en
    }

    fileprivate static func translate(_ key: String) -> String {
        guard let col = current.column else { return key }
        return table[key]?[col] ?? key
    }
}

/// Texto da interface no idioma atual
func L(_ key: String) -> String { L10n.translate(key) }

/// Texto com valores: L("%d núcleos", 10)
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.translate(key), locale: L10n.locale, arguments: args)
}

// MARK: Traduções: [inglês, alemão, espanhol, chinês simplificado]

private let table: [String: [String]] = [
    // Abas e navegação
    "Sistema": ["System", "System", "Sistema", "系统"],
    "Clipboard": ["Clipboard", "Ablage", "Portapapeles", "剪贴板"],
    "Ações": ["Actions", "Aktionen", "Acciones", "操作"],
    "Notas": ["Notes", "Notizen", "Notas", "笔记"],
    "Ajustes": ["Settings", "Einstellungen", "Ajustes", "设置"],
    "Ajustes…": ["Settings…", "Einstellungen…", "Ajustes…", "设置…"],
    "Voltar": ["Back", "Zurück", "Atrás", "返回"],
    "Sair do Menew": ["Quit Menew", "Menew beenden", "Salir de Menew", "退出 Menew"],

    // Sistema
    "Ligado há": ["Uptime", "Laufzeit", "Encendido hace", "已运行"],
    "Temperatura": ["Temperature", "Temperatur", "Temperatura", "温度"],
    "%d núcleos": ["%d cores", "%d Kerne", "%d núcleos", "%d 核"],
    "Memória": ["Memory", "Speicher", "Memoria", "内存"],
    "%@ de %@": ["%@ of %@", "%@ von %@", "%@ de %@", "%@ / %@"],
    "Disco": ["Disk", "Festplatte", "Disco", "磁盘"],
    "%@ livres": ["%@ free", "%@ frei", "%@ libres", "可用 %@"],
    "Bateria": ["Battery", "Batterie", "Batería", "电池"],
    "Processador": ["Processor", "Prozessor", "Procesador", "处理器"],
    "últimos 2 min": ["last 2 min", "letzte 2 Min.", "últimos 2 min", "最近 2 分钟"],
    "em uso": ["in use", "belegt", "en uso", "使用中"],
    "Internet": ["Internet", "Internet", "Internet", "网络"],
    "Download": ["Download", "Download", "Descarga", "下载"],
    "Upload": ["Upload", "Upload", "Subida", "上传"],
    "IP local": ["Local IP", "Lokale IP", "IP local", "本地 IP"],
    "IP público": ["Public IP", "Öffentliche IP", "IP pública", "公网 IP"],
    "Quer saber a velocidade real da sua conexão?": ["Want to know your real connection speed?", "Wie schnell ist deine Verbindung wirklich?", "¿Quieres saber la velocidad real de tu conexión?", "想知道你的真实网速吗？"],
    "Testar": ["Test", "Testen", "Probar", "测速"],
    "Medindo velocidade… leva uns 20 segundos": ["Measuring speed… takes about 20 seconds", "Messe Geschwindigkeit… dauert etwa 20 Sekunden", "Midiendo velocidad… tarda unos 20 segundos", "正在测速…大约需要 20 秒"],
    "Não deu para medir agora.": ["Couldn't measure right now.", "Messung gerade nicht möglich.", "No se pudo medir ahora.", "暂时无法测速。"],
    "Tentar de novo": ["Try again", "Erneut versuchen", "Reintentar", "重试"],
    "Latência": ["Latency", "Latenz", "Latencia", "延迟"],
    "Testar de novo": ["Test again", "Erneut testen", "Probar de nuevo", "重新测速"],
    "Responsividade baixa": ["Low responsiveness", "Geringe Reaktionsfähigkeit", "Capacidad de respuesta baja", "响应性低"],
    "Responsividade média": ["Medium responsiveness", "Mittlere Reaktionsfähigkeit", "Capacidad de respuesta media", "响应性中等"],
    "Responsividade alta": ["High responsiveness", "Hohe Reaktionsfähigkeit", "Capacidad de respuesta alta", "响应性高"],
    "Dispositivos": ["Devices", "Geräte", "Dispositivos", "设备"],
    "E": ["L", "L", "I", "左"],
    "D": ["R", "R", "D", "右"],
    "Estojo": ["Case", "Etui", "Estuche", "充电盒"],
    "Quem está usando a CPU": ["Top CPU usage", "Größte CPU-Nutzer", "Quién usa la CPU", "CPU 占用最高"],
    "Monitor de Atividade": ["Activity Monitor", "Aktivitätsanzeige", "Monitor de Actividad", "活动监视器"],
    "Carregando…": ["Loading…", "Wird geladen…", "Cargando…", "加载中…"],
    "cheia em %@": ["full in %@", "voll in %@", "llena en %@", "%@ 后充满"],
    "carregando": ["charging", "lädt", "cargando", "正在充电"],
    "na tomada": ["plugged in", "am Netz", "enchufado", "已接通电源"],
    "restam %@": ["%@ left", "noch %@", "quedan %@", "剩余 %@"],
    "na bateria": ["on battery", "Batteriebetrieb", "con batería", "使用电池"],
    "Normal": ["Normal", "Normal", "Normal", "正常"],
    "Morno": ["Warm", "Warm", "Tibio", "偏热"],
    "Quente": ["Hot", "Heiß", "Caliente", "很热"],
    "Crítico": ["Critical", "Kritisch", "Crítico", "过热"],

    // Ações
    "Limpeza": ["Cleaning", "Reinigung", "Limpieza", "清洁"],
    "Limpar teclado": ["Clean keyboard", "Tastatur reinigen", "Limpiar teclado", "清洁键盘"],
    "trava por 2 min": ["locks for 2 min", "sperrt 2 Min.", "bloquea 2 min", "锁定 2 分钟"],
    "Libere o Menew em Acessibilidade": ["Allow Menew in Accessibility", "Erlaube Menew unter Bedienungshilfen", "Permite Menew en Accesibilidad", "请在“辅助功能”中允许 Menew"],
    "Limpar tela": ["Clean screen", "Bildschirm reinigen", "Limpiar pantalla", "清洁屏幕"],
    "tela preta": ["black screen", "schwarzer Bildschirm", "pantalla negra", "黑屏"],
    "Esvaziar lixeira": ["Empty Trash", "Papierkorb leeren", "Vaciar papelera", "清倒废纸篓"],
    "Energia": ["Power", "Energie", "Energía", "电源"],
    "Manter acordado": ["Keep awake", "Wach halten", "Mantener activo", "保持唤醒"],
    "ligado": ["on", "an", "activado", "已开启"],
    "Acordado 1h": ["Awake 1h", "1 Std. wach", "Activo 1 h", "唤醒 1 小时"],
    "Acordado por 1 hora": ["Awake for 1 hour", "1 Stunde wach", "Activo durante 1 hora", "将保持唤醒 1 小时"],
    "Bloquear tela": ["Lock screen", "Bildschirm sperren", "Bloquear pantalla", "锁定屏幕"],
    "Finder": ["Finder", "Finder", "Finder", "访达"],
    "Arquivos ocultos": ["Hidden files", "Versteckte Dateien", "Archivos ocultos", "隐藏文件"],
    "Ocultar mesa": ["Hide desktop", "Schreibtisch aus", "Ocultar escritorio", "隐藏桌面"],
    "Ejetar discos": ["Eject disks", "Volumes auswerfen", "Expulsar discos", "推出磁盘"],
    "Ferramentas": ["Tools", "Werkzeuge", "Herramientas", "工具"],
    "Modo escuro": ["Dark mode", "Dunkelmodus", "Modo oscuro", "深色模式"],
    "Print": ["Screenshot", "Bildschirmfoto", "Captura", "截图"],
    "vai pro clipboard": ["to clipboard", "in die Ablage", "al portapapeles", "存入剪贴板"],
    "Conta-gotas": ["Color picker", "Pipette", "Cuentagotas", "取色器"],
    "copia o hex": ["copies hex", "kopiert Hex", "copia el hex", "复制 HEX"],
    "Limpar formatação": ["Clear formatting", "Formatierung weg", "Quitar formato", "清除格式"],
    "Monitor": ["Monitor", "Monitor", "Monitor", "监视器"],
    "Terminal": ["Terminal", "Terminal", "Terminal", "终端"],

    // Limpeza
    "Teclado bloqueado": ["Keyboard locked", "Tastatur gesperrt", "Teclado bloqueado", "键盘已锁定"],
    "Pode limpar à vontade. Nenhuma tecla vai funcionar.": ["Clean away. No key will work.", "Putz ruhig los. Keine Taste funktioniert.", "Limpia tranquilo. Ninguna tecla funcionará.", "尽管清洁吧，所有按键都不会生效。"],
    "Desbloquear": ["Unlock", "Entsperren", "Desbloquear", "解锁"],
    "Destrava sozinho em %@": ["Unlocks automatically in %@", "Entsperrt automatisch in %@", "Se desbloquea solo en %@", "%@ 后自动解锁"],
    "Tela de limpeza": ["Cleaning screen", "Reinigungsbildschirm", "Pantalla de limpieza", "清洁屏幕"],
    "Clique duas vezes ou aperte esc para sair": ["Double-click or press esc to exit", "Doppelklicken oder esc drücken zum Beenden", "Haz doble clic o pulsa esc para salir", "双击或按 esc 退出"],

    // Clipboard
    "Histórico do clipboard": ["Clipboard history", "Ablageverlauf", "Historial del portapapeles", "剪贴板历史"],
    "Tudo": ["All", "Alle", "Todo", "全部"],
    "Texto": ["Text", "Text", "Texto", "文本"],
    "Links": ["Links", "Links", "Enlaces", "链接"],
    "Imagens": ["Images", "Bilder", "Imágenes", "图片"],
    "Arquivos": ["Files", "Dateien", "Archivos", "文件"],
    "Fixados": ["Pinned", "Angeheftet", "Fijados", "置顶"],
    "agora": ["now", "jetzt", "ahora", "刚刚"],
    "Buscar no histórico": ["Search history", "Verlauf durchsuchen", "Buscar en el historial", "搜索历史"],
    "Pausado": ["Paused", "Pausiert", "En pausa", "已暂停"],
    "Copie algo para começar": ["Copy something to get started", "Kopiere etwas, um loszulegen", "Copia algo para empezar", "复制点什么开始吧"],
    "Nada encontrado": ["Nothing found", "Nichts gefunden", "Nada encontrado", "未找到内容"],
    "Colar": ["Paste", "Einsetzen", "Pegar", "粘贴"],
    "Colar como texto puro": ["Paste as plain text", "Als reinen Text einsetzen", "Pegar como texto sin formato", "粘贴为纯文本"],
    "Só copiar": ["Copy only", "Nur kopieren", "Solo copiar", "仅复制"],
    "Desafixar": ["Unpin", "Lösen", "Desfijar", "取消置顶"],
    "Fixar": ["Pin", "Anheften", "Fijar", "置顶"],
    "Transformar e copiar": ["Transform and copy", "Umwandeln und kopieren", "Transformar y copiar", "转换并复制"],
    "MAIÚSCULAS": ["UPPERCASE", "GROSSBUCHSTABEN", "MAYÚSCULAS", "全部大写"],
    "minúsculas": ["lowercase", "kleinbuchstaben", "minúsculas", "全部小写"],
    "Primeira Letra Maiúscula": ["Title Case", "Erster Buchstabe Groß", "Primera Letra Mayúscula", "首字母大写"],
    "Remover espaços extras": ["Remove extra spaces", "Überflüssige Leerzeichen entfernen", "Quitar espacios extra", "移除多余空格"],
    "Abrir link": ["Open link", "Link öffnen", "Abrir enlace", "打开链接"],
    "Mostrar no Finder": ["Show in Finder", "Im Finder zeigen", "Mostrar en Finder", "在访达中显示"],
    "Abrir imagem": ["Open image", "Bild öffnen", "Abrir imagen", "打开图片"],
    "Apagar": ["Delete", "Löschen", "Borrar", "删除"],
    "Origem": ["Source", "Quelle", "Origen", "来源"],
    "Desconhecido": ["Unknown", "Unbekannt", "Desconocido", "未知"],
    "Copiado": ["Copied", "Kopiert", "Copiado", "复制时间"],
    "Conteúdo": ["Content", "Inhalt", "Contenido", "内容"],
    "Copiar": ["Copy", "Kopieren", "Copiar", "复制"],
    "O arquivo desta imagem não foi encontrado.": ["This image file could not be found.", "Die Bilddatei wurde nicht gefunden.", "No se encontró el archivo de esta imagen.", "找不到此图片文件。"],
    "Link": ["Link", "Link", "Enlace", "链接"],
    "Abrir no navegador": ["Open in browser", "Im Browser öffnen", "Abrir en el navegador", "在浏览器中打开"],
    "Imagem": ["Image", "Bild", "Imagen", "图片"],
    "1 arquivo": ["1 file", "1 Datei", "1 archivo", "1 个文件"],
    "%d arquivos": ["%d files", "%d Dateien", "%d archivos", "%d 个文件"],
    "%@ e mais %d": ["%@ and %d more", "%@ und %d weitere", "%@ y %d más", "%@ 等 %d 个"],
    "%d caracteres · %d palavras · %d linha": ["%d characters · %d words · %d line", "%d Zeichen · %d Wörter · %d Zeile", "%d caracteres · %d palabras · %d línea", "%d 个字符 · %d 个词 · %d 行"],
    "%d caracteres · %d palavras · %d linhas": ["%d characters · %d words · %d lines", "%d Zeichen · %d Wörter · %d Zeilen", "%d caracteres · %d palabras · %d líneas", "%d 个字符 · %d 个词 · %d 行"],
    "colar": ["paste", "einsetzen", "pegar", "粘贴"],
    "texto puro": ["plain text", "reiner Text", "texto plano", "纯文本"],
    "rápido": ["quick", "schnell", "rápido", "快速"],
    "fixar": ["pin", "anheften", "fijar", "置顶"],
    "apagar": ["delete", "löschen", "borrar", "删除"],
    "%d itens": ["%d items", "%d Einträge", "%d elementos", "%d 条"],

    // Ações do sistema
    "Esvaziar a Lixeira?": ["Empty the Trash?", "Papierkorb leeren?", "¿Vaciar la papelera?", "清倒废纸篓？"],
    "Os itens serão apagados permanentemente.": ["Items will be permanently deleted.", "Die Objekte werden endgültig gelöscht.", "Los elementos se eliminarán permanentemente.", "这些项目将被永久删除。"],
    "Esvaziar": ["Empty", "Leeren", "Vaciar", "清倒"],
    "Cancelar": ["Cancel", "Abbrechen", "Cancelar", "取消"],
    "Nenhum disco para ejetar": ["No disks to eject", "Keine Volumes zum Auswerfen", "No hay discos para expulsar", "没有可推出的磁盘"],
    "%d disco(s) ejetado(s)": ["%d disk(s) ejected", "%d Volume(s) ausgeworfen", "%d disco(s) expulsado(s)", "已推出 %d 个磁盘"],
    "Cor %@ copiada": ["Color %@ copied", "Farbe %@ kopiert", "Color %@ copiado", "已复制颜色 %@"],
    "Clipboard não tem texto": ["Clipboard has no text", "Ablage enthält keinen Text", "El portapapeles no tiene texto", "剪贴板中没有文本"],
    "Formatação removida": ["Formatting removed", "Formatierung entfernt", "Formato eliminado", "已清除格式"],
    "Permita o Menew em Automação nos Ajustes": ["Allow Menew under Automation in Settings", "Erlaube Menew unter Automation in den Einstellungen", "Permite Menew en Automatización en Ajustes", "请在设置的“自动化”中允许 Menew"],

    // Notas
    "Anote qualquer coisa…\nSalva sozinho, fica aqui até você apagar.": ["Write anything…\nIt saves itself and stays here until you delete it.", "Schreib einfach los…\nWird automatisch gespeichert und bleibt, bis du es löschst.", "Escribe lo que quieras…\nSe guarda solo y se queda aquí hasta que lo borres.", "随便写点什么…\n自动保存，直到你删除为止。"],
    "Salvo · %d caracteres": ["Saved · %d characters", "Gespeichert · %d Zeichen", "Guardado · %d caracteres", "已保存 · %d 个字符"],
    "Apagar notas": ["Delete notes", "Notizen löschen", "Borrar notas", "删除笔记"],
    "Apagar todas as notas?": ["Delete all notes?", "Alle Notizen löschen?", "¿Borrar todas las notas?", "删除所有笔记？"],

    // Liberar espaço
    "Liberar espaço": ["Free up space", "Speicher freigeben", "Liberar espacio", "释放空间"],
    "caches e mais": ["caches and more", "Caches und mehr", "cachés y más", "缓存等"],
    "Análise rápida": ["Quick scan", "Schnellanalyse", "Análisis rápido", "快速扫描"],
    "Análise profunda": ["Deep scan", "Tiefenanalyse", "Análisis profundo", "深度扫描"],
    "Caches, logs e arquivos de desenvolvimento. Seguro: os apps recriam o que precisarem.": ["Caches, logs and developer files. Safe: apps recreate whatever they need.", "Caches, Logs und Entwicklerdateien. Sicher: Apps erstellen neu, was sie brauchen.", "Cachés, registros y archivos de desarrollo. Seguro: las apps recrean lo que necesiten.", "缓存、日志和开发文件。安全：应用会按需重新生成。"],
    "Também procura downloads antigos, arquivos grandes e itens do Xcode. Você revisa, e o que for removido vai para a Lixeira.": ["Also looks for old downloads, large files and Xcode leftovers. You review it, and anything removed goes to the Trash.", "Sucht auch alte Downloads, große Dateien und Xcode-Reste. Du prüfst alles, Entferntes landet im Papierkorb.", "También busca descargas antiguas, archivos grandes y restos de Xcode. Tú revisas, y lo eliminado va a la Papelera.", "还会查找旧下载、大文件和 Xcode 残留。由你确认，删除的内容会移到废纸篓。"],
    "Analisando o disco…": ["Scanning your disk…", "Festplatte wird analysiert…", "Analizando el disco…", "正在扫描磁盘…"],
    "Limpando…": ["Cleaning…", "Wird bereinigt…", "Limpiando…", "正在清理…"],
    "Limpar": ["Clean", "Bereinigen", "Limpiar", "清理"],
    "Permitido": ["Allowed", "Erlaubt", "Permitido", "已允许"],
    "Prévia ao vivo": ["Live preview", "Live-Vorschau", "Vista previa en vivo", "实时预览"],
    "Selecionado": ["Selected", "Ausgewählt", "Seleccionado", "已选择"],
    "Liberar %@?": ["Free up %@?", "%@ freigeben?", "¿Liberar %@?", "释放 %@？"],
    "Caches e logs são apagados (os apps recriam). Arquivos seus vão para a Lixeira.": ["Caches and logs are deleted (apps recreate them). Your files go to the Trash.", "Caches und Logs werden gelöscht (Apps erstellen sie neu). Deine Dateien landen im Papierkorb.", "Las cachés y registros se borran (las apps los recrean). Tus archivos van a la Papelera.", "缓存和日志将被删除（应用会重新生成）。你的文件会移到废纸篓。"],
    "%@ liberados": ["%@ freed", "%@ freigegeben", "%@ liberados", "已释放 %@"],
    "Alguns itens em uso podem ter ficado para trás.": ["Some items in use may have been skipped.", "Einige verwendete Objekte wurden evtl. übersprungen.", "Algunos elementos en uso pueden haberse omitido.", "部分正在使用的项目可能被跳过。"],
    "Concluir": ["Done", "Fertig", "Listo", "完成"],
    "Nada para limpar. Tudo em ordem!": ["Nothing to clean. All tidy!", "Nichts zu bereinigen. Alles sauber!", "Nada que limpiar. ¡Todo en orden!", "没有可清理的内容，一切整洁！"],
    "e mais %d": ["and %d more", "und %d weitere", "y %d más", "还有 %d 项"],
    "Apps usando mais memória": ["Apps using the most memory", "Apps mit dem meisten Speicher", "Apps que más memoria usan", "内存占用最高的应用"],
    "Encerrar": ["Quit", "Beenden", "Salir", "退出"],
    "O macOS já gerencia a memória sozinho. Encerrar um app pesado é o que realmente libera espaço.": ["macOS already manages memory on its own. Quitting a heavy app is what actually frees it.", "macOS verwaltet den Speicher selbst. Erst das Beenden einer schweren App gibt ihn wirklich frei.", "macOS ya gestiona la memoria solo. Cerrar una app pesada es lo que realmente la libera.", "macOS 会自动管理内存。退出占用高的应用才能真正释放。"],
    "Caches de apps": ["App caches", "App-Caches", "Cachés de apps", "应用缓存"],
    "Os apps recriam quando precisam": ["Apps recreate them when needed", "Apps erstellen sie bei Bedarf neu", "Las apps los recrean cuando hace falta", "应用会按需重新生成"],
    "Logs": ["Logs", "Logs", "Registros", "日志"],
    "Registros antigos de apps e do sistema": ["Old app and system logs", "Alte App- und Systemprotokolle", "Registros antiguos de apps y del sistema", "旧的应用和系统日志"],
    "Xcode: DerivedData": ["Xcode: DerivedData", "Xcode: DerivedData", "Xcode: DerivedData", "Xcode：DerivedData"],
    "Arquivos de compilação, recriados no próximo build": ["Build files, recreated on next build", "Build-Dateien, beim nächsten Build neu erstellt", "Archivos de compilación, se recrean en el próximo build", "编译文件，下次构建时重新生成"],
    "Simuladores: caches": ["Simulators: caches", "Simulatoren: Caches", "Simuladores: cachés", "模拟器缓存"],
    "Caches dos simuladores do iOS": ["iOS simulator caches", "Caches der iOS-Simulatoren", "Cachés de los simuladores de iOS", "iOS 模拟器缓存"],
    "Caches de desenvolvimento": ["Developer caches", "Entwickler-Caches", "Cachés de desarrollo", "开发缓存"],
    "npm, Gradle e afins": ["npm, Gradle and friends", "npm, Gradle und Co.", "npm, Gradle y similares", "npm、Gradle 等"],
    "Xcode: suporte a dispositivos": ["Xcode: device support", "Xcode: Geräteunterstützung", "Xcode: soporte de dispositivos", "Xcode：设备支持"],
    "Baixado de novo ao conectar o aparelho": ["Downloaded again when you connect the device", "Wird beim Verbinden des Geräts neu geladen", "Se descarga de nuevo al conectar el dispositivo", "连接设备时会重新下载"],
    "Xcode: Archives": ["Xcode: Archives", "Xcode: Archive", "Xcode: Archives", "Xcode：归档"],
    "Builds antigos exportados; revise antes": ["Old exported builds; review first", "Alte exportierte Builds; vorher prüfen", "Builds antiguos exportados; revisa antes", "旧的导出构建，请先确认"],
    "Downloads antigos": ["Old downloads", "Alte Downloads", "Descargas antiguas", "旧下载"],
    "Mais de 90 dias; revise antes": ["Older than 90 days; review first", "Älter als 90 Tage; vorher prüfen", "Más de 90 días; revisa antes", "超过 90 天，请先确认"],
    "Arquivos grandes": ["Large files", "Große Dateien", "Archivos grandes", "大文件"],
    "Mais de 500 MB; revise antes": ["Over 500 MB; review first", "Über 500 MB; vorher prüfen", "Más de 500 MB; revisa antes", "超过 500 MB，请先确认"],

    // Notas (várias, tags, protegidas)
    "Buscar notas": ["Search notes", "Notizen durchsuchen", "Buscar notas", "搜索笔记"],
    "Nova": ["New", "Neu", "Nueva", "新建"],
    "Todas": ["All", "Alle", "Todas", "全部"],
    "Nenhuma nota ainda": ["No notes yet", "Noch keine Notizen", "Aún no hay notas", "还没有笔记"],
    "Nota sem título": ["Untitled note", "Unbenannte Notiz", "Nota sin título", "无标题笔记"],
    "Conteúdo protegido": ["Protected content", "Geschützter Inhalt", "Contenido protegido", "内容已保护"],
    "Proteger com Touch ID": ["Protect with Touch ID", "Mit Touch ID schützen", "Proteger con Touch ID", "使用触控 ID 保护"],
    "Remover proteção": ["Remove protection", "Schutz entfernen", "Quitar protección", "取消保护"],
    "Protegida nas Chaves do macOS": ["Protected in the macOS Keychain", "Im macOS-Schlüsselbund geschützt", "Protegida en el Llavero de macOS", "已在 macOS 钥匙串中保护"],
    "abrir a nota protegida": ["open the protected note", "die geschützte Notiz öffnen", "abrir la nota protegida", "打开受保护的笔记"],
    "Apagar nota": ["Delete note", "Notiz löschen", "Borrar nota", "删除笔记"],
    "Apagar esta nota?": ["Delete this note?", "Diese Notiz löschen?", "¿Borrar esta nota?", "删除这条笔记？"],
    "Ler": ["Read", "Lesen", "Leer", "阅读"],
    "Use #tags no texto para organizar e **negrito**, listas e - [ ] tarefas em Markdown.": ["Use #tags in the text to organize, and Markdown for **bold**, lists and - [ ] tasks.", "Nutze #Tags im Text zum Ordnen und Markdown für **fett**, Listen und - [ ] Aufgaben.", "Usa #etiquetas en el texto para organizar y Markdown para **negrita**, listas y - [ ] tareas.", "在文字中使用 #标签 整理，并用 Markdown 写 **粗体**、列表和 - [ ] 任务。"],
    "Título na primeira linha…\nUse #tags, **negrito**, listas e - [ ] tarefas.": ["Title on the first line…\nUse #tags, **bold**, lists and - [ ] tasks.", "Titel in der ersten Zeile…\nNutze #Tags, **fett**, Listen und - [ ] Aufgaben.", "Título en la primera línea…\nUsa #etiquetas, **negrita**, listas y - [ ] tareas.", "第一行是标题…\n可使用 #标签、**粗体**、列表和 - [ ] 任务。"],

    // Ajuda
    "Ajuda": ["Help", "Hilfe", "Ayuda", "帮助"],
    "Reportar um problema…": ["Report a problem…", "Problem melden…", "Informar de un problema…", "报告问题…"],
    "Sugerir uma ideia…": ["Suggest an idea…", "Idee vorschlagen…", "Sugerir una idea…", "提出建议…"],
    "Ver no GitHub": ["View on GitHub", "Auf GitHub ansehen", "Ver en GitHub", "在 GitHub 上查看"],
    "Abre o GitHub com a versão do app e do macOS já preenchidas. Você revisa antes de enviar.": ["Opens GitHub with the app and macOS versions filled in. You review it before sending.", "Öffnet GitHub mit bereits ausgefüllter App- und macOS-Version. Du prüfst alles vor dem Senden.", "Abre GitHub con las versiones de la app y de macOS ya rellenas. Lo revisas antes de enviar.", "打开 GitHub 并自动填好应用和 macOS 版本，发送前你可以检查。"],

    // Ajustes
    "Aparência": ["Appearance", "Erscheinungsbild", "Apariencia", "外观"],
    "Tema": ["Theme", "Design", "Tema", "主题"],
    "Idioma": ["Language", "Sprache", "Idioma", "语言"],
    "Automático (sistema)": ["Automatic (system)", "Automatisch (System)", "Automático (sistema)", "自动（跟随系统）"],
    "Automático": ["Automatic", "Automatisch", "Automático", "自动"],
    "Claro": ["Light", "Hell", "Claro", "浅色"],
    "Escuro": ["Dark", "Dunkel", "Oscuro", "深色"],
    "Barra de menus": ["Menu bar", "Menüleiste", "Barra de menús", "菜单栏"],
    "Mostrar": ["Show", "Anzeigen", "Mostrar", "显示"],
    "Só o ícone": ["Icon only", "Nur Symbol", "Solo el icono", "仅图标"],
    "CPU + RAM": ["CPU + RAM", "CPU + RAM", "CPU + RAM", "CPU + 内存"],
    "Rede": ["Network", "Netzwerk", "Red", "网络"],
    "CPU + RAM + Rede": ["CPU + RAM + Network", "CPU + RAM + Netzwerk", "CPU + RAM + Red", "CPU + 内存 + 网络"],
    "Abrir ao iniciar o Mac": ["Open at login", "Beim Anmelden öffnen", "Abrir al iniciar sesión", "登录时打开"],
    "Permissões": ["Permissions", "Berechtigungen", "Permisos", "权限"],
    "Acessibilidade": ["Accessibility", "Bedienungshilfen", "Accesibilidad", "辅助功能"],
    "Permitir": ["Allow", "Erlauben", "Permitir", "允许"],
    "Usada para colar automaticamente e para travar o teclado na limpeza.": ["Used to paste automatically and to lock the keyboard while cleaning.", "Wird zum automatischen Einsetzen und zum Sperren der Tastatur beim Reinigen verwendet.", "Se usa para pegar automáticamente y bloquear el teclado al limpiar.", "用于自动粘贴以及清洁时锁定键盘。"],
    "Colar automaticamente ao escolher": ["Paste automatically when picking", "Beim Auswählen automatisch einsetzen", "Pegar automáticamente al elegir", "选择后自动粘贴"],
    "Pausar captura": ["Pause capture", "Aufzeichnung pausieren", "Pausar captura", "暂停记录"],
    "Ignorar senhas (1Password, Keychain…)": ["Ignore passwords (1Password, Keychain…)", "Passwörter ignorieren (1Password, Schlüsselbund…)", "Ignorar contraseñas (1Password, Llavero…)", "忽略密码（1Password、钥匙串…）"],
    "Guardar %d itens": ["Keep %d items", "%d Einträge behalten", "Guardar %d elementos", "保留 %d 条"],
    "Ignorar apps": ["Ignore apps", "Apps ignorieren", "Ignorar apps", "忽略的应用"],
    "bundle IDs separados por vírgula": ["comma-separated bundle IDs", "Bundle-IDs, durch Komma getrennt", "bundle IDs separados por comas", "以逗号分隔的 Bundle ID"],
    "Limpar histórico (mantém fixados)": ["Clear history (keeps pinned)", "Verlauf löschen (Angeheftete bleiben)", "Borrar historial (mantiene fijados)", "清空历史（保留置顶）"],
    "Apagar todo o histórico não fixado?": ["Delete all unpinned history?", "Gesamten nicht angehefteten Verlauf löschen?", "¿Borrar todo el historial no fijado?", "删除所有未置顶的历史记录？"],
    "Apagar itens com mais de": ["Delete items older than", "Einträge löschen nach", "Borrar elementos con más de", "删除早于此时间的条目"],
    "Nunca": ["Never", "Nie", "Nunca", "从不"],
    "1 dia": ["1 day", "1 Tag", "1 día", "1 天"],
    "%d dias": ["%d days", "%d Tagen", "%d días", "%d 天"],
    "Pressione o atalho…": ["Press shortcut…", "Kurzbefehl drücken…", "Pulsa el atajo…", "请按下快捷键…"],
    "Voltar ao padrão": ["Reset to default", "Auf Standard zurücksetzen", "Restablecer", "恢复默认"],
    "Snippets": ["Snippets", "Textbausteine", "Fragmentos", "文本片段"],
    "Snippet": ["Snippet", "Textbaustein", "Fragmento", "文本片段"],
    "Histórico": ["History", "Verlauf", "Historial", "历史"],
    "Novo snippet": ["New snippet", "Neuer Baustein", "Nuevo fragmento", "新建片段"],
    "Editar snippet": ["Edit snippet", "Baustein bearbeiten", "Editar fragmento", "编辑片段"],
    "Editar": ["Edit", "Bearbeiten", "Editar", "编辑"],
    "Título": ["Title", "Titel", "Título", "标题"],
    "Salvar": ["Save", "Sichern", "Guardar", "保存"],
    "Nenhum snippet ainda": ["No snippets yet", "Noch keine Textbausteine", "Aún no hay fragmentos", "还没有文本片段"],
    "Cole com ⌘⇧V → Snippets": ["Paste with ⌘⇧V → Snippets", "Einsetzen mit ⌘⇧V → Textbausteine", "Pega con ⌘⇧V → Fragmentos", "用 ⌘⇧V → 文本片段 粘贴"],
    "Use {date}, {time} e {clipboard} para preencher na hora de colar.": ["Use {date}, {time} and {clipboard} to fill in when pasting.", "{date}, {time} und {clipboard} werden beim Einsetzen ausgefüllt.", "Usa {date}, {time} y {clipboard} para rellenar al pegar.", "粘贴时会自动填入 {date}、{time} 和 {clipboard}。"],
    "Data de hoje": ["Today's date", "Heutiges Datum", "Fecha de hoy", "今天的日期"],
    "Assinatura de e-mail": ["Email signature", "E-Mail-Signatur", "Firma de correo", "邮件签名"],
    "Abraços,\nSeu nome": ["Best,\nYour name", "Viele Grüße\nDein Name", "Saludos,\nTu nombre", "祝好，\n你的名字"],
    "Atualizações": ["Updates", "Updates", "Actualizaciones", "更新"],
    "Procurar atualizações automaticamente": ["Check for updates automatically", "Automatisch nach Updates suchen", "Buscar actualizaciones automáticamente", "自动检查更新"],
    "Procurar agora": ["Check now", "Jetzt suchen", "Buscar ahora", "立即检查"],
    "Procurar atualizações…": ["Check for Updates…", "Nach Updates suchen…", "Buscar actualizaciones…", "检查更新…"],
    "Atalhos": ["Shortcuts", "Kurzbefehle", "Atajos", "快捷键"],
    "Abrir este menu": ["Open this menu", "Dieses Menü öffnen", "Abrir este menú", "打开此菜单"],
    "%@ está usando %d%% da CPU há 2 minutos.": ["%@ has been using %d%% CPU for 2 minutes.", "%@ nutzt seit 2 Minuten %d%% CPU.", "%@ lleva 2 minutos usando el %d%% de la CPU.", "%@ 已连续 2 分钟占用 %d%% 的 CPU。"],
    "20% ou menos, fora da tomada": ["20% or less, unplugged", "20 % oder weniger, ohne Netzteil", "20 % o menos, desenchufado", "未接电源且电量不高于 20%"],
    "A CPU está acima de 90% há 2 minutos.": ["CPU has been above 90% for 2 minutes.", "Die CPU liegt seit 2 Minuten über 90 %.", "La CPU lleva 2 minutos por encima del 90 %.", "CPU 已连续 2 分钟高于 90%。"],
    "A pressão de memória mostra se o Mac precisa de mais memória. Se estiver normal, está tudo bem, mesmo com a memória quase toda usada.": ["Memory pressure tells you whether your Mac needs more memory. If it's normal, you're fine, even when memory looks almost full.", "Der Speicherdruck zeigt, ob dein Mac mehr Speicher braucht. Ist er normal, ist alles gut, auch wenn der Speicher fast voll aussieht.", "La presión de memoria indica si tu Mac necesita más memoria. Si es normal, todo va bien, aunque la memoria parezca casi llena.", "内存压力显示 Mac 是否需要更多内存。只要压力正常就没问题，即使内存看起来快用满了。"],
    "Abrir Ajustes": ["Open Settings", "Einstellungen öffnen", "Abrir Ajustes", "打开设置"],
    "Acima de 90% por 2 minutos": ["Above 90% for 2 minutes", "Über 90 % für 2 Minuten", "Por encima del 90 % durante 2 minutos", "连续 2 分钟高于 90%"],
    "Alertas": ["Alerts", "Hinweise", "Alertas", "提醒"],
    "Apps": ["Apps", "Apps", "Apps", "应用"],
    "As notificações do Menew estão desligadas no macOS.": ["Menew's notifications are turned off in macOS.", "Mitteilungen von Menew sind in macOS ausgeschaltet.", "Las notificaciones de Menew están desactivadas en macOS.", "Menew 的通知已在 macOS 中关闭。"],
    "Assistência recomendada": ["Service recommended", "Service empfohlen", "Se recomienda reparación", "建议维修"],
    "Bateria baixa": ["Low battery", "Batterie schwach", "Batería baja", "电量不足"],
    "CPU alta por muito tempo": ["High CPU for a while", "CPU lange stark ausgelastet", "CPU alta durante mucho tiempo", "CPU 长时间高负载"],
    "Carregador": ["Charger", "Netzteil", "Cargador", "充电器"],
    "Ciclos": ["Cycles", "Zyklen", "Ciclos", "循环次数"],
    "Comprimida": ["Compressed", "Komprimiert", "Comprimida", "已压缩"],
    "Disco quase cheio": ["Disk almost full", "Festplatte fast voll", "Disco casi lleno", "磁盘快满了"],
    "Encerrar %@": ["Quit %@", "%@ beenden", "Salir de %@", "退出 %@"],
    "Forçar encerramento": ["Force Quit", "Sofort beenden", "Forzar salida", "强制退出"],
    "Gráfico da CPU": ["CPU graph", "CPU-Verlauf", "Gráfico de CPU", "CPU 图表"],
    "Memória no limite": ["Memory is running out", "Speicher wird knapp", "Memoria al límite", "内存即将耗尽"],
    "Menos de 10 GB livres": ["Less than 10 GB free", "Weniger als 10 GB frei", "Menos de 10 GB libres", "可用空间少于 10 GB"],
    "Mostrar ao lado do ícone": ["Show next to the icon", "Neben dem Symbol anzeigen", "Mostrar junto al icono", "在图标旁显示"],
    "O Mac está sem memória livre e pode ficar lento. Feche apps que não está usando.": ["Your Mac is out of free memory and may slow down. Quit apps you're not using.", "Dein Mac hat keinen freien Speicher mehr und kann langsam werden. Beende Apps, die du nicht nutzt.", "Tu Mac se quedó sin memoria libre y puede ir lento. Cierra las apps que no uses.", "Mac 的可用内存已耗尽，可能会变慢。请退出不用的应用。"],
    "Pressão alta": ["High pressure", "Hoher Druck", "Presión alta", "压力较高"],
    "Pressão crítica": ["Critical pressure", "Kritischer Druck", "Presión crítica", "压力严重"],
    "Pressão de memória crítica": ["Critical memory pressure", "Kritischer Speicherdruck", "Presión de memoria crítica", "内存压力严重"],
    "Pressão normal": ["Normal pressure", "Normaler Druck", "Presión normal", "压力正常"],
    "Restam %d%%. Conecte o carregador.": ["%d%% left. Plug in your charger.", "Noch %d %%. Schließe das Netzteil an.", "Queda un %d%%. Conecta el cargador.", "剩余 %d%%。请接上充电器。"],
    "Restam só %@. Que tal liberar espaço no Menew?": ["Only %@ left. Free up space with Menew?", "Nur noch %@ frei. Mit Menew Speicher freigeben?", "Solo quedan %@. ¿Liberar espacio con Menew?", "仅剩 %@。用 Menew 释放空间？"],
    "Saúde": ["Health", "Zustand", "Salud", "健康度"],
    "Um aviso do macOS quando algo precisa da sua atenção. Cada alerta avisa uma vez, até a situação se resolver.": ["A macOS notification when something needs your attention. Each alert fires once until the situation is resolved.", "Eine macOS-Mitteilung, wenn etwas deine Aufmerksamkeit braucht. Jeder Hinweis kommt einmal, bis sich die Lage bessert.", "Un aviso de macOS cuando algo necesita tu atención. Cada alerta avisa una vez hasta que se resuelva.", "有情况需要注意时发送 macOS 通知。每个提醒只发一次，直到情况恢复。"],
    "%d conectado(s)": ["%d connected", "%d verbunden", "%d conectado(s)", "已连接 %d 个"],
    "%d horas": ["%d hours", "%d Stunden", "%d horas", "%d 小时"],
    "%d minutos": ["%d minutes", "%d Minuten", "%d minutos", "%d 分钟"],
    "1 hora": ["1 hour", "1 Stunde", "1 hora", "1 小时"],
    "Abrir %@": ["Open %@", "%@ öffnen", "Abrir %@", "打开 %@"],
    "Apaga a tela na hora. Para voltar, use Touch ID ou sua senha.": ["Turns the screen off right away. Use Touch ID or your password to come back.", "Schaltet den Bildschirm sofort aus. Zurück mit Touch ID oder deinem Passwort.", "Apaga la pantalla al instante. Para volver, usa Touch ID o tu contraseña.", "立即关闭屏幕。用触控 ID 或密码返回。"],
    "Apaga para sempre o que está na Lixeira. Pergunta antes.": ["Permanently deletes what's in the Trash. Asks first.", "Löscht den Inhalt des Papierkorbs endgültig. Fragt vorher nach.", "Borra para siempre lo que hay en la papelera. Pregunta antes.", "永久删除废纸篓中的内容。会先确认。"],
    "Aparecem": ["Visible", "Sichtbar", "Visibles", "显示"],
    "Aparecem no Finder": ["Visible in Finder", "Im Finder sichtbar", "Visibles en el Finder", "在访达中显示"],
    "Até %@": ["Until %@", "Bis %@", "Hasta las %@", "直到 %@"],
    "Até eu desligar": ["Until I turn it off", "Bis ich es ausschalte", "Hasta que lo apague", "直到我关闭"],
    "Até você desligar": ["Until you turn it off", "Bis du es ausschaltest", "Hasta que lo apagues", "直到你关闭"],
    "Bloqueia todas as teclas por 2 minutos para você limpar. Destrava com um clique.": ["Blocks every key for 2 minutes so you can wipe it. Unlock with a click.", "Sperrt alle Tasten für 2 Minuten zum Reinigen. Mit einem Klick entsperren.", "Bloquea todas las teclas durante 2 minutos para limpiarlo. Se desbloquea con un clic.", "锁定所有按键 2 分钟以便清洁。点一下即可解锁。"],
    "Clique em qualquer ponto da tela para copiar a cor em hexadecimal.": ["Click anywhere on screen to copy that color as hex.", "Klicke irgendwo auf den Bildschirm, um die Farbe als Hex zu kopieren.", "Haz clic en cualquier punto de la pantalla para copiar el color en hexadecimal.", "点击屏幕任意位置，以十六进制复制颜色。"],
    "Controles": ["Controls", "Steuerung", "Controles", "控制"],
    "Deixa todas as telas pretas para ver manchas. Dois cliques para sair.": ["Turns every display black to spot smudges. Double-click to exit.", "Macht alle Bildschirme schwarz, um Flecken zu sehen. Doppelklick zum Beenden.", "Pone todas las pantallas en negro para ver manchas. Doble clic para salir.", "让所有屏幕变黑以便发现污渍。双击退出。"],
    "Desligado": ["Off", "Aus", "Desactivado", "关闭"],
    "Ejeta com segurança todos os discos externos e pendrives.": ["Safely ejects all external drives and USB sticks.", "Wirft alle externen Laufwerke und USB-Sticks sicher aus.", "Expulsa con seguridad todos los discos externos y memorias USB.", "安全推出所有外置磁盘和 U 盘。"],
    "Encontra caches, logs e arquivos grandes. Você revisa antes de apagar.": ["Finds caches, logs and large files. You review before anything is deleted.", "Findet Caches, Protokolle und große Dateien. Du prüfst vor dem Löschen.", "Encuentra cachés, registros y archivos grandes. Revisas antes de borrar.", "查找缓存、日志和大文件。删除前由你确认。"],
    "Esconde tudo da mesa, bom para gravar a tela ou apresentar. Os arquivos continuam lá.": ["Hides everything on the desktop, handy for recording or presenting. Your files stay put.", "Blendet alles auf dem Schreibtisch aus, praktisch zum Aufnehmen oder Präsentieren. Die Dateien bleiben.", "Oculta todo el escritorio, útil para grabar o presentar. Los archivos siguen ahí.", "隐藏桌面上的所有内容，方便录屏或演示。文件仍在原处。"],
    "Escondidos": ["Hidden", "Ausgeblendet", "Ocultos", "已隐藏"],
    "Escondidos no Finder": ["Hidden in Finder", "Im Finder ausgeblendet", "Ocultos en el Finder", "在访达中隐藏"],
    "Impede que a tela apague e o Mac durma.": ["Keeps the display on and the Mac from sleeping.", "Verhindert, dass der Bildschirm ausgeht und der Mac schläft.", "Evita que la pantalla se apague y que el Mac entre en reposo.", "防止屏幕关闭和 Mac 进入睡眠。"],
    "Ligado": ["On", "An", "Activado", "开启"],
    "Manter acordado por um tempo": ["Keep awake for a while", "Eine Weile wach halten", "Mantener despierto un rato", "保持唤醒一段时间"],
    "Mostra arquivos que começam com ponto, como .git e .env. O Finder reinicia.": ["Shows files that start with a dot, like .git and .env. Finder restarts.", "Zeigt Dateien, die mit einem Punkt beginnen, etwa .git und .env. Der Finder startet neu.", "Muestra archivos que empiezan por punto, como .git y .env. El Finder se reinicia.", "显示以点开头的文件，如 .git 和 .env。访达会重新启动。"],
    "Selecione uma área da tela. A imagem vai para o clipboard e aparece no histórico.": ["Select an area of the screen. The image goes to the clipboard and shows up in your history.", "Wähle einen Bereich aus. Das Bild landet in der Zwischenablage und im Verlauf.", "Selecciona un área de la pantalla. La imagen va al portapapeles y aparece en el historial.", "选择屏幕区域。图像会进入剪贴板并出现在历史中。"],
    "Tira fonte, cor e links do texto copiado. Cole como texto simples.": ["Strips fonts, colors and links from the copied text, so it pastes as plain text.", "Entfernt Schrift, Farbe und Links aus dem kopierten Text. Einfügen als reiner Text.", "Quita fuente, color y enlaces del texto copiado. Se pega como texto simple.", "去除已复制文本的字体、颜色和链接，以纯文本粘贴。"],
    "Troca a aparência de todo o macOS entre claro e escuro.": ["Switches all of macOS between light and dark.", "Schaltet ganz macOS zwischen hell und dunkel um.", "Cambia todo macOS entre claro y oscuro.", "在浅色和深色之间切换整个 macOS。"],
    "caches e lixo": ["caches and junk", "Caches und Müll", "cachés y basura", "缓存和垃圾"],
    "do texto copiado": ["from copied text", "aus kopiertem Text", "del texto copiado", "已复制的文本"],
    "nenhum conectado": ["none connected", "keins verbunden", "ninguno conectado", "未连接"],
    "pede a senha": ["asks for password", "fragt nach Passwort", "pide la contraseña", "需要密码"],
    "pede confirmação": ["asks first", "fragt vorher", "pide confirmación", "会先确认"],
    "travado": ["locked", "gesperrt", "bloqueado", "已锁定"],
    "Ícones da mesa": ["Desktop icons", "Schreibtischsymbole", "Iconos del escritorio", "桌面图标"],
]
