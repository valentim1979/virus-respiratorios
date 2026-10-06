# Vigilância Epidemiológica — 15ª RS Maringá

Painel de vigilância epidemiológica de SRAG (Síndrome Respiratória Aguda
Grave) hospitalizada para a 15ª Regional de Saúde de Maringá/PR — 30
municípios do noroeste do Paraná, 909.489 habitantes em 2025 —, com dados
do SIVEP-Gripe. Publicado como site estático (Quarto + GitHub Pages) e
atualizado continuamente.

**Site publicado:** https://valentim1979.github.io/virus-respiratorios

A metodologia completa, no formato de seção de Métodos para artigos e
para a tese, está em [METODOLOGIA.md](METODOLOGIA.md).

## O que o painel mostra

O recorte é por município de **residência** e as séries semanais usam a
**semana epidemiológica de início dos sintomas** (`SEM_PRI`).

- **Situação do ano corrente:** curva epidêmica comparada com os anos
  anteriores, notificados e confirmados por semana, incidência e
  mortalidade por município (gráficos e mapas), perfil por sexo,
  raça/cor, faixa etária, classificação final e evolução.
- **Circulação viral:** agentes detectados por RT-PCR, tendência semanal,
  tipos e linhagens de influenza, composição por faixa etária e variação
  anual desde 2022.
- **Canal endêmico:** mediana e percentis 25, 75 e 90 dos anos
  pós-pandêmicos (2022 ao ano anterior), com cada semana classificada
  como abaixo do esperado, esperada, alerta ou epidêmica.
- **Nowcasting:** correção do atraso de digitação das semanas recentes
  (triângulo de notificação com regressão binomial negativa, D = 4,
  janela de 26 semanas, intervalo de predição de 95%), com validação
  retrospectiva em 20 cortes semanais publicada junto da estimativa.
- **Estatística descritiva:** completitude, oportunidade de notificação,
  tempo até o desfecho, comorbidades, letalidade entre casos encerrados,
  UTI, taxas por 100 mil por faixa etária e sexo, critério de
  confirmação, antiviral (uso e oportunidade, inclusive entre óbitos e
  curados de influenza) e situação vacinal contra covid-19 e influenza.
- **Avaliação da vigilância:**
  - inconsistência, valor preditivo positivo e os cinco indicadores de
    oportunidade de Ribeiro & Sanchez (2020);
  - consistência por regras e representatividade (razão de incidência
    padronizada por idade), atributos do protocolo da OMS (2001);
  - oportunidade de digitação por unidade notificadora.

As interpretações que dependem de inferência são redigidas como
hipóteses, separadas da descrição dos resultados.

## Fontes de dados

| Dado | Fonte | Atualização |
|---|---|---|
| Casos do ano corrente | Base estadual (PR) exportada do SIVEP-Gripe (DBF), anonimizada localmente | Diária (exportação manual) |
| Casos dos demais anos (2019 em diante) | Dados abertos de SRAG do Ministério da Saúde, via API do [dados.gov.br](https://dados.gov.br) | Anos encerrados são baixados uma única vez |
| População (denominadores) | Estimativas por município, idade e sexo 2000-2025 do Ministério da Saúde (DATASUS/Tabnet), por `baixar_populacao.R` | Anual |
| Regionais, macrorregiões e malha municipal | `sivep_15rs/parana_macrorregiao.csv` e IBGE (2024) | Fixa |
| Sensibilidade (análise anual, fora do painel) | SIH/SUS e SIM (DATASUS) | Anos fechados |

A base aberta do Ministério sai com uma a duas semanas de defasagem; por
isso, no ano corrente, o painel prioriza a exportação direta do
SIVEP-Gripe. As duas fontes usam o mesmo dicionário de dados e são
harmonizadas antes da análise.

## Proteção de dados (LGPD)

A base exportada do SIVEP-Gripe contém dados pessoais e passa por
`anonimizar_sivep.R` antes de qualquer análise:

- mantém só as variáveis de `colunas_permitidas.txt` (o conjunto do dado
  aberto do Ministério, sem data de nascimento e número da notificação,
  mais bairro e unidade notificadora);
- aborta sem gravar nada se algum identificador direto estiver presente;
- apaga o arquivo bruto após verificar a base anonimizada.

A base em nível de registro é **pseudonimizada**, e não anonimizada no
sentido estrito, por isso não é compartilhada. Ela fica em
`~/SIVEP_dados/` (permissão 0700), fora do repositório e de pastas
sincronizadas com a nuvem. O painel publica apenas dados agregados.

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `SCRIPT_Unificado.R` | Script principal: carrega a base local do ano e a API dos demais anos, gera gráficos, mapas, CSVs e Excel |
| `descritiva_srag_15rs.R` | Tabelas e gráficos descritivos (D01–D12), usados por `descritiva.qmd` |
| `nowcasting.R` | Nowcasting e validação retrospectiva, chamado pelo script principal |
| `anonimizar_sivep.R` | Anonimização da base exportada do SIVEP-Gripe (LGPD) |
| `colunas_permitidas.txt` | Lista de variáveis mantidas na anonimização |
| `baixar_populacao.R` | Download da população do PR por município, sexo e idade simples (Tabnet) |
| `analise_sensibilidade.R` | Análise anual SIVEP-Gripe × SIH/SUS × SIM, fora do painel |
| `index.qmd`, `descritiva.qmd`, `sobre.qmd` | Páginas do site |
| `_quarto.yml` | Configuração do projeto Quarto |
| `dbf_sivep/` | Cache local dos CSVs baixados da API e arquivos do DATASUS (não versionado, exceto `.gitkeep`) |
| `sivep_15rs/` | Dados de apoio: população, regionais e macrorregiões do PR, shapefiles (malha municipal do PR, bairros de Maringá e Sarandi) |
| `dados/`, `tabelas/`, `graficos/` | Saídas geradas pelos scripts (CSVs para o site, Excel, PNGs) |
| `docs/` | Site já renderizado — é o que o GitHub Pages publica |
| `arquivo/` | Scripts e páginas fora de uso, mantidos para eventual reaproveitamento (fora do pipeline ativo) |
| `processar_entrada.sh` | Disparado pelo systemd quando chega uma exportação do SIVEP: anonimiza, gera, renderiza e publica |
| `publicar.sh` | Roda o script principal, renderiza o Quarto e publica no GitHub |
| `instalar_dependencias.sh` | Instala as dependências de sistema e os pacotes R necessários |

## Como rodar

1. Configure o token da API em `~/.Renviron`:
   ```
   DADOS_GOV_TOKEN=seu_token_aqui
   ```
2. Instale as dependências (uma vez): `./instalar_dependencias.sh`
3. Publique:
   ```
   ./publicar.sh                # usa o cache existente
   ./publicar.sh --dados-novos  # força recarregar o ano corrente e re-renderizar tudo
   ```

Isso executa `SCRIPT_Unificado.R`, renderiza o site com `quarto render` e
já faz commit + push do resultado.

Tarefas anuais, fora da rotina:

```
Rscript baixar_populacao.R [ano]           # nova estimativa populacional (Tabnet)
Rscript analise_sensibilidade.R 2024 2025  # SIVEP × SIH/SUS × SIM, só anos fechados
```

Com os arquivos do DATASUS já em `dbf_sivep/datasus/`, a análise de
sensibilidade roda sem acesso ao FTP com `SENS_OFFLINE=1`.

## Atualização diária com a base do SIVEP-Gripe

1. Exporte do SIVEP-Gripe o DBF estadual (PR) do ano corrente.
2. Coloque o arquivo (`.dbf` ou `.zip`) em `~/SIVEP_entrada/`.
3. O serviço `sivep-entrada.path` (systemd de usuário) roda `processar_entrada.sh`:
   anonimiza a base, apaga o arquivo bruto, gera os gráficos, renderiza e
   publica. O resultado aparece como notificação no desktop.

## Software

R 4.6.1 (MASS, dplyr, ggplot2, sf, tmap, readr, foreign, writexl, tidytext,
knitr, kableExtra) e Quarto 1.10.18. Versões completas e as limitações
conhecidas do painel estão em [METODOLOGIA.md](METODOLOGIA.md).
