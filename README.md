# MeuMenu

App de barra de menus para macOS 14+, feito em Swift/SwiftUI, sem dependências.

- **Sistema**: CPU (com gráfico), memória, disco, bateria, rede (↓↑ e IP local), tempo ligado, temperatura e os processos que mais usam CPU
- **Clipboard**: histórico de texto, imagens e arquivos, com busca, itens fixados, ícone do app de origem e amostra de cor para hex
- **⌘⇧V**: painel flutuante (↑↓ ↩ colar, ⌥↩ texto puro, ⌘1–9, ⌘P fixar, ⌘⌫ apagar, esc)
- **⌥⌘M**: abre o menu principal
- **Notas rápidas** que salvam sozinhas
- **Internet**: velocidade em tempo real, IP local e público, teste de velocidade (networkQuality)
- **Dispositivos**: bateria de AirPods, Magic Mouse/Keyboard/Trackpad
- **Limpeza**: trava o teclado por 2 min ou apaga a tela para limpar
- **Ações**: manter acordado, bloquear tela, arquivos ocultos, ocultar mesa, ejetar discos, esvaziar lixeira, modo escuro, print → clipboard, conta-gotas, limpar formatação

## Capturas de tela

```bash
.build/release/MeuMenu --snapshot /caminho/da/pasta
```

Gera PNGs de todas as telas (claro e escuro) usando um histórico fictício.

## Compilar

```bash
./build.sh            # gera build/MeuMenu.app
./build.sh --install  # copia para /Applications e abre
```

Os dados ficam em `~/Library/Application Support/MeuMenu/`.

Para o "colar automaticamente" funcionar, libere o MeuMenu em Ajustes do Sistema → Privacidade e Segurança → Acessibilidade.
A assinatura é ad-hoc, então depois de recompilar talvez seja preciso liberar de novo.
