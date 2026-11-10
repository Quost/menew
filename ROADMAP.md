# Roadmap do Menew

Plano de longo prazo, escrito em novembro de 2026 a partir de um benchmark com os ~450 apps de [macmenubar.app](https://macmenubar.app/) e cruzado com o que o Menew já faz. É uma direção, não uma promessa: a ordem pode mudar conforme as issues e o que os usuários pedirem.

Esforço estimado: **P** pequeno, **M** médio, **G** grande. Em itálico, apps do site que inspiraram o item.

Critérios para entrar: nativo, roda no Mac, sem conta, sem telemetria e sem chamadas de rede novas (ver [CLAUDE.md](CLAUDE.md)). O que exige rede está em [Depende de decisão](#depende-de-decisão).

## Primeiro ciclo (prioridade)

Muito valor com pouco esforço, reaproveitando o que já existe:

1. **1.99, Agentes de IA** ✅ preparada: seção de agentes, avisos no notch, "esperando por você", custo, limites, previsão e servidor MCP.
2. **2.0, Agentes, segunda parte**: aprovar ou negar permissões pelo notch (2.29) e manter o Mac acordado enquanto um agente trabalha. Notch, hooks e manter acordado já existem.
3. **2.16, Clipboard mais seguro**: tirar UTM dos links, detectar chaves e tokens e apagá-los sozinho. Pequeno, para todo mundo, reforça a privacidade.
4. **2.9, Lembretes na barra**: lista "Hoje" do app Lembretes, marcar como feito, fixar uma tarefa na barra.
5. **2.6, Pausas inteligentes**: 20-20-20, alongar e levantar, adiadas sozinhas em reunião, gravação ou foco, coisa que os concorrentes não sabem.
6. **2.14, Ditado em qualquer app**: segurar uma tecla e falar, processado no Mac, com limpeza por IA. Prepara o "falar com o agente" (2.32).

Fora do primeiro ciclo de propósito: **esconder ícones (2.3)** é o pedido mais comum, mas é arriscado no macOS 26 (fazer um protótipo em paralelo antes de anunciar). **Volume por app (2.20)** e **presets de monitor (2.76)** são grandes demais.

Como medir sem telemetria: downloads por release no GitHub, estrelas, issues e cliques no GoatCounter das páginas de cada feature.

## Fase 1 · Agentes e barra (1.99 → 2.5)

- **1.99** Agentes de IA: sessões, limites, MCP ✅ · *CodexBar, AIQuota, Burnrate*
- **2.0** Agentes no notch: avisos e "esperando por você" ✅ na 1.99; falta manter acordado enquanto o agente trabalha (P) · *Vibe Island, Look Alive, Belay*
- **2.1** Custo e previsão: custo por modelo e projeto, previsão de quando o limite estoura ✅ na 1.99 · *Tokenscope, ReserveGauge*
- **2.2** Configurar agentes: ligar e desligar skills e servidores MCP, trocar conta ou provedor (M) · *Wasdy, Prism Switch, Quotio*
- **2.3** Esconder ícones da barra: seção oculta, sempre ocultos, compatível com o notch (G) · *Ice, Bartender, Hidden Bar*
- **2.4** Plugins da barra no formato SwiftBar/xbar (M) · *SwiftBar*
- **2.5** Ícone com personalidade: CPU animada, temas sazonais opcionais (P) · *RunCat, Festivitas*

## Fase 2 · Saúde e dia (2.6 → 2.13)

- **2.6** Pausas inteligentes, adiadas em reunião, gravação ou tela cheia (M) · *LookAway, Pausebar, Recess*
- **2.7** Postura pelo sensor dos AirPods, sem câmera (M) · *Poise*
- **2.8** Água e hábitos: check-in com 1 clique, sequência que perdoa (P) · *Aqumi, Keystone, Tasktile*
- **2.9** Lembretes na barra: "Hoje", marcar como feito, uma tarefa fixa (P) · *Barrie, One Thing, Satu*
- **2.10** Planejar o dia: lembretes encaixados nos horários livres entre reuniões (M) · *Tideline, Nowline*
- **2.11** Calendário do mês, aniversários dos Contatos, contagens regressivas (P) · *Itsycal, Honeyday, Await*
- **2.12** Alerta de reunião em tela cheia, hora local de cada colega e horário em comum (M) · *Dato, Chime, There*
- **2.13** Tempo por projeto: timer de 1 clique, tempo esquecido, "recibo" do dia (M) · *Dial, Punchcard*

## Fase 3 · Texto, captura, som e Mac (2.14 → 2.28)

- **2.14** Ditado segurando uma tecla, em qualquer app, no Mac (M) · *parrot, Handy, HoldSpeak*
- **2.15** Bolha de ações ao selecionar texto, com as ações do ⌃⌥⌘R (M) · *PopClip, SwiftBiu*
- **2.16** Clipboard mais seguro: sem UTM, segredos que expiram, Touch ID (P) · *UTMBeGone, Klipvault*
- **2.17** Teclas e cliques na tela, holofote, zoom, desenhar na tela (M) · *KeyCastr, ClickLight, Presentify*
- **2.18** Screenshot bonito: fundo, sombra, proporção fixa, régua de pixels (M) · *Tuji, Framéd, PixelSnap*
- **2.19** Bordas da tela como ring light, espelho de câmera, tela de privacidade (P) · *DisplayFill, Hand Mirror, Shoji*
- **2.20** Volume por app, prioridade de dispositivos, mudo ao tirar o fone (G) · *FineTune, AudioPriorityBar, Default0*
- **2.21** Agora tocando: Music e Spotify no menu e no notch, HUD de volume e brilho (M) · *Boring Notch, Tuneful*. Usar AppleScript, já que o MediaRemote está restrito desde o macOS 15.4.
- **2.22** Sons de foco gerados no Mac, ligados ao timer (P) · *Patter, CapyMuMu*
- **2.23** AirPods por atalho, Bluetooth não reconecta com o Mac dormindo, o que o cabo USB-C suporta (M) · *Sharptooth, Bluesnooze, WhatCable*
- **2.24** Modo vigia: alarme ao tirar o carregador ou fechar a tampa, travar quando o iPhone se afasta (M) · *Stealward, Peeku*
- **2.25** Ajustes do macOS com desfazer: Dock, screenshots, arquivos ocultos (P) · *Mainspring, One Switch*
- **2.26** Histórico de quedas da internet e do Wi-Fi, sem tráfego extra (P) · *NetCheck, Online Indicator*
- **2.27** Atalho por app (⌥1 abre o Slack), alternador de janelas com miniaturas (G) · *Spring, DockDoor, cmdcmd*
- **2.28** Navegador por domínio, links de reunião direto no app, favoritos de todos os navegadores na paleta (M) · *Portals, Bookmark Bar*

## Fase 4 · Agentes, segunda onda (2.29 → 2.36)

- **2.29** Aprovar ou negar permissões do agente pelo notch (M) · *Vibe Island*
- **2.30** Linha do tempo da sessão: o que o agente fez, arquivos e comandos (M)
- **2.31** Continuar sozinho quando o limite zera, com fila de prompts (M) · *CodexReset*
- **2.32** Falar com o agente: ditado direto na sessão ativa (P) · *Agent Bar*
- **2.33** Mais ferramentas no MCP, com permissão a cada ação: janelas, apps, captura, lembretes, calendário (M) · *Macuse, Orchard*
- **2.34** Comando `menew` para scripts: avisos, progresso no notch, clipboard, notas (M) · *Notchification*
- **2.35** Progresso de builds no notch (xcodebuild, npm, testes) (P)
- **2.36** Agentes como personagens flutuando, modo divertido opcional (P) · *Agenteam*

## Fase 5 · Barra e notch do seu jeito (2.37 → 2.44)

- **2.37** Espaçamento entre os ícones da barra (P) · *Menu Bar Spacing*
- **2.38** Relógio no canto quando a barra fica oculta (P) · *Corner Time*
- **2.39** Buscar nos menus do app ativo pela paleta (M)
- **2.40** Notch montável: escolher os blocos do painel (M) · *OmniNotch, NotchDodo*
- **2.41** Cartões do clipboard saindo do notch (M) · *Just Copy, Supaste*
- **2.42** Pastas favoritas como menus, links rápidos no notch (P) · *Folder Peek, LinkNotch*
- **2.43** Qualquer app na barra, com não lidos do Slack ou do Mail (M) · *Badgeify*
- **2.44** Uma pasta do app Atalhos como menu na barra (P) · *Short Run*

## Fase 6 · Saúde, segunda onda (2.45 → 2.51)

- **2.45** Estatísticas de digitação, cliques e rolagem, só contagens (P) · *Mac Input Stats*
- **2.46** Limites gentis por app ("30 min de YouTube por dia") (M) · *BalmyTime*
- **2.47** Respiração guiada de 1 minuto no notch (P) · *Mysa*
- **2.48** Filtro noturno mais forte que o Night Shift, com modo vermelho e horário (M) · *Nox, Sundown*
- **2.49** Tela e luz do teclado abaixo do mínimo (P) · *Doze, Lowlight*
- **2.50** Lembretes de movimento com exercícios curtos (P) · *DeskSquat, Standflow*
- **2.51** Resumo semanal: pausas, postura, tempo de tela, horas tarde (P)

## Fase 7 · Ideias e escrita (2.52 → 2.59)

- **2.52** Notas adesivas flutuantes ou presas na borda da tela (M) · *Tucky, FloatyDo*
- **2.53** Notas por app ou por janela (M) · *Flip*
- **2.54** Uma linha direto no fim de um .md escolhido (Obsidian) (P) · *Markie*
- **2.55** Diário em formato de conversa, ligado à Memória (M) · *mynd*
- **2.56** Salvar a aba do navegador na Memória com um atalho (P) · *Snaggy, Clipii*
- **2.57** Mini planilha no menu (M) · *MenuSheet*
- **2.58** Revisão do dia e da semana numa página só (M)
- **2.59** Coleções no clipboard, "sempre colar sem formatação" por app (P) · *PastePal*

## Fase 8 · Vídeo e demos (2.60 → 2.66)

- **2.60** Câmera numa bolha na gravação de tela (M) · *FaceScreen*
- **2.61** Kit de bug report: gravação, dados do sistema e logs num .zip (M) · *Jam*
- **2.62** Comprimir imagens em lote, com WebP e AVIF (P) · *Zipic, Tinyowl*
- **2.63** Cortar e acelerar gravações antes de exportar (M)
- **2.64** Paleta de cores de uma imagem, histórico do conta-gotas (P) · *Sip*
- **2.65** Legendas gravadas no vídeo a partir da transcrição (M)
- **2.66** Traduzir a tela: a tradução aparece por cima da área (M) · *TrueDict, PinsGO*

## Fase 9 · Arquivos e espaço (2.67 → 2.73)

- **2.67** Buscar qualquer arquivo pela paleta, com prévia (M) · *Everywhere*
- **2.68** Regras automáticas para pastas como Downloads, com desfazer (M) · *DropSweep*
- **2.69** Converter um arquivo trocando a extensão (P) · *Consul*
- **2.70** Raio-X dos "Dados do Sistema": snapshots, backups do iPhone, simuladores (M) · *System Data*
- **2.71** Enviar para o outro Mac pela rede local, sem nuvem (M) · *Sharee*
- **2.72** Recortar e colar arquivos no Finder com ⌘X (M) · *FinderClip*
- **2.73** Fotos parecidas (não idênticas) no limpador, sempre para o Lixo (M)

## Fase 10 · Som, telas e entrada (2.74 → 2.81)

- **2.74** Equalizador do sistema por dispositivo (M) · *FineTune*
- **2.75** Dois fones ou várias saídas ao mesmo tempo (P) · *PairPods, Cacophony*
- **2.76** Presets de monitor (resolução, HiDPI, brilho) por perfil (G) · *BetterDisplay, Crisp*
- **2.77** Janelas voltam ao lugar quando o monitor reconecta (M) · *ScreenPlace, Stay*
- **2.78** Rolagem suave e sentido separado para mouse e trackpad (M) · *AirScroll*
- **2.79** Idioma do teclado por app (P) · *LinguaX*
- **2.80** Painel de privacidade: qual app usou câmera, microfone e localização, e quando (M)
- **2.81** Ângulo da tampa, com ações (P) · *LidAngleSensor, Lid Plane*

## Fase 11 · Dev, segunda onda (2.82 → 2.88)

- **2.82** Servidores de dev agrupados por projeto (P) · *TidyPorts, Port Menu*
- **2.83** Containers do Docker e do `container` da Apple: listar, parar, logs (M) · *Berthly*
- **2.84** Simuladores iOS e emuladores Android: abrir, limpar, deep link (M) · *MiniSim, SimTag*
- **2.85** Identidade do git por pasta, pessoal e trabalho (P) · *Switzy*
- **2.86** Kit dev maior na paleta: JSON, Base64, hash, regex, cron (P)
- **2.87** "Avise quando acabar" para comandos longos no terminal (P)
- **2.88** Snippets de código com destaque de sintaxe (P) · *BearGist*

## Fase 12 · Plataforma e acabamento (2.89 → 3.0)

- **2.89** Sincronizar notas, snippets e ajustes entre os seus Macs pelo iCloud, opcional e sem conta nova (G)
- **2.90** Clipboard entre os seus Macs, opcional (M) · *CliperX*
- **2.91** API de plugins do Menew, com painéis próprios (G)
- **2.92** Mais idiomas no app e no site: francês, japonês, coreano, italiano (M)
- **2.93** Calendário lunar chinês e feriados por país (P) · *LunarBar*
- **2.94** Acessibilidade: VoiceOver completo, tudo pelo teclado (M)
- **2.95** Modo economia: o Menew mede o próprio gasto de energia (M)
- **2.96** Mascote opcional que reage à CPU e ao foco (P) · *CatPod, RunCat*
- **2.97** Cara ou coroa, sorteio e dado na paleta (P) · *Flippr*
- **3.0** **Painel do dia**: agenda, agentes, saúde, tarefas e Mac numa tela, com o "Agora" redesenhado em volta disso (G)

## Depende de decisão

Criam chamadas de rede novas, que hoje não são permitidas. Só entram como opcionais e sob demanda, como o câmbio:

- Clima (WeatherKit)
- PRs e issues do GitHub (pelo `gh` instalado)
- Aviso de atualização dos outros apps · *MacUpdater*
- Cliente HTTP rápido · *Pingo*
- Upload para um bucket seu · *Tinyowl*

## Fora

- Limite de carga da bateria: precisa de helper com senha de admin, e o Menew promete não usar.
- Firewall: é outro produto (o LuLu já faz).
- Gravação contínua "para quando esqueceu de gravar": risco de privacidade.
- Proxy para compartilhar assinaturas de IA: bate nos termos de uso.
- Wallpapers baixados da internet, sons de teclado, Hue e controles de TV.
