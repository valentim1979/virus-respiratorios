#!/bin/bash
# ==============================================================================
# processar_entrada.sh — Vigilância Epidemiológica / 15ª RS Maringá
# Disparado pelo systemd (sivep-entrada.path) quando um DBF/ZIP do SIVEP-Gripe
# chega em ~/SIVEP_entrada: anonimiza, gera os gráficos, renderiza e publica.
# Uso manual: ./processar_entrada.sh
# ==============================================================================

set -eo pipefail

PROJETO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJETO"
LOG="$PROJETO/processar_entrada.log"

avisar() { notify-send -a "SIVEP" "$@" 2>/dev/null || true; }
trap 'avisar -u critical "Publicação do boletim falhou" "Veja $LOG"' ERR

# Uma execução por vez (o systemd pode disparar de novo durante o processamento)
exec 9>"$PROJETO/.processar_entrada.lock"
flock -n 9 || { echo "Já existe um processamento em andamento."; exit 0; }

exec > >(tee -a "$LOG") 2>&1
echo ""
echo "=================================================="
echo "  PROCESSAR ENTRADA — $(date '+%d/%m/%Y %H:%M')"
echo "=================================================="

avisar "Arquivo do SIVEP recebido" "Anonimizando e gerando o boletim…"

git pull --rebase
Rscript "$PROJETO/anonimizar_sivep.R" "$HOME/SIVEP_entrada"
"$PROJETO/publicar.sh" --dados-novos

avisar "Boletim publicado" "https://valentim1979.github.io/virus-respiratorios/"
