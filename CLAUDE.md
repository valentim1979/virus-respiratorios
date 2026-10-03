# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Visão geral

Boletim epidemiológico de SRAG (SIVEP-Gripe, módulo hospitalar) da 15ª Regional de Saúde de Maringá/PR, publicado como site estático Quarto no GitHub Pages (`docs/`) em https://valentim1979.github.io/virus-respiratorios/ (repositório `valentim1979/virus-respiratorios`; antes se chamava `vigilancia-epidemiologica`, nome que a pasta local ainda usa). Todo o código, comentários, commits e textos do site são em português.

## Onde roda / sincronização

- A publicação oficial roda no **MacBook**, todo dia às 23h via launchd (`com.valentim.vigilancia-publicar.plist` → `./publicar.sh --dados-novos`), com commit e push automáticos.
- Neste PC (Linux/Omarchy) o repositório pode ficar para trás: **sempre `git pull` antes de mexer**. O histórico do GitHub já foi reescrito uma vez; se `main` e `origin/main` divergirem sem ancestral comum, não faça merge — iguale ao remoto.
- Não rode `./publicar.sh` / `/publicar` neste PC sem o usuário pedir: ele faz `git add .` + commit + push e concorre com a publicação do Mac.

## Comandos

```bash
./instalar_dependencias.sh          # uma vez: gdal/geos/proj (pacman), udunits + quarto-cli-bin (yay), pacotes R
Rscript SCRIPT_Unificado.R          # só gera gráficos/tabelas/CSVs (sem publicar)
quarto render                       # gera o site em docs/
quarto preview                      # servidor local para conferir o site
./publicar.sh [--dados-novos]       # R + render + commit + push (ver .claude/commands/publicar.md)
```

`--dados-novos` apaga `_freeze/` para forçar o Quarto a reexecutar o R; sem ele, `freeze: auto` reaproveita o cache (bom para mudanças só de texto/layout).

Requer `DADOS_GOV_TOKEN=...` em `~/.Renviron` (API dados.gov.br). Não há testes nem lint.

## Arquitetura

**Fluxo de dados:** API dados.gov.br → cache `dbf_sivep/SRAG_API_<ano>.csv` → `SCRIPT_Unificado.R` → `graficos/*.png`, `dados/*.csv`, `tabelas/*.xlsx` → páginas `.qmd` → `docs/`.

- **`SCRIPT_Unificado.R`** (~1600 linhas) é organizado em blocos numerados (`BLOCO 0` … `BLOCO 5`+). O `BLOCO 0` concentra os parâmetros editáveis (`ANO_ANALISE`, `ANO_INICIO_CANAL`, `MUNICIPIO_ANALISE`, caminhos de arquivos). Gráficos são salvos via `salvar_grafico()` com rodapé `texto_rodape`.
- **Cache da API** (`baixar_via_api()`): anos encerrados são baixados uma vez e reaproveitados para sempre; o ano corrente só é rebaixado se o CSV não for de hoje; se o download falhar, mantém o cache anterior. `dbf_sivep/` (~4,7 GB) não é versionado.
- **Recorte da regional:** por município de **residência** (`CO_MUN_RES` ∈ `municipios_15rs$codigo_ibge_6`, código IBGE de 6 dígitos). Municípios e população IBGE 2025 estão fixos no `BLOCO 2` (`municipios_15rs`); regionais/macrorregiões do PR vêm de `sivep_15rs/parana_macrorregiao.csv`; a malha municipal, de `sivep_15rs/GIS/Pr_Municipios_2024/`. Não há mais mapas por bairro (a API não traz `NM_BAIRRO`).
- **Páginas consomem as saídas de formas diferentes:**
  - `index.qmd` — página principal; usa os PNGs de `graficos/` por caminho fixo (o nome do arquivo é o contrato entre script e página) e células `{ojs}` interativas que leem `dados/*.csv` via `FileAttachment` (por isso `dados/**` está em `resources` no `_quarto.yml`).
  - `descritiva.qmd` — executa R no render, mas **não** reroda o script principal: lê `~/SIVEP_dados/contexto_descritiva.rds` (salvo no fim de `SCRIPT_Unificado.R`; pasta configurável por `SIVEP_DADOS`) e faz `source("descritiva_srag_15rs.R")`, que monta os gráficos `gD01`–`gD12` exibidos direto pela página e grava `tabelas/descritiva_15rs_<ano>.xlsx`. Por isso o `.rds` precisa existir antes do `quarto render`; se `descritiva_srag_15rs.R` passar a usar outro objeto do script principal, inclua-o na lista do `saveRDS()`.
- Ao renomear ou criar um gráfico no script, atualize a referência correspondente no `.qmd`.
- `arquivo/` guarda páginas/scripts fora de uso e `sivep_15rs/` contém scripts antigos e um app Shiny; ambos estão excluídos do render e não fazem parte do pipeline ativo.
