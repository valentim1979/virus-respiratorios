# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Visão geral

Boletim epidemiológico de SRAG (SIVEP-Gripe, módulo hospitalar) da 15ª Regional de Saúde de Maringá/PR, publicado como site estático Quarto no GitHub Pages (`docs/`) em https://valentim1979.github.io/virus-respiratorios/ (repositório `valentim1979/virus-respiratorios`; antes se chamava `vigilancia-epidemiologica`, nome que a pasta local ainda usa). Todo o código, comentários, commits e textos do site são em português.

## Onde roda / sincronização

- A publicação roda **neste notebook (Linux/Omarchy)**: o usuário baixa à mão o DBF estadual (PR) de um ano no SIVEP-Gripe e joga em `~/SIVEP_entrada/`; a unit systemd de usuário `sivep-entrada.path` dispara `sivep-entrada.service` → `processar_entrada.sh` (anonimiza → `publicar.sh --dados-novos`), com notificação no desktop. Log em `processar_entrada.log`. Se a árvore do git estiver suja (trabalho em andamento), a base é atualizada mas a publicação é **adiada** — por isso, ao terminar uma mudança, faça o commit e, se houver base nova, rode `./publicar.sh --dados-novos`.
- Até 03/10/2026 a publicação rodava num Mac (launchd às 23h, via API); foi desligada. Não reative publicação em outra máquina — duas máquinas publicando geram push recusado.
- `~/Work` é sincronizado com o OneDrive (rclone bisync). Por isso **dados por registro nunca ficam no projeto**: base anonimizada e contexto da página descritiva vão para `~/SIVEP_dados/` (variável `SIVEP_DADOS`), e o DBF bruto entra por `~/SIVEP_entrada/`, ambos fora do `~/Work`.
- O histórico do GitHub já foi reescrito uma vez; se `main` e `origin/main` divergirem sem ancestral comum, não faça merge — iguale ao remoto. Com a árvore suja, `git pull` falha com "Please commit or stash them" (pull configurado com rebase) — não é divergência.
- Não rode `./publicar.sh` / `/publicar` sem o usuário pedir: faz `git add .` + commit + push.

## Dados do SIVEP e LGPD

- `anonimizar_sivep.R` lê o DBF/ZIP mais recente de `~/SIVEP_entrada`, mantém **só** as colunas de `colunas_permitidas.txt` (dado aberto do Ministério − `DT_NASC`/`NU_NOTIFIC` + bairro e unidade notificadora), grava `~/SIVEP_dados/sivep_local_anon_<ano>.rds` (tudo texto, datas `AAAA-MM-DD`, como o CSV da API) e **apaga o bruto**; em erro, move o bruto para `~/SIVEP_entrada/erro/`. Aborta se a base misturar anos (<95% num ano).
- `carregar_base(ano)` no `SCRIPT_Unificado.R` usa a base local do ano quando existe; os demais anos vêm da API. A data do rodapé (`DATA_EXTRACAO`) passa a ser a da exportação do DBF.
- Nunca leia, imprima ou registre valores de registros do DBF bruto ou da base anonimizada — só nomes de colunas e contagens agregadas. Para adicionar uma coluna, inclua-a em `colunas_permitidas.txt` (nunca identificadores diretos; a lista `PROIBIDAS` no script barra os principais).

## Metodologia

`METODOLOGIA.md` é a seção de Métodos (artigo/tese) do painel. **Ao mudar qualquer definição, indicador, fonte, anonimização ou modelo, atualize-o no mesmo commit** — descrevendo o que o código faz (não o que deveria fazer) e acrescentando uma linha no "Histórico de alterações". Referências citadas devem ser reais e verificáveis.

## Comandos

```bash
./instalar_dependencias.sh          # uma vez: gdal/geos/proj (pacman), udunits + quarto-cli-bin (yay), pacotes R
Rscript SCRIPT_Unificado.R          # só gera gráficos/tabelas/CSVs (sem publicar)
Rscript baixar_populacao.R [ano]    # 1x/ano: população PR por município/sexo/idade (Tabnet) → sivep_15rs/
quarto render                       # gera o site em docs/
quarto preview                      # servidor local para conferir o site
./publicar.sh [--dados-novos]       # R + render + commit + push (ver .claude/commands/publicar.md)
```

`--dados-novos` apaga `_freeze/` para forçar o Quarto a reexecutar o R; sem ele, `freeze: auto` reaproveita o cache (bom para mudanças só de texto/layout).

Requer `DADOS_GOV_TOKEN=...` em `~/.Renviron` (API dados.gov.br). Não há testes nem lint.

## Arquitetura

**Fluxo de dados:** API dados.gov.br → cache `dbf_sivep/SRAG_API_<ano>.csv` (+ base local anonimizada do ano, se houver) → `SCRIPT_Unificado.R` → `graficos/*.png`, `dados/*.csv`, `tabelas/*.xlsx` → páginas `.qmd` → `docs/`.

- **`SCRIPT_Unificado.R`** (~1600 linhas) é organizado em blocos numerados (`BLOCO 0` … `BLOCO 5`+). O `BLOCO 0` concentra os parâmetros editáveis (`ANO_ANALISE`, `ANO_INICIO_CANAL`, `MUNICIPIO_ANALISE`, caminhos de arquivos). Gráficos são salvos via `salvar_grafico()` com rodapé `texto_rodape`.
- **Cache da API** (`baixar_via_api()`): anos encerrados são baixados uma vez e reaproveitados para sempre; o ano corrente só é rebaixado se o CSV não for de hoje; se o download falhar, mantém o cache anterior. `dbf_sivep/` (~4,7 GB) não é versionado.
- **Recorte da regional:** por município de **residência** (`CO_MUN_RES` ∈ `municipios_15rs$codigo_ibge_6`, código IBGE de 6 dígitos). Municípios estão fixos no `BLOCO 2` (`municipios_15rs`); a população vem do arquivo mais recente `sivep_15rs/populacao_pr_idade_sexo_<ano>.csv` (`baixar_populacao.R`, estimativas MS/DATASUS), com os valores digitados no `BLOCO 2` só como reserva; regionais/macrorregiões do PR vêm de `sivep_15rs/parana_macrorregiao.csv`; a malha municipal, de `sivep_15rs/GIS/Pr_Municipios_2024/`. Não há mapas por bairro hoje (a API não traz `NM_BAIRRO`; a base local traz).
- **Páginas consomem as saídas de formas diferentes:**
  - `index.qmd` — página principal; usa os PNGs de `graficos/` por caminho fixo (o nome do arquivo é o contrato entre script e página) e células `{ojs}` interativas que leem `dados/*.csv` via `FileAttachment` (por isso `dados/**` está em `resources` no `_quarto.yml`).
  - `descritiva.qmd` — executa R no render, mas **não** reroda o script principal: lê `~/SIVEP_dados/contexto_descritiva.rds` (salvo no fim de `SCRIPT_Unificado.R`; pasta configurável por `SIVEP_DADOS`) e faz `source("descritiva_srag_15rs.R")`, que monta os gráficos `gD01`–`gD12` exibidos direto pela página e grava `tabelas/descritiva_15rs_<ano>.xlsx`. Por isso o `.rds` precisa existir antes do `quarto render`; se `descritiva_srag_15rs.R` passar a usar outro objeto do script principal, inclua-o na lista do `saveRDS()`.
- **Nowcasting** (`nowcasting.R`, chamado no bloco "GRÁFICO 06c" do script principal): triângulo de notificação com binomial negativa (D = 4, janela de 26 semanas, corte no último sábado), gera `graficos/06c_nowcasting.png`, `dados/nowcasting_srag.csv` e a validação retrospectiva `dados/nowcasting_validacao.csv`, lidos pela aba "Estimativa (nowcasting)" do `index.qmd`. Parâmetros escolhidos por validação — documentados em `METODOLOGIA.md` §8.1; não mude sem rerodar a validação.
- Ao renomear ou criar um gráfico no script, atualize a referência correspondente no `.qmd`.
- `sivep_15rs/` só guarda dados de apoio (CSV de regionais do PR e shapefiles: malha do PR e bairros de Maringá/Sarandi). `arquivo/` guarda páginas/scripts fora de uso. Ambos estão excluídos do render.
