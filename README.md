# Vigilância Epidemiológica — 15ª RS Maringá

Painel de vigilância epidemiológica de SRAG (Síndrome Respiratória Aguda
Grave) para a 15ª Regional de Saúde de Maringá/PR, com dados do
SIVEP-Gripe (módulo hospitalar). Publicado como site estático (Quarto +
GitHub Pages).

**Site publicado:** https://valentim1979.github.io/virus-respiratorios

## O que o projeto faz

- Baixa os dados de SRAG direto da API pública do [dados.gov.br](https://dados.gov.br)
  (não depende mais de DBF local).
- Gera gráficos e mapas por município da regional (`SCRIPT_Unificado.R`).
- Gera tabelas descritivas complementares (`descritiva_srag_15rs.R`).
- Renderiza o site com Quarto a partir dos `.qmd` da raiz.

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `SCRIPT_Unificado.R` | Script principal: baixa os dados via API, gera gráficos/mapas e exporta CSVs/Excel |
| `descritiva_srag_15rs.R` | Tabelas e gráficos descritivos (D01–D12), usado por `descritiva.qmd` |
| `index.qmd`, `descritiva.qmd`, `sobre.qmd` | Páginas do site |
| `_quarto.yml` | Configuração do projeto Quarto |
| `dbf_sivep/` | Cache local dos CSVs baixados da API (não versionado, exceto `.gitkeep`) |
| `sivep_15rs/` | Dados de apoio: regionais/macrorregiões do PR e shapefiles (malha municipal do PR, bairros de Maringá e Sarandi) |
| `dados/`, `tabelas/`, `graficos/` | Saídas geradas pelos scripts (CSVs para o site, Excel, PNGs) |
| `docs/` | Site já renderizado — é o que o GitHub Pages publica |
| `arquivo/` | Scripts e páginas fora de uso hoje, mantidos para eventual reaproveitamento (não fazem parte do pipeline ativo) |
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

## Atualização diária com a base do SIVEP-Gripe

1. Exporte do SIVEP-Gripe o DBF estadual (PR) do ano corrente.
2. Coloque o arquivo (`.dbf` ou `.zip`) em `~/SIVEP_entrada/`.
3. O serviço `sivep-entrada.path` (systemd de usuário) roda `processar_entrada.sh`:
   anonimiza a base (`anonimizar_sivep.R`, LGPD), apaga o arquivo bruto, gera os
   gráficos, renderiza e publica. O resultado aparece como notificação no desktop.

A base anonimizada fica em `~/SIVEP_dados/`, fora do repositório e do OneDrive.
Detalhes metodológicos e de proteção de dados em [METODOLOGIA.md](METODOLOGIA.md).

## Fonte dos dados

SIVEP-Gripe (módulo hospitalar), via API pública do dados.gov.br. Anos
anteriores ao corrente são estáticos (baixados uma vez e reaproveitados);
o ano corrente é rebaixado sempre que o cache local não for do dia.
