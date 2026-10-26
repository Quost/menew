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
    "Atalhos": ["Shortcuts", "Kurzbefehle", "Atajos", "快捷键"],
    "Abrir este menu": ["Open this menu", "Dieses Menü öffnen", "Abrir este menú", "打开此菜单"],
]
