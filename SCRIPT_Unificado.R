# ==============================================================================
# VIGILÂNCIA EPIDEMIOLÓGICA — 15ª REGIONAL DE SAÚDE DE MARINGÁ
# Script unificado: Gráficos SRAG + Mapas por município
# Autor   : Valentim Sala Junior
# Saída   : pasta graficos/ do projeto GitHub Pages
# Versão 4: carregamento sempre via API dados.gov.br (DBF local removido);
#           bloco climático (INMET) removido; mapas/gráficos por bairro
#           removidos (a API não traz NM_BAIRRO) — só ficam os mapas por
#           município da regional
# ==============================================================================


# ==============================================================================
# CARREGAMENTO DO TOKEN DA API (necessário — o script agora só usa a API)
# ==============================================================================
if (file.exists("~/.Renviron")) readRenviron("~/.Renviron")

# Timeout maior para downloads grandes via API (alguns anos passam de 1 GB)
options(timeout = 1800)

# ==============================================================================
# BLOCO 0 — CONFIGURAÇÃO GLOBAL (EDITE AQUI)
# ==============================================================================

# --- 0.1 Anos de análise ---
ANO_ANALISE <- 2026
ANO_INICIO_CANAL <- 2022

# --- 0.2 Município ---
MUNICIPIO_ANALISE <- NULL

# --- 0.3 Caminhos (relativos à raiz do projeto) ---
# Pasta de cache dos CSVs baixados da API dados.gov.br. Os dados de SRAG
# agora vêm sempre da API — DBFs locais não são mais lidos.
DIRETORIO_CACHE_API <- "dbf_sivep"

ARQUIVO_IBGE <- "sivep_15rs/ibge_cnv_pop.csv"
ARQUIVO_REGIONAIS_PR <- "sivep_15rs/parana_macrorregiao.csv"

CAMINHO_SHP_MUNICIPIOS <- "sivep_15rs/GIS/Pr_Municipios_2024/PR_Municipios_2024.shp"

# --- 0.5 Pasta de saída ---
DIR_GRAFICOS <- "graficos"

# --- 0.6 Data de extração ---
# Data de referência: mtime do CSV em cache (baixado da API) para o ano de
# análise, ou a data de hoje se ainda não tiver sido baixado nesta execução.
CAMINHO_CACHE_ANO_ANALISE <- file.path(DIRETORIO_CACHE_API, paste0("SRAG_API_", max(ANO_ANALISE), ".csv"))
DATA_EXTRACAO <- if (file.exists(CAMINHO_CACHE_ANO_ANALISE)) {
  as.Date(file.info(CAMINHO_CACHE_ANO_ANALISE)$mtime)
} else {
  Sys.Date()
}

# --- 0.7 API dados.gov.br (fonte única dos dados de SRAG) ---
ID_CONJUNTO_SRAG <- "39a4995f-4a6e-440f-8c8f-b00c81fae0d0"  # SRAG 2019 a 2026


# ==============================================================================
# BLOCO 1 — PACOTES
# ==============================================================================

pacotes <- c(
  "sf", "foreign", "dplyr", "ggplot2", "scales", "tidyr",
  "readr", "stringr", "lubridate", "forcats", "tmap", "writexl",
  "httr"
)

for (pkg in pacotes) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg)
  library(pkg, character.only = TRUE)
}


# ==============================================================================
# BLOCO 2 — MUNICÍPIOS E POPULAÇÕES DA 15ª RS
# ==============================================================================

municipios_15rs <- tibble::tribble(
  ~codigo_ibge_6, ~municipio,                     ~populacao_2025,
  410115,         "ANGULO",                        3357,
  410210,         "ASTORGA",                       26203,
  410220,         "ATALAIA",                       4046,
  410590,         "COLORADO",                      23313,
  410730,         "DOUTOR CAMARGO",                6517,
  410780,         "FLORAI",                        4805,
  410790,         "FLORESTA",                      11522,
  410810,         "FLORIDA",                       2711,
  411000,         "IGUARACU",                      5693,
  411090,         "ITAGUAJE",                      4530,
  411110,         "ITAMBE",                        6228,
  411160,         "IVATUBA",                       2685,
  411360,         "LOBATO",                        4707,
  411410,         "MANDAGUACU",                    34521,
  411420,         "MANDAGUARI",                    38313,
  411480,         "MARIALVA",                      44749,
  411520,         "MARINGA",                       429660,
  411630,         "MUNHOZ DE MELO",                4057,
  411640,         "NOSSA SENHORA DAS GRACAS",      3669,
  411690,         "NOVA ESPERANCA",                27142,
  411740,         "OURIZONA",                      3193,
  411750,         "PAICANDU",                      48695,
  411810,         "PARANACITY",                    9549,
  412040,         "PRESIDENTE CASTELO BRANCO",     4304,
  412340,         "SANTA FE",                      11730,
  412360,         "SANTA INES",                    1745,
  412450,         "SANTO INACIO",                  6463,
  412530,         "SAO JORGE DO IVAI",             5170,
  412625,         "SARANDI",                       128106,
  412830,         "UNIFLOR",                       2106
)

POPULACAO_15RS_TOTAL <- sum(municipios_15rs$populacao_2025)

message("Municípios: ", nrow(municipios_15rs),
        " | Pop. total: ", format(POPULACAO_15RS_TOTAL, big.mark = ".", decimal.mark = ","))


# ==============================================================================
# BLOCO 2B — TABELA DE REFERÊNCIA: MACRORREGIÃO / REGIONAL / MUNICÍPIO (PARANÁ)
# Cobre os 399 municípios do estado (fonte: IBGE 2022, tabela fornecida pelo
# usuário). Usada para expandir o filtro de estabelecimentos da seção
# "Notificações por estabelecimento" da 15RS para o Paraná inteiro.
# ==============================================================================
ref_regionais_pr <- readr::read_csv(ARQUIVO_REGIONAIS_PR, show_col_types = FALSE) %>%
  mutate(codigo_ibge_6 = as.integer(codigo_ibge_6))

message("Tabela de referência PR: ", nrow(ref_regionais_pr), " municípios, ",
        n_distinct(ref_regionais_pr$regional), " regionais, ",
        n_distinct(ref_regionais_pr$macrorregiao), " macrorregiões.")


# ==============================================================================
# BLOCO 3 — FUNÇÕES AUXILIARES
# ==============================================================================

if (!dir.exists(DIR_GRAFICOS)) dir.create(DIR_GRAFICOS, recursive = TRUE)
message("Saída: ", DIR_GRAFICOS)

texto_rodape <- paste0(
  "Fonte: SIVEP-Gripe | Dados: ", format(DATA_EXTRACAO, "%d/%m/%Y"),
  " | Atualizado: ", format(Sys.Date(), "%d/%m/%Y")
)

salvar_grafico <- function(grafico, nome_arquivo, width = 12, height = 7) {
  caminho <- file.path(DIR_GRAFICOS, paste0(nome_arquivo, ".png"))
  ggsave(
    filename = caminho, plot = grafico,
    width = width, height = height, units = "in", dpi = 150, bg = "white"
  )
  message("Salvo: ", caminho)
}

# ------------------------------------------------------------------------------
# NOVO — Integração com a API do dados.gov.br
# ------------------------------------------------------------------------------

obter_token_dados_gov <- function() {
  token <- Sys.getenv("DADOS_GOV_TOKEN")
  if (token == "") {
    stop(
      "DADOS_GOV_TOKEN não configurado. Adicione a linha ",
      "DADOS_GOV_TOKEN=seu_token em ~/.Renviron e rode readRenviron('~/.Renviron')."
    )
  }
  token
}

localizar_recurso_ano <- function(ano, formato = "CSV") {
  token <- obter_token_dados_gov()

  resp <- httr::GET(
    paste0("https://dados.gov.br/dados/api/publico/conjuntos-dados/", ID_CONJUNTO_SRAG),
    httr::add_headers(`chave-api-dados-abertos` = token)
  )
  if (httr::status_code(resp) != 200) {
    stop("Falha ao consultar a API (status ", httr::status_code(resp), ").")
  }

  recursos <- httr::content(resp, as = "parsed")$recursos
  link <- NULL
  for (r in recursos) {
    formato_ok <- !is.null(r$formato) && toupper(r$formato) == toupper(formato)
    titulo_ok  <- !is.null(r$titulo)  && grepl(as.character(ano), r$titulo)
    if (formato_ok && titulo_ok) link <- r$link
  }
  if (is.null(link)) stop("Recurso ", formato, " de ", ano, " não encontrado na API.")
  link
}

baixar_via_api <- function(ano, diretorio_cache) {
  link    <- localizar_recurso_ano(ano, "CSV")
  destino <- file.path(diretorio_cache, paste0("SRAG_API_", ano, ".csv"))

  if (!dir.exists(diretorio_cache)) dir.create(diretorio_cache, recursive = TRUE)

  # Anos encerrados (ex.: 2019-2025) ficam em cache pra sempre, já que os
  # dados não mudam mais. O ano corrente é rebaixado uma vez por dia, porque
  # os casos continuam sendo notificados.
  ano_corrente   <- lubridate::year(Sys.Date())
  cache_e_hoje   <- file.exists(destino) &&
    as.Date(file.info(destino)$mtime) == Sys.Date()
  precisa_baixar <- !file.exists(destino) || (ano == ano_corrente && !cache_e_hoje)

  if (precisa_baixar) {
    message("  Baixando via API dados.gov.br: ", link)
    temp <- paste0(destino, ".tmp")
    erro_download <- tryCatch({
      download.file(link, destfile = temp, mode = "wb")
      NULL
    }, error = function(e) e)

    if (!is.null(erro_download) || !file.exists(temp)) {
      # Download falhou: descarta o arquivo temporário. Se já existia um
      # cache anterior (ex.: de ontem), mantém ele em vez de apagar dados
      # bons; só falha de vez se nunca existiu cache nenhum pra esse ano.
      if (file.exists(temp)) unlink(temp)
      if (!file.exists(destino)) {
        stop("Falha ao baixar ", ano, ": ",
             if (!is.null(erro_download)) conditionMessage(erro_download) else "arquivo não foi criado")
      }
      message("  [aviso] Falha ao atualizar ", ano, " — mantendo cache anterior (",
              basename(destino), ")")
    } else {
      file.rename(temp, destino)
    }
  } else {
    message(
      "  [cache] Usando CSV já baixado (", basename(destino), ")",
      if (ano == ano_corrente) " — atualizado hoje" else " — ano encerrado, não muda mais"
    )
  }

  # [Não verificado] assume separador ";" e encoding latin1, padrão histórico
  # do SIVEP-Gripe/SRAG. Se der erro de parsing, confira o dicionário de dados:
  # https://s3.sa-east-1.amazonaws.com/ckan.saude.gov.br/SRAG/dicionario-de-dados-2019-a-2025.pdf
  readr::read_delim(
    destino, delim = ";",
    locale    = readr::locale(encoding = "latin1"),
    col_types = readr::cols(.default = "c"),
    progress  = FALSE
  )
}

# validar_campos_dbf_api(): compara os nomes de coluna do DBF local com os do
# CSV público da API para um dado ano, sem baixar o arquivo inteiro (lê só o
# cabeçalho via conexão). Use isso ANTES de confiar no fallback abaixo — não
# há garantia de que os dois têm exatamente os mesmos campos (por exemplo,
# NM_BAIRRO pode existir só na base interna da regional).
validar_campos_dbf_api <- function(ano, diretorio_dbf = DIRETORIO_CACHE_API) {

  caminho_dbf <- file.path(diretorio_dbf, paste0("SRAGHOSP", ano, ".dbf"))
  if (!file.exists(caminho_dbf)) {
    stop("DBF local de ", ano, " não encontrado em ", diretorio_dbf, " — não dá pra comparar.")
  }
  dbf_amostra <- foreign::read.dbf(caminho_dbf, as.is = TRUE)
  nomes_dbf   <- toupper(names(dbf_amostra))

  link <- localizar_recurso_ano(ano, "CSV")
  con  <- url(link, method = "libcurl", encoding = "latin1")
  cabecalho <- readLines(con, n = 1, warn = FALSE)
  close(con)

  nomes_api <- toupper(strsplit(cabecalho, ";")[[1]])
  nomes_api <- trimws(gsub('"', '', nomes_api))

  em_comum  <- intersect(nomes_dbf, nomes_api)
  so_no_dbf <- setdiff(nomes_dbf, nomes_api)
  so_na_api <- setdiff(nomes_api, nomes_dbf)

  cat("=== Comparação de campos — SRAG", ano, "===\n")
  cat("Total no DBF local :", length(nomes_dbf), "\n")
  cat("Total no CSV da API:", length(nomes_api), "\n")
  cat("Em comum (", length(em_comum), "):\n  ", paste(sort(em_comum), collapse = ", "), "\n\n", sep = "")
  cat("Só no DBF local (", length(so_no_dbf), "):\n  ", paste(sort(so_no_dbf), collapse = ", "), "\n\n", sep = "")
  cat("Só no CSV da API (", length(so_na_api), "):\n  ", paste(sort(so_na_api), collapse = ", "), "\n", sep = "")

  invisible(list(comum = em_comum, so_dbf = so_no_dbf, so_api = so_na_api))
}

# carregar_base(): baixa sempre o CSV via API dados.gov.br. DBFs locais não
# são mais lidos — todo o carregamento passa pela API.
carregar_base <- function(ano, diretorio) {
  message("  Baixando via API dados.gov.br (SRAG ", ano, ")...")
  df <- tryCatch(
    baixar_via_api(ano, diretorio),
    error = function(e) {
      message("  [erro] Falha ao baixar via API para ", ano, ": ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(df)) {
    message("  [OK] ", nrow(df), " registros (via API)")
    df$ANO_BASE <- ano
  }
  df
}

parseia_data <- function(x) {
  if (inherits(x, "Date")) return(x)
  d <- as.Date(as.character(x), format = "%d/%m/%Y")
  if (sum(!is.na(d)) > 0) return(d)
  as.Date(as.character(x), format = "%Y-%m-%d")
}

criar_faixa_etaria <- function(df) {
  df %>% mutate(
    faixa_etaria = case_when(
      is.na(COD_IDADE)  ~ "Em branco/Ignorado",
      COD_IDADE <= 2005 ~ "0-6 meses",
      COD_IDADE <= 2011 ~ "6-11 meses",
      COD_IDADE <= 3004 ~ "1-4 anos",
      COD_IDADE <= 3009 ~ "5-9 anos",
      COD_IDADE <= 3014 ~ "10-14 anos",
      COD_IDADE <= 3019 ~ "15-19 anos",
      COD_IDADE <= 3029 ~ "20-29 anos",
      COD_IDADE <= 3039 ~ "30-39 anos",
      COD_IDADE <= 3049 ~ "40-49 anos",
      COD_IDADE <= 3059 ~ "50-59 anos",
      COD_IDADE >= 3060 ~ "60 anos e mais",
      TRUE              ~ "Erro/Outro"
    )
  )
}

padronizar_sexo <- function(df) {
  df %>% mutate(
    sexo = case_when(
      CS_SEXO %in% c("M", "m", "1", 1) ~ "Masculino",
      CS_SEXO %in% c("F", "f", "2", 2) ~ "Feminino",
      TRUE                              ~ "Ignorado"
    )
  )
}

ORDEM_FAIXAS <- c(
  "0-6 meses", "6-11 meses", "1-4 anos", "5-9 anos",
  "10-14 anos", "15-19 anos", "20-29 anos", "30-39 anos",
  "40-49 anos", "50-59 anos", "60 anos e mais",
  "Em branco/Ignorado", "Erro/Outro"
)

# ==============================================================================
# BLOCO 4 — CARREGAMENTO E LIMPEZA DOS DADOS
# ==============================================================================

anos_disponiveis <- 2019:2026

anos_carregar <- if (!is.null(ANO_ANALISE)) intersect(ANO_ANALISE, anos_disponiveis) else anos_disponiveis

anos_curva <- if (is.null(ANO_ANALISE)) {
  anos_disponiveis
} else if (length(ANO_ANALISE) == 1) {
  intersect(seq(ANO_ANALISE - 2, ANO_ANALISE), anos_disponiveis)
} else {
  intersect(ANO_ANALISE, anos_disponiveis)
}

anos_a_carregar <- sort(union(anos_carregar, anos_curva))

message("\nCarregando anos: ", paste(anos_a_carregar, collapse = ", "))

lista_bases <- Filter(Negate(is.null),
                      lapply(anos_a_carregar, carregar_base, diretorio = DIRETORIO_CACHE_API))

if (length(lista_bases) == 0) stop("Nenhuma base carregada. Verifique a conexão com a API dados.gov.br e o token DADOS_GOV_TOKEN.")

base_completa <- bind_rows(lista_bases)
names(base_completa) <- toupper(names(base_completa))

message("Total de registros: ", format(nrow(base_completa), big.mark = ".", decimal.mark = ","))

base_completa <- base_completa %>%
  mutate(
    CO_MUN_RES     = as.integer(CO_MUN_RES),
    DT_NOTIFIC_DT  = parseia_data(DT_NOTIFIC),
    ANO            = lubridate::year(DT_NOTIFIC_DT),
    SEM_EPI        = as.integer(SEM_NOT),
    CLASSIFICACAO  = case_when(
      CLASSI_FIN == 1 ~ "Influenza",
      CLASSI_FIN == 2 ~ "Outro vírus respiratório",
      CLASSI_FIN == 3 ~ "Outro agente etiológico",
      CLASSI_FIN == 4 ~ "SRAG não especificada",
      CLASSI_FIN == 5 ~ "COVID-19",
      TRUE            ~ "Não classificado"
    ),
    OBITO_SRAG   = EVOLUCAO == 2,
    OBITO_OUTRAS = EVOLUCAO == 3,
    UTI_SIM      = UTI == 1
  )

base_15rs_completa <- base_completa %>%
  filter(CO_MUN_RES %in% municipios_15rs$codigo_ibge_6)

base_ano_principal <- base_15rs_completa %>% filter(ANO_BASE %in% anos_carregar)

if (!is.null(MUNICIPIO_ANALISE) && nzchar(trimws(MUNICIPIO_ANALISE))) {
  cod_mun <- municipios_15rs %>%
    filter(toupper(municipio) == toupper(trimws(MUNICIPIO_ANALISE))) %>%
    pull(codigo_ibge_6)
  base_filtrada <- base_ano_principal %>% filter(CO_MUN_RES == cod_mun)
  POPULACAO_ESCOPO <- municipios_15rs %>%
    filter(codigo_ibge_6 == cod_mun) %>% pull(populacao_2025)
  escopo_titulo <- paste0(tools::toTitleCase(tolower(MUNICIPIO_ANALISE)),
                          " — 15ª RS Maringá")
} else {
  base_filtrada    <- base_ano_principal
  POPULACAO_ESCOPO <- POPULACAO_15RS_TOTAL
  escopo_titulo    <- "15ª Regional de Saúde de Maringá"
}

anos_contexto <- setdiff(as.character(anos_curva), as.character(anos_carregar))

message("Escopo    : ", escopo_titulo)
message("Registros : ", format(nrow(base_filtrada), big.mark = ".", decimal.mark = ","))
message("Pop. IBGE : ", format(POPULACAO_ESCOPO, big.mark = ".", decimal.mark = ","))


# ==============================================================================
# BLOCO 4b — CARGA HISTÓRICA PARA ANÁLISE VIRAL
# ==============================================================================

anos_virus_historico <- setdiff(2019:(max(anos_carregar) - 1), anos_a_carregar)

if (length(anos_virus_historico) > 0) {
  message("\nCarregando anos históricos para gráfico de vírus: ",
          paste(anos_virus_historico, collapse = ", "))

  lista_bases_hist <- Filter(Negate(is.null),
                             lapply(anos_virus_historico, carregar_base,
                                    diretorio = DIRETORIO_CACHE_API))

  if (length(lista_bases_hist) > 0) {
    base_hist_extra <- bind_rows(lista_bases_hist)
    names(base_hist_extra) <- toupper(names(base_hist_extra))
    base_hist_extra <- base_hist_extra %>%
      mutate(CO_MUN_RES = as.integer(CO_MUN_RES))

    base_15rs_historica <- bind_rows(
      base_15rs_completa,
      base_hist_extra %>% filter(CO_MUN_RES %in% municipios_15rs$codigo_ibge_6)
    )
    message("[OK] base_15rs_historica: ",
            n_distinct(base_15rs_historica$ANO_BASE), " anos | ",
            format(nrow(base_15rs_historica), big.mark = ".", decimal.mark = ","), " registros")
  } else {
    base_15rs_historica <- base_15rs_completa
    message("  [aviso] Nenhum ano histórico adicional encontrado.")
  }
} else {
  base_15rs_historica <- base_15rs_completa
}


# ==============================================================================
# BLOCO 5 — AGREGAÇÕES PARA MAPAS
# ==============================================================================

casos_municipio <- base_15rs_completa %>%
  filter(ANO_BASE %in% anos_carregar) %>%
  group_by(CO_MUN_RES) %>%
  summarise(
    casos         = n(),
    obitos_srag   = sum(OBITO_SRAG,   na.rm = TRUE),
    obitos_outras = sum(OBITO_OUTRAS, na.rm = TRUE),
    uti           = sum(UTI_SIM,      na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(municipios_15rs, by = c("CO_MUN_RES" = "codigo_ibge_6")) %>%
  mutate(
    incidencia_100k  = round(casos       / populacao_2025 * 100000, 1),
    mortalidade_100k = round(obitos_srag / populacao_2025 * 100000, 1),
    letalidade_pct   = round(obitos_srag / casos          * 100,    1)
  ) %>%
  arrange(desc(incidencia_100k))

casos_semana_class <- base_filtrada %>%
  filter(!is.na(SEM_EPI)) %>%
  group_by(SEM_EPI, CLASSIFICACAO) %>%
  summarise(casos = n(), .groups = "drop") %>%
  arrange(SEM_EPI)


# ==============================================================================
# GRÁFICO 06 — CURVA EPIDÊMICA COMPARATIVA
# ==============================================================================

base_curva <- base_15rs_completa %>%
  filter(ANO_BASE %in% anos_curva) %>%
  { if (!is.null(MUNICIPIO_ANALISE)) filter(., CO_MUN_RES == cod_mun) else . }

casos_semana_ano <- base_curva %>%
  mutate(
    Ano    = as.character(ANO_BASE),
    Semana = as.integer(SEM_NOT)
  ) %>%
  filter(!is.na(Semana)) %>%
  group_by(Ano, Semana) %>%
  summarise(Total = n(), .groups = "drop")

if (nrow(casos_semana_ano) > 0) {
  todos_anos    <- sort(unique(casos_semana_ano$Ano))
  anos_destaque <- as.character(anos_carregar)
  paleta        <- c("#E63946","#F4A261","#2A9D8F","#457B9D","#6A0572","#E9C46A","#264653","#A8DADC")
  cores_curva   <- setNames(paleta[seq_along(todos_anos)], todos_anos)
  espessuras    <- setNames(ifelse(todos_anos %in% anos_destaque, 2.2, 0.9), todos_anos)

  n_por_ano  <- casos_semana_ano %>% group_by(Ano) %>% summarise(n = sum(Total), .groups = "drop")
  rotulos    <- setNames(paste0(n_por_ano$Ano, "  (N = ", format(n_por_ano$n, big.mark = ".", decimal.mark = ","), ")"),
                         n_por_ano$Ano)

  g06 <- ggplot(casos_semana_ano,
                aes(x = Semana, y = Total, group = Ano, color = Ano, linewidth = Ano)) +
    geom_line(alpha = 0.9) +
    geom_point(size = 1.2, alpha = 0.85) +
    scale_color_manual(values = cores_curva, labels = rotulos) +
    scale_linewidth_manual(values = espessuras, guide = "none") +
    scale_x_continuous(breaks = seq(1, 52, by = 4), limits = c(1, 53)) +
    labs(
      title    = paste0("Curva Epidêmica Comparativa — ", escopo_titulo),
      subtitle = paste0("Ano(s) em análise: ", paste(anos_carregar, collapse = ", "),
                        " | Contexto histórico: ", paste(anos_contexto, collapse = ", ")),
      x = "Semana Epidemiológica", y = "Casos Notificados",
      color = "Ano", caption = texto_rodape
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"), legend.position = "right")

  salvar_grafico(g06, "06_curva_epidemica_comparativa")
}


# ==============================================================================
# GRÁFICO 06b — CANAL ENDÊMICO COM PERCENTIS HISTÓRICOS (PÓS-PANDEMIA)
# ==============================================================================

ano_atual <- max(anos_carregar)

anos_historico <- setdiff(
  intersect(ANO_INICIO_CANAL:(ano_atual - 1), anos_disponiveis),
  anos_carregar
)

message("Canal endêmico — anos de referência: ", paste(anos_historico, collapse = ", "))

if (length(anos_historico) < 2) {
  message("  [aviso] Menos de 2 anos de referência — canal endêmico não gerado.")
} else {

  base_historico <- base_15rs_completa %>%
    filter(ANO_BASE %in% anos_historico) %>%
    { if (!is.null(MUNICIPIO_ANALISE) && nzchar(trimws(MUNICIPIO_ANALISE)))
      filter(., CO_MUN_RES == cod_mun) else . } %>%
    mutate(Semana = as.integer(SEM_NOT)) %>%
    filter(!is.na(Semana)) %>%
    group_by(ANO_BASE, Semana) %>%
    summarise(total = n(), .groups = "drop")

  canal <- base_historico %>%
    group_by(Semana) %>%
    summarise(
      mediana = median(total),
      p25     = quantile(total, 0.25),
      p75     = quantile(total, 0.75),
      p90     = quantile(total, 0.90),
      n_anos  = n_distinct(ANO_BASE),
      .groups = "drop"
    )

  serie_atual <- base_15rs_completa %>%
    filter(ANO_BASE %in% anos_carregar) %>%
    { if (!is.null(MUNICIPIO_ANALISE) && nzchar(trimws(MUNICIPIO_ANALISE)))
      filter(., CO_MUN_RES == cod_mun) else . } %>%
    mutate(Semana = as.integer(SEM_NOT)) %>%
    filter(!is.na(Semana)) %>%
    group_by(Semana) %>%
    summarise(total = n(), .groups = "drop")

  serie_atual <- serie_atual %>%
    left_join(canal, by = "Semana") %>%
    mutate(
      zona = case_when(
        total > p90  ~ "Epidêmico",
        total > p75  ~ "Alerta",
        total >= p25 ~ "Esperado",
        TRUE         ~ "Abaixo do esperado"
      ),
      zona = factor(zona, levels = c(
        "Epidêmico", "Alerta", "Esperado", "Abaixo do esperado"
      ))
    )

  cores_zona <- c(
    "Epidêmico"          = "#C62828",
    "Alerta"             = "#FF8F00",
    "Esperado"           = "#2E7D32",
    "Abaixo do esperado" = "#1565C0"
  )

  n_atual    <- sum(serie_atual$total)
  n_anos_ref <- length(anos_historico)
  label_ref  <- paste0(min(anos_historico), "–", max(anos_historico))
  semanas_ep <- sum(serie_atual$zona %in% c("Epidêmico", "Alerta"), na.rm = TRUE)

  g06b <- ggplot() +
    geom_ribbon(data = canal, aes(x = Semana, ymin = p75, ymax = p90),
                fill = "#FFECB3", alpha = 0.85) +
    geom_ribbon(data = canal, aes(x = Semana, ymin = p25, ymax = p75),
                fill = "#C8E6C9", alpha = 0.85) +
    geom_line(data = canal, aes(x = Semana, y = mediana),
              color = "#388E3C", linewidth = 0.8, linetype = "dashed") +
    geom_line(data = serie_atual, aes(x = Semana, y = total),
              color = "#1A237E", linewidth = 1.2) +
    geom_point(data = serie_atual, aes(x = Semana, y = total, color = zona), size = 3) +
    geom_text(data = serie_atual, aes(x = Semana, y = total, label = total),
              vjust = -0.8, size = 2.8, color = "grey30") +
    scale_color_manual(values = cores_zona, name = "Zona") +
    scale_x_continuous(breaks = seq(1, 53, by = 4), limits = c(1, 53)) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
    labs(
      title    = paste0("Canal Endêmico de SRAG — ", escopo_titulo,
                        " (", ano_atual, " | N = ", format(n_atual, big.mark = ".", decimal.mark = ","), ")"),
      subtitle = paste0(
        "Zona verde = esperado (P25–P75)  |  Zona amarela = alerta (P75–P90)  |  Acima = epidêmico (> P90)\n",
        "Referência pós-pandêmica: ", label_ref, " (", n_anos_ref, " anos)  |  ",
        "Semanas em alerta ou acima: ", semanas_ep
      ),
      x = "Semana Epidemiológica", y = "Casos Notificados", caption = texto_rodape
    ) +
    theme_minimal() +
    theme(
      plot.title    = element_text(face = "bold"),
      plot.subtitle = element_text(size = 8.5, color = "grey40", lineheight = 1.3),
      legend.position = "bottom"
    )

  salvar_grafico(g06b, "06b_canal_endemico")
}


# ==============================================================================
# GRÁFICO 07 — NOTIFICAÇÕES POR SEMANA EPIDEMIOLÓGICA
# ==============================================================================

casos_semana <- base_filtrada %>%
  group_by(SEM_NOT) %>%
  summarise(total = n(), .groups = "drop")

n_semana   <- sum(casos_semana$total)
incid_100k <- round(n_semana / POPULACAO_ESCOPO * 100000, 1)

g07 <- ggplot(casos_semana, aes(x = factor(SEM_NOT), y = total)) +
  geom_col(fill = "#0057A3") +
  geom_text(aes(label = total), vjust = -0.5, size = 3.2) +
  labs(
    title    = paste0("SRAG por Semana Epidemiológica — ", escopo_titulo,
                      " (N = ", format(n_semana, big.mark = ".", decimal.mark = ","), ")"),
    subtitle = paste0("N = ", format(n_semana, big.mark = ".", decimal.mark = ","),
                      " | Taxa: ", incid_100k, " por 100.000 hab.",
                      " | Pop. IBGE 2025: ", format(POPULACAO_ESCOPO, big.mark = ".", decimal.mark = ",")),
    x = "Semana Epidemiológica", y = "Notificações", caption = texto_rodape
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

salvar_grafico(g07, "07_notificacoes_semana_epi")


# ==============================================================================
# GRÁFICO 07b — VARIAÇÃO SEMANAL COM MÉDIA E TENDÊNCIA
# ==============================================================================

casos_semana_var <- base_filtrada %>%
  group_by(SEM_NOT) %>%
  summarise(total = n(), .groups = "drop") %>%
  arrange(SEM_NOT) %>%
  mutate(
    media    = round(mean(total), 1),
    variacao = round((total - lag(total)) / lag(total) * 100, 1),
    direcao  = case_when(
      is.na(variacao) ~ "neutra",
      variacao > 0    ~ "aumento",
      variacao < 0    ~ "reducao",
      TRUE            ~ "neutra"
    )
  )

g07b <- ggplot(casos_semana_var, aes(x = as.integer(SEM_NOT), y = total)) +
  geom_col(aes(fill = direcao), width = 0.7) +
  geom_line(aes(y = media), color = "#FF8C00", linewidth = 1, linetype = "dashed") +
  geom_text(
    aes(label = ifelse(!is.na(variacao),
                       paste0(ifelse(variacao > 0, "+", ""), variacao, "%"), "")),
    vjust = -0.5, size = 2.8, color = "grey30"
  ) +
  annotate("text", x = 1, y = unique(casos_semana_var$media) * 1.03,
           label = paste0("Média: ", unique(casos_semana_var$media)),
           hjust = 0, size = 3, color = "#FF8C00", fontface = "italic") +
  scale_fill_manual(
    values = c("aumento" = "#C62828", "reducao" = "#2E7D32", "neutra" = "#0057A3"),
    guide  = "none"
  ) +
  scale_x_continuous(breaks = seq(1, 53, by = 2)) +
  labs(
    title    = paste0("Variação Semanal de SRAG — ", escopo_titulo),
    subtitle = "Vermelho = aumento | Verde = redução | Laranja tracejado = média do período",
    x = "Semana Epidemiológica", y = "Casos Notificados", caption = texto_rodape
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

salvar_grafico(g07b, "07b_variacao_semanal")


# ==============================================================================
# GRÁFICO 08 — CONFIRMADOS POR SEMANA EPIDEMIOLÓGICA
# ==============================================================================

confirmados_semana <- base_filtrada %>%
  filter(CLASSI_FIN %in% c(1, 2, 3, 5)) %>%
  group_by(SEM_NOT) %>%
  summarise(total = n(), .groups = "drop")

n_conf <- sum(confirmados_semana$total)

g08 <- ggplot(confirmados_semana, aes(x = factor(SEM_NOT), y = total)) +
  geom_col(fill = "#A30000") +
  geom_text(aes(label = total), vjust = -0.5, size = 3.2) +
  labs(
    title    = paste0("SRAG Confirmado por Semana Epidemiológica — ", escopo_titulo,
                      " (N = ", format(n_conf, big.mark = ".", decimal.mark = ","), ")"),
    subtitle = paste0("N = ", format(n_conf, big.mark = ".", decimal.mark = ",")),
    x = "Semana Epidemiológica", y = "Casos Confirmados", caption = texto_rodape
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

salvar_grafico(g08, "08_confirmados_semana_epi")


# ==============================================================================
# GRÁFICO 09 — INCIDÊNCIA POR MUNICÍPIO
# ==============================================================================

g09 <- casos_municipio %>%
  mutate(
    municipio = fct_reorder(str_to_title(municipio), incidencia_100k),
    rotulo    = paste0(incidencia_100k, " /100k  (n=", casos, ")")
  ) %>%
  ggplot(aes(x = incidencia_100k, y = municipio)) +
  geom_col(fill = "#1A5C38") +
  geom_text(aes(label = rotulo), hjust = -0.05, size = 3) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.25))) +
  labs(
    title    = paste0("Taxa de Incidência de SRAG por Município — 15ª RS Maringá",
                      " (N = ", format(sum(casos_municipio$casos), big.mark = ".", decimal.mark = ","), ")"),
    subtitle = paste0("Por 100.000 habitantes | Pop. IBGE 2025",
                      " | Pop. total: ", format(POPULACAO_15RS_TOTAL, big.mark = ".", decimal.mark = ","),
                      " | Ano(s): ", paste(anos_carregar, collapse = ", ")),
    x = "Incidência por 100.000 hab.", y = "Município", caption = texto_rodape
  ) +
  theme_minimal()

salvar_grafico(g09, "09_incidencia_por_municipio", height = 10)


# ==============================================================================
# GRÁFICO 10 — NOTIFICAÇÕES POR REGIONAL DE SAÚDE (PARANÁ)
# ==============================================================================

# Filtra por SG_UF_NOT == "PR" (não pelo número no início de ID_REGIONA):
# a base é nacional e outros estados também numeram suas regionais de 1 a 22
# (ex.: PE usa "001", "002"...; RS usa "001 CRS"...), então filtrar só pelo
# número deixava passar regionais de outros estados junto com as do Paraná.
base_pr <- base_completa %>%
  mutate(
    SG_UF_NOT  = toupper(trimws(SG_UF_NOT)),
    ID_REGIONA = toupper(trimws(ID_REGIONA))
  ) %>%
  filter(SG_UF_NOT == "PR", !is.na(ID_REGIONA), nzchar(ID_REGIONA),
         ANO_BASE %in% anos_carregar)
# Nota: base_pr agora deriva de base_completa (já com CO_MUN_RES como inteiro,
# SEM_EPI, CLASSIFICACAO, OBITO_SRAG, UTI_SIM etc.), em vez de bind_rows(lista_bases)
# cru — mesmas linhas de antes, só que com as colunas derivadas necessárias para
# o export por estabelecimento (abaixo). O Gráfico 10 não muda.

if ("ID_REGIONA" %in% names(base_pr) && nrow(base_pr) > 0) {
  casos_regional <- base_pr %>%
    group_by(ID_REGIONA) %>%
    summarise(total = n(), .groups = "drop") %>%
    arrange(desc(total))

  n_pr <- sum(casos_regional$total)

  g10 <- ggplot(casos_regional,
                aes(x = total, y = fct_reorder(ID_REGIONA, total))) +
    geom_col(fill = "#0057A3") +
    geom_text(aes(label = format(total, big.mark = ".", decimal.mark = ",")), hjust = -0.1, size = 3) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(
      title    = paste0("Notificações de SRAG por Regional de Saúde — Paraná",
                        " (N = ", format(n_pr, big.mark = ".", decimal.mark = ","), ")"),
      subtitle = paste(anos_carregar, collapse = ", "),
      x = "Total de Notificações", y = "Regional de Saúde", caption = texto_rodape
    ) +
    theme_minimal()

  salvar_grafico(g10, "10_notificacoes_regionais_pr", height = 10)
}


# ==============================================================================
# GRÁFICO 11 — DISTRIBUIÇÃO POR SEXO
# ==============================================================================

casos_sexo <- base_filtrada %>%
  padronizar_sexo() %>%
  filter(sexo != "Ignorado") %>%
  group_by(sexo) %>%
  summarise(total = n(), .groups = "drop") %>%
  mutate(pct = round(total / sum(total) * 100, 1))

n_sexo <- sum(casos_sexo$total)

g11 <- ggplot(casos_sexo, aes(x = total, y = sexo, fill = sexo)) +
  geom_col() +
  geom_text(aes(label = paste0(total, " (", pct, "%)")), hjust = -0.1, size = 4) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.2))) +
  scale_fill_manual(values = c("Masculino" = "#0057A3", "Feminino" = "#E91E8C")) +
  labs(
    title    = paste0("Distribuição por Sexo — ", escopo_titulo,
                      " (N = ", format(n_sexo, big.mark = ".", decimal.mark = ","), ")"),
    x = "Notificações", y = NULL, fill = "Sexo", caption = texto_rodape
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

salvar_grafico(g11, "11_distribuicao_sexo", height = 4)


# ==============================================================================
# GRÁFICO 12 — CLASSIFICAÇÃO FINAL
# ==============================================================================

casos_class <- base_filtrada %>%
  mutate(
    class_label = case_when(
      CLASSI_FIN == 1 ~ "SRAG por Influenza",
      CLASSI_FIN == 2 ~ "SRAG por Outro Vírus Respiratório",
      CLASSI_FIN == 3 ~ "SRAG por Outro Agente Etiológico",
      CLASSI_FIN == 4 ~ "SRAG Não Especificado",
      CLASSI_FIN == 5 ~ "SRAG por Covid-19",
      TRUE            ~ "Em Investigação"
    )
  ) %>%
  group_by(class_label) %>%
  summarise(total = n(), .groups = "drop") %>%
  arrange(desc(total))

n_class <- sum(casos_class$total)

g12 <- ggplot(casos_class,
              aes(x = total, y = fct_reorder(class_label, total))) +
  geom_col(fill = "#0057A3") +
  geom_text(aes(label = total), hjust = -0.1, size = 4) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title    = paste0("Classificação Final — ", escopo_titulo,
                      " (N = ", format(n_class, big.mark = ".", decimal.mark = ","), ")"),
    x = "Total de Notificações", y = "Classificação", caption = texto_rodape
  ) +
  theme_minimal()

salvar_grafico(g12, "12_classificacao_final")


# ==============================================================================
# GRÁFICO 13 — CIRCULAÇÃO VIRAL TOTAL (RT-PCR)
# ==============================================================================

viral_wide <- base_filtrada %>%
  filter(PCR_RESUL == 1 | POS_PCRFLU == 1 | POS_PCROUT == 1) %>%
  mutate(
    Influenza        = POS_PCRFLU == 1,
    VSR              = PCR_VSR    == 1,
    `Rinovírus`      = PCR_RINO   == 1,
    `Adenovírus`     = PCR_ADENO  == 1,
    `Metapneumovírus`= PCR_METAP  == 1,
    `Parainfluenza 1`= PCR_PARA1  == 1,
    `Parainfluenza 2`= PCR_PARA2  == 1,
    `Parainfluenza 3`= PCR_PARA3  == 1,
    `Parainfluenza 4`= PCR_PARA4  == 1,
    `Covid-19`       = PCR_SARS2  == 1
  )

circulacao_viral <- viral_wide %>%
  summarise(across(Influenza:`Covid-19`, ~ sum(.x, na.rm = TRUE))) %>%
  tidyr::pivot_longer(everything(), names_to = "virus", values_to = "total") %>%
  filter(total > 0) %>%
  arrange(desc(total))

n_viral <- sum(circulacao_viral$total)

g13 <- ggplot(circulacao_viral,
              aes(x = total, y = fct_reorder(virus, total))) +
  geom_col(fill = "#0057A3") +
  geom_text(aes(label = total), hjust = -0.1, size = 4) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title    = paste0("Vírus Identificados por RT-PCR — ", escopo_titulo,
                      " (N = ", format(n_viral, big.mark = ".", decimal.mark = ","), ")"),
    x = "Casos Positivos", y = "Vírus", caption = texto_rodape
  ) +
  theme_minimal()

salvar_grafico(g13, "13_circulacao_viral_total")


# ==============================================================================
# GRÁFICO 14 — TENDÊNCIA SEMANAL DE VÍRUS RESPIRATÓRIOS
# ==============================================================================

virus_semanal <- base_filtrada %>%
  filter(!is.na(SEM_NOT)) %>%
  mutate(
    Influenza       = POS_PCRFLU == 1,
    VSR             = PCR_VSR    == 1,
    `Rinovírus`     = PCR_RINO   == 1,
    `Adenovírus`    = PCR_ADENO  == 1,
    `Metapneumovírus`= PCR_METAP == 1,
    `Covid-19`      = PCR_SARS2  == 1
  ) %>%
  tidyr::pivot_longer(
    cols      = c(Influenza, VSR, `Rinovírus`, `Adenovírus`, `Metapneumovírus`, `Covid-19`),
    names_to  = "virus",
    values_to = "positivo"
  ) %>%
  filter(positivo == TRUE) %>%
  group_by(SEM_NOT, virus) %>%
  summarise(total = n(), .groups = "drop")

if (nrow(virus_semanal) > 0) {
  n_semanal <- nrow(base_filtrada %>% filter(POS_PCRFLU == 1 | POS_PCROUT == 1))

  g14 <- ggplot(virus_semanal,
                aes(x = as.integer(SEM_NOT), y = total, color = virus, group = virus)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 1.5, alpha = 0.8) +
    scale_x_continuous(breaks = seq(1, 53, by = 4)) +
    scale_color_brewer(palette = "Set1") +
    labs(
      title    = paste0("Tendência Semanal de Vírus Respiratórios — ", escopo_titulo,
                        " (N = ", format(n_semanal, big.mark = ".", decimal.mark = ","), ")"),
      subtitle = "Influenza, Covid-19, VSR, Rinovírus, Adenovírus, Metapneumovírus",
      x = "Semana Epidemiológica", y = "Casos Positivos",
      color = "Vírus", caption = texto_rodape
    ) +
    theme_minimal() +
    theme(legend.position = "bottom")

  salvar_grafico(g14, "14_tendencia_viral_semanal")
}


# ==============================================================================
# GRÁFICO D13 — VÍRUS PREDOMINANTE POR FAIXA ETÁRIA
# ==============================================================================

virus_faixa_wide <- base_filtrada %>%
  criar_faixa_etaria() %>%
  filter(faixa_etaria %in% ORDEM_FAIXAS[1:11]) %>%
  mutate(
    faixa_etaria    = factor(faixa_etaria, levels = ORDEM_FAIXAS),
    Influenza       = POS_PCRFLU == 1,
    VSR             = PCR_VSR    == 1,
    `Covid-19`      = PCR_SARS2  == 1,
    `Rinovírus`     = PCR_RINO   == 1,
    `Adenovírus`    = PCR_ADENO  == 1,
    `Metapneumovírus`= PCR_METAP == 1,
    Parainfluenza   = (PCR_PARA1 == 1 | PCR_PARA2 == 1 |
                         PCR_PARA3 == 1 | PCR_PARA4 == 1)
  )

virus_faixa_long <- virus_faixa_wide %>%
  tidyr::pivot_longer(
    cols      = c(Influenza, VSR, `Covid-19`, `Rinovírus`,
                  `Adenovírus`, `Metapneumovírus`, Parainfluenza),
    names_to  = "virus",
    values_to = "positivo"
  ) %>%
  filter(positivo == TRUE) %>%
  group_by(faixa_etaria, virus) %>%
  summarise(n = n(), .groups = "drop")

virus_faixa_prop <- virus_faixa_long %>%
  group_by(faixa_etaria) %>%
  mutate(total_faixa = sum(n), pct = round(n / total_faixa * 100, 1)) %>%
  ungroup()

n_por_faixa <- virus_faixa_prop %>%
  distinct(faixa_etaria, total_faixa) %>%
  mutate(label_faixa = paste0(as.character(faixa_etaria), "\n(n=", total_faixa, ")"))

labels_faixas <- setNames(n_por_faixa$label_faixa, n_por_faixa$faixa_etaria)

if (nrow(virus_faixa_prop) > 0) {
  gD13_heat <- ggplot(virus_faixa_prop,
                      aes(x = faixa_etaria, y = virus, fill = pct)) +
    geom_tile(color = "white", linewidth = 0.6) +
    geom_text(aes(label = paste0(pct, "%")), size = 3.2, color = "grey10") +
    scale_fill_distiller(palette = "YlOrRd", direction = 1,
                         limits = c(0, 100), name = "% dentro\nda faixa") +
    scale_x_discrete(labels = labels_faixas, guide = guide_axis(angle = 40)) +
    labs(
      title    = paste0("Vírus Predominante por Faixa Etária — ", escopo_titulo),
      subtitle = paste0("% calculado sobre PCR positivos em cada faixa | Ano(s): ",
                        paste(anos_carregar, collapse = ", ")),
      x = "Faixa Etária", y = NULL, caption = texto_rodape
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold"),
          panel.grid = element_blank(), axis.text.y = element_text(size = 11))

  salvar_grafico(gD13_heat, "D13_virus_faixa_etaria_heatmap", width = 14, height = 6)
}

if (nrow(virus_faixa_long) > 0) {
  gD13_bar <- ggplot(virus_faixa_long,
                     aes(x = faixa_etaria, y = n, fill = virus)) +
    geom_col(position = "fill") +
    scale_y_continuous(labels = scales::percent_format()) +
    scale_fill_brewer(palette = "Set1") +
    scale_x_discrete(guide = guide_axis(angle = 40)) +
    labs(
      title    = paste0("Composição Viral por Faixa Etária — ", escopo_titulo),
      subtitle = paste0("Proporção de cada vírus no total de PCR positivos da faixa | Ano(s): ",
                        paste(anos_carregar, collapse = ", ")),
      x = "Faixa Etária", y = "Proporção", fill = "Vírus", caption = texto_rodape
    ) +
    theme_minimal(base_size = 12) +
    theme(plot.title = element_text(face = "bold"), legend.position = "bottom")

  salvar_grafico(gD13_bar, "D13_virus_faixa_etaria_barras", width = 14, height = 6)
}

message("Gráficos D13 salvos.")


# ==============================================================================
# GRÁFICO 15 — TIPOS E LINHAGENS DE INFLUENZA
# ==============================================================================

influenza_tipos <- base_filtrada %>%
  filter(POS_PCRFLU == 1) %>%
  mutate(
    tipo_label = case_when(
      TP_FLU_PCR == 1 & PCR_FLUASU == 1 ~ "Influenza A(H1N1)pdm09",
      TP_FLU_PCR == 1 & PCR_FLUASU == 2 ~ "Influenza A(H3N2)",
      TP_FLU_PCR == 1 & PCR_FLUASU == 3 ~ "Influenza A não subtipado",
      TP_FLU_PCR == 1 & PCR_FLUASU == 4 ~ "Influenza A não subtipável",
      TP_FLU_PCR == 1                   ~ "Influenza A não subtipado",
      TP_FLU_PCR == 2 & PCR_FLUBLI == 1 ~ "Influenza B – Vitória",
      TP_FLU_PCR == 2 & PCR_FLUBLI == 2 ~ "Influenza B – Yamagata",
      TP_FLU_PCR == 2 & PCR_FLUBLI == 3 ~ "Influenza B – Não realizado",
      TP_FLU_PCR == 2                   ~ "Influenza B – Não classificado",
      TRUE                              ~ "Ignorado / Não classificado"
    )
  ) %>%
  group_by(tipo_label) %>%
  summarise(total = n(), .groups = "drop") %>%
  arrange(desc(total))

n_inf <- sum(influenza_tipos$total)

if (nrow(influenza_tipos) > 0) {
  g15 <- ggplot(influenza_tipos,
                aes(x = total, y = fct_reorder(tipo_label, total))) +
    geom_col(fill = "#0057A3") +
    geom_text(aes(label = total), hjust = -0.1, size = 4) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(
      title    = paste0("Tipos e Linhagens de Influenza (RT-PCR) — ", escopo_titulo,
                        " (N = ", format(n_inf, big.mark = ".", decimal.mark = ","), ")"),
      x = "Total de Casos", y = "Classificação", caption = texto_rodape
    ) +
    theme_minimal()

  salvar_grafico(g15, "15_tipos_linhagens_influenza")
}


# ==============================================================================
# GRÁFICO 22 — TENDÊNCIA ANUAL DE VÍRUS RESPIRATÓRIOS
# ==============================================================================

if (!requireNamespace("tidytext", quietly = TRUE)) install.packages("tidytext")
library(tidytext)

colunas_virus <- c(
  "PCR_SARS2", "PCR_VSR", "PCR_PARA1", "PCR_PARA2", "PCR_PARA3", "PCR_PARA4",
  "PCR_ADENO", "PCR_METAP", "PCR_BOCA", "PCR_RINO", "PCR_OUTRO"
)

nomes_virus <- c(
  PCR_SARS2 = "SARS-CoV-2",      PCR_VSR   = "VSR",
  PCR_PARA1 = "Parainfluenza 1", PCR_PARA2 = "Parainfluenza 2",
  PCR_PARA3 = "Parainfluenza 3", PCR_PARA4 = "Parainfluenza 4",
  PCR_ADENO = "Adenovírus",      PCR_METAP = "Metapneumovírus",
  PCR_BOCA  = "Bocavírus",       PCR_RINO  = "Rinovírus",
  PCR_OUTRO = "Outro vírus respiratório"
)

colunas_presentes <- intersect(colunas_virus, names(base_15rs_historica))
flu_presente      <- "POS_PCRFLU" %in% names(base_15rs_historica)

ANO_INICIO_VIRAL <- 2023

if (length(colunas_presentes) > 0 && flu_presente) {

  base_virus_hist <- base_15rs_historica %>%
    filter(ANO_BASE >= ANO_INICIO_VIRAL) %>%
    mutate(
      PCR_FLU = if_else(POS_PCRFLU == 1, "1", NA_character_),
      across(all_of(colunas_presentes), as.character)
    ) %>%
    select(ANO_BASE, all_of(colunas_presentes), PCR_FLU)

  casos_virus_ano <- base_virus_hist %>%
    pivot_longer(cols = c(all_of(colunas_presentes), PCR_FLU),
                 names_to = "virus_cod", values_to = "marcado") %>%
    filter(marcado == "1") %>%
    mutate(virus = case_when(
      virus_cod == "PCR_FLU" ~ "Influenza",
      TRUE ~ nomes_virus[virus_cod]
    )) %>%
    filter(!is.na(virus)) %>%
    group_by(ANO_BASE, virus) %>%
    summarise(casos = n(), .groups = "drop")

  virus_ativos <- casos_virus_ano %>%
    group_by(virus) %>% summarise(total = sum(casos), .groups = "drop") %>%
    filter(total > 0) %>% pull(virus)

  casos_virus_ano <- casos_virus_ano %>%
    filter(virus %in% virus_ativos) %>%
    tidyr::complete(ANO_BASE, virus, fill = list(casos = 0))

  top3 <- casos_virus_ano %>%
    group_by(virus) %>% summarise(total = sum(casos), .groups = "drop") %>%
    slice_max(total, n = 3) %>% pull(virus)

  casos_virus_ano <- casos_virus_ano %>%
    mutate(destaque = virus %in% top3,
           espessura  = if_else(destaque, 1.4, 0.7),
           alpha_line = if_else(destaque, 1.0, 0.55))

  ano_atual_viral <- max(casos_virus_ano$ANO_BASE)

  g22 <- ggplot(casos_virus_ano,
                aes(x = ANO_BASE, y = casos, color = virus, group = virus)) +
    geom_vline(xintercept = ano_atual_viral - 0.5,
               linetype = "dotted", color = "grey60", linewidth = 0.7) +
    annotate("text", x = ano_atual_viral - 0.45, y = Inf,
             label = paste0(ano_atual_viral, "\n(parcial)"),
             hjust = 0, vjust = 1.3, size = 2.8, color = "grey50") +
    geom_line(aes(linewidth = I(espessura), alpha = I(alpha_line))) +
    geom_point(aes(size = I(if_else(destaque, 3, 1.8)), alpha = I(alpha_line))) +
    geom_text(data = casos_virus_ano %>% filter(ANO_BASE == max(ANO_BASE), casos > 0),
              aes(label = virus), hjust = -0.1, size = 2.8) +
    scale_x_continuous(breaks = sort(unique(casos_virus_ano$ANO_BASE)),
                       expand = expansion(mult = c(0.02, 0.25))) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.10))) +
    scale_color_manual(values = c(
      "Influenza" = "#E63946", "VSR" = "#2A9D8F", "Rinovírus" = "#F4A261",
      "SARS-CoV-2" = "#457B9D", "Metapneumovírus" = "#6A0572",
      "Adenovírus" = "#E9C46A", "Parainfluenza 1" = "#264653",
      "Parainfluenza 2" = "#A8DADC", "Parainfluenza 3" = "#8D99AE",
      "Parainfluenza 4" = "#B5838D", "Bocavírus" = "#6B705C",
      "Outro vírus respiratório" = "#CDB4DB"
    ), guide = guide_legend(ncol = 2, override.aes = list(linewidth = 1.2, size = 3))) +
    labs(
      title    = paste0("Variação Anual de Vírus Respiratórios — ", escopo_titulo),
      subtitle = paste0("Detecções por RT-PCR | ", ANO_INICIO_VIRAL, "–", ano_atual_viral,
                        " (exclui pico pandêmico 2020–2021) | Vírus em destaque: ",
                        paste(top3, collapse = ", ")),
      x = "Ano", y = "Casos detectados (RT-PCR)", color = "Vírus", caption = texto_rodape
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"),
          plot.subtitle = element_text(size = 8.5, color = "grey40"),
          legend.position = "bottom", legend.title = element_blank(),
          panel.grid.minor = element_blank())

  salvar_grafico(g22, "22_virus_tendencia_anual", width = 13, height = 7)
  message("[OK] Gráfico 22 salvo.")

} else {
  message("  [aviso] Colunas de PCR não encontradas — gráfico 22 não gerado.")
}


# ==============================================================================
# GRÁFICO 16 — FAIXA ETÁRIA: NOTIFICADOS vs CONFIRMADOS
# ==============================================================================

notif_faixa <- base_filtrada %>%
  criar_faixa_etaria() %>%
  group_by(faixa_etaria) %>%
  summarise(n = n(), .groups = "drop") %>%
  mutate(status = "Notificados")

conf_faixa <- base_filtrada %>%
  filter(CLASSI_FIN %in% c(1, 2, 3, 5)) %>%
  criar_faixa_etaria() %>%
  group_by(faixa_etaria) %>%
  summarise(n = n(), .groups = "drop") %>%
  mutate(status = "Confirmados")

faixa_combinada <- bind_rows(notif_faixa, conf_faixa) %>%
  filter(faixa_etaria %in% ORDEM_FAIXAS) %>%
  mutate(faixa_etaria = factor(faixa_etaria, levels = ORDEM_FAIXAS))

n_notif_fe <- sum(notif_faixa$n)
n_conf_fe  <- sum(conf_faixa$n)

g16 <- ggplot(faixa_combinada, aes(x = n, y = faixa_etaria, fill = status)) +
  geom_col(position = "dodge") +
  geom_text(aes(label = n), position = position_dodge(width = 0.9), hjust = -0.1, size = 3) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  scale_fill_manual(values = c("Notificados" = "#0057A3", "Confirmados" = "#1A5C38")) +
  labs(
    title    = paste0("Faixa Etária: Notificados vs Confirmados — ", escopo_titulo,
                      " (Notif.: ", format(n_notif_fe, big.mark = ".", decimal.mark = ","),
                      " | Conf.: ", format(n_conf_fe, big.mark = ".", decimal.mark = ","), ")"),
    x = "Quantidade", y = "Faixa Etária", fill = "Status", caption = texto_rodape
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

salvar_grafico(g16, "16_faixa_etaria_notif_confirmados", height = 8)


# ==============================================================================
# GRÁFICO 17 — PIRÂMIDE ETÁRIA (NOTIFICADOS)
# ==============================================================================

piramide_notif <- base_filtrada %>%
  criar_faixa_etaria() %>%
  padronizar_sexo() %>%
  filter(sexo != "Ignorado", faixa_etaria %in% ORDEM_FAIXAS) %>%
  group_by(faixa_etaria, sexo) %>%
  summarise(n = n(), .groups = "drop") %>%
  mutate(faixa_etaria = factor(faixa_etaria, levels = ORDEM_FAIXAS),
         value = ifelse(sexo == "Masculino", -n, n))

n_piramide_notif <- sum(piramide_notif$n)

g17 <- ggplot(piramide_notif, aes(x = faixa_etaria, y = value, fill = sexo)) +
  geom_bar(stat = "identity", width = 0.8) +
  geom_text(aes(label = n, hjust = ifelse(sexo == "Masculino", 1.15, -0.15)), size = 3.5) +
  coord_flip() +
  scale_y_continuous(labels = function(x) abs(x)) +
  scale_fill_manual(values = c("Masculino" = "#0057A3", "Feminino" = "#E91E8C")) +
  labs(
    title   = paste0("Pirâmide Etária — Notificados — ", escopo_titulo,
                     " (N = ", format(n_piramide_notif, big.mark = ".", decimal.mark = ","), ")"),
    x = "Faixa Etária", y = "Número de Casos", fill = "Sexo", caption = texto_rodape
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

salvar_grafico(g17, "17_piramide_etaria_notificados", height = 8)


# ==============================================================================
# GRÁFICO 18 — PIRÂMIDE ETÁRIA (ÓBITOS)
# ==============================================================================

piramide_obitos <- base_filtrada %>%
  filter(EVOLUCAO == 2) %>%
  criar_faixa_etaria() %>%
  padronizar_sexo() %>%
  filter(sexo != "Ignorado", faixa_etaria %in% ORDEM_FAIXAS) %>%
  group_by(faixa_etaria, sexo) %>%
  summarise(n = n(), .groups = "drop") %>%
  mutate(faixa_etaria = factor(faixa_etaria, levels = ORDEM_FAIXAS),
         value = ifelse(sexo == "Masculino", -n, n))

if (nrow(piramide_obitos) > 0) {
  n_piramide_obitos <- sum(piramide_obitos$n)

  g18 <- ggplot(piramide_obitos, aes(x = faixa_etaria, y = value, fill = sexo)) +
    geom_bar(stat = "identity", width = 0.8) +
    geom_text(aes(label = n, hjust = ifelse(sexo == "Masculino", 1.15, -0.15)), size = 3.5) +
    coord_flip() +
    scale_y_continuous(labels = function(x) abs(x)) +
    scale_fill_manual(values = c("Masculino" = "#0057A3", "Feminino" = "#E91E8C")) +
    labs(
      title   = paste0("Pirâmide Etária — Óbitos — ", escopo_titulo,
                       " (N = ", format(n_piramide_obitos, big.mark = ".", decimal.mark = ","), ")"),
      x = "Faixa Etária", y = "Número de Óbitos", fill = "Sexo", caption = texto_rodape
    ) +
    theme_minimal() +
    theme(legend.position = "bottom")

  salvar_grafico(g18, "18_piramide_etaria_obitos", height = 8)
}


# ==============================================================================
# GRÁFICO 19 — EVOLUÇÃO (DESFECHO)
# ==============================================================================

casos_evolucao <- base_filtrada %>%
  mutate(
    evolucao_label = case_when(
      EVOLUCAO == 1 ~ "Cura",
      EVOLUCAO == 2 ~ "Óbito por SRAG",
      EVOLUCAO == 3 ~ "Óbito por Outras Causas",
      EVOLUCAO == 9 ~ "Ignorado",
      TRUE          ~ "Em investigação"
    )
  ) %>%
  group_by(evolucao_label) %>%
  summarise(total = n(), .groups = "drop")

n_evol <- sum(casos_evolucao$total)

g19 <- ggplot(casos_evolucao,
              aes(x = total, y = fct_reorder(evolucao_label, total))) +
  geom_col(fill = "#A30000") +
  geom_text(aes(label = total), hjust = -0.1, size = 4) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title   = paste0("Casos por Evolução (Desfecho) — ", escopo_titulo,
                     " (N = ", format(n_evol, big.mark = ".", decimal.mark = ","), ")"),
    x = "Número de Casos", y = "Evolução", caption = texto_rodape
  ) +
  theme_minimal()

salvar_grafico(g19, "19_evolucao_desfecho")


# ==============================================================================
# GRÁFICO 20 — RAÇA / COR
# ==============================================================================

casos_raca <- base_filtrada %>%
  mutate(
    raca_label = case_when(
      CS_RACA == 1 ~ "Branca",
      CS_RACA == 2 ~ "Preta",
      CS_RACA == 3 ~ "Amarela",
      CS_RACA == 4 ~ "Parda",
      CS_RACA == 5 ~ "Indígena",
      TRUE         ~ "Ignorado/Outros"
    )
  ) %>%
  group_by(raca_label) %>%
  summarise(total = n(), .groups = "drop")

n_raca <- sum(casos_raca$total)

g20 <- ggplot(casos_raca,
              aes(x = total, y = fct_reorder(raca_label, total))) +
  geom_col(fill = "#0057A3") +
  geom_text(aes(label = total), hjust = -0.1, size = 4) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title   = paste0("Casos por Raça/Cor — ", escopo_titulo,
                     " (N = ", format(n_raca, big.mark = ".", decimal.mark = ","), ")"),
    x = "Número de Casos", y = "Raça/Cor", caption = texto_rodape
  ) +
  theme_minimal()

salvar_grafico(g20, "20_raca_cor")


# ==============================================================================
# GRÁFICO 21 — ESCOLARIDADE (> 18 ANOS)
# ------------------------------------------------------------------------------
# REMOVIDO por decisão manual: não agrega valor ao dashboard.
# [Inferência, não verificado nos dados] O filtro usava NU_IDADE_N > 18 sem
# checar TP_IDADE (unidade: dia/mês/ano) — diferente de COD_IDADE, usado nos
# gráficos de faixa etária (16/17/18), que já vem com a unidade embutida no
# código. Se for esse o motivo do excesso de "Analfabeto", o resto do script
# tem o padrão certo (COD_IDADE) pra usar numa eventual reconstrução futura.
# ==============================================================================


titulo_ano <- paste(anos_carregar, collapse = "/")

g_class <- casos_semana_class %>%
  ggplot(aes(x = SEM_EPI, y = casos, color = CLASSIFICACAO, group = CLASSIFICACAO)) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 1.2, alpha = 0.7) +
  scale_x_continuous(breaks = seq(1, 53, by = 4)) +
  scale_color_brewer(palette = "Set1") +
  labs(
    title    = paste("SRAG por Classificação Etiológica e Semana |", titulo_ano),
    subtitle = paste0(escopo_titulo, " | Fonte: SIVEP-GRIPE"),
    x = "Semana epidemiológica", y = "Casos notificados",
    color = NULL, caption = texto_rodape
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

salvar_grafico(g_class,
               paste0("srag_serie_classificacao_", paste(anos_carregar, collapse = "_")))


# ==============================================================================
# MAPAS GEOGRÁFICOS (tmap)
# ==============================================================================

tmap_mode("plot")

if (file.exists(CAMINHO_SHP_MUNICIPIOS)) {
  message("\nGerando mapa por município...")
  malha_pr <- sf::st_read(CAMINHO_SHP_MUNICIPIOS, quiet = TRUE)

  malha_15rs <- malha_pr %>%
    mutate(CO_MUN_6 = floor(as.integer(CD_MUN) / 10)) %>%
    filter(CO_MUN_6 %in% municipios_15rs$codigo_ibge_6) %>%
    left_join(casos_municipio, by = c("CO_MUN_6" = "CO_MUN_RES"))

  mapa_casos <- tm_shape(malha_15rs) +
    tm_polygons(fill = "casos",
                fill.scale  = tm_scale_continuous(values = "brewer.blues"),
                fill.legend = tm_legend(title = "Casos de SRAG"),
                col = "white", lwd = 0.5) +
    tm_text("NM_MUN", size = 0.45, col = "grey20") +
    tm_title(paste("SRAG — Casos por Município\n15ª RS Maringá/PR |", titulo_ano)) +
    tm_compass(position = c("right", "top"), size = 1.5) +
    tm_scalebar(position = c("left", "bottom"))

  tmap_save(mapa_casos,
            file.path(DIR_GRAFICOS, paste0("mapa_srag_casos_", paste(anos_carregar, collapse = "_"), ".png")),
            width = 2400, height = 2000, device = png)

  mapa_incid <- tm_shape(malha_15rs) +
    tm_polygons(fill = "incidencia_100k",
                fill.scale  = tm_scale_continuous(values = "brewer.yl_or_rd"),
                fill.legend = tm_legend(title = "Casos/100 mil hab."),
                col = "white", lwd = 0.5) +
    tm_text("NM_MUN", size = 0.45, col = "grey20") +
    tm_title(paste("SRAG — Incidência\n15ª RS Maringá/PR |", titulo_ano, "| Pop. IBGE 2025")) +
    tm_compass(position = c("right", "top"), size = 1.5) +
    tm_scalebar(position = c("left", "bottom"))

  tmap_save(mapa_incid,
            file.path(DIR_GRAFICOS, paste0("mapa_srag_incidencia_", paste(anos_carregar, collapse = "_"), ".png")),
            width = 2400, height = 2000, device = png)

  message("Mapas por município salvos.")
} else {
  warning("Shapefile de municípios não encontrado: ", CAMINHO_SHP_MUNICIPIOS)
}

# ==============================================================================
# EXPORTAÇÃO EXCEL
# ==============================================================================

dir_tabelas <- file.path(dirname(DIR_GRAFICOS), "tabelas")
if (!dir.exists(dir_tabelas)) dir.create(dir_tabelas, recursive = TRUE)

writexl::write_xlsx(
  list(
    "municipios_15rs"         = municipios_15rs,
    "casos_municipio"         = casos_municipio,
    "serie_temporal"          = casos_semana,
    "serie_por_classificacao" = casos_semana_class
  ),
  file.path(dir_tabelas, paste0("srag_15rs_", paste(anos_carregar, collapse = "_"), ".xlsx"))
)


# ==============================================================================
# EXPORTAÇÃO — DADOS POR ESTABELECIMENTO (para filtro interativo no site)
# Gera CSVs agregados (estabelecimento x semana [x vírus]) consumidos pelos
# blocos Observable JS em index.qmd, na seção "Notificações por estabelecimento".
# Não inclui microdados individuais.
# ==============================================================================

dir_dados <- file.path(dirname(DIR_GRAFICOS), "dados")
if (!dir.exists(dir_dados)) dir.create(dir_dados, recursive = TRUE)

# [Não verificado] A API pública do dados.gov.br não traz o estabelecimento
# notificador (NO_UNIDADE/NM_UNIDADE/ID_UNIDADE não existem em nenhum ano
# testado, 2019-2026) — provavelmente esses campos só existiam nos DBFs
# locais antigos. NM_UN_INTE (unidade de internação) é usada como
# aproximação: só cobre quem foi hospitalizado, não todas as notificações.
# Base dedicada ao export por estabelecimento: localiza cada hospital pelo
# município de INTERNAÇÃO (CO_MU_INTE), não pelo de residência do paciente
# (CO_MUN_RES) — cerca de 1/3 das internações acontecem num município
# diferente do de residência, então usar CO_MUN_RES colocaria o hospital
# no município errado. O escopo geográfico (só Paraná) vem naturalmente do
# join com ref_regionais_pr: hospitalizações fora do PR não têm
# correspondência em ref_regionais_pr$codigo_ibge_6 e são descartadas
# adiante (!is.na(MUNICIPIO)) — não depende do texto SG_UF_NOT/SG_UF_INTE.
base_estab_pr <- base_completa %>%
  filter(ANO_BASE %in% anos_carregar) %>%
  mutate(CO_MU_INTE = as.integer(CO_MU_INTE))

col_estab <- intersect(c("NO_UNIDADE", "NM_UNIDADE", "ID_UNIDADE", "NM_UN_INTE"),
                       names(base_estab_pr))
col_estab <- if (length(col_estab) > 0) col_estab[1] else NA_character_

if (is.na(col_estab)) {
  warning("Nenhuma coluna de estabelecimento (NO_UNIDADE/NM_UNIDADE/ID_UNIDADE/",
          "NM_UN_INTE) encontrada na base. Exportação para o filtro do site foi pulada.")
} else {
  if (col_estab == "NM_UN_INTE") {
    message("  [aviso] Usando NM_UN_INTE (unidade de internação) como aproximação ",
            "de estabelecimento — cobre só os casos hospitalizados.")
  }
  # A partir daqui, a exportação cobre o Paraná inteiro (base_estab_pr), não
  # só a 15RS — MUNICIPIO/REGIONAL/MACRORREGIAO vêm da tabela de referência
  # ref_regionais_pr (BLOCO 2B), casada por CO_MU_INTE (município de
  # INTERNAÇÃO, isto é, onde o hospital está — não CO_MUN_RES, que é o
  # município de residência do paciente). Linhas cujo município de
  # internação não está na tabela (fora do PR, ou código ausente/errado)
  # são descartadas (!is.na(MUNICIPIO)).
  casos_estabelecimento <- base_estab_pr %>%
    mutate(
      ESTABELECIMENTO = trimws(as.character(.data[[col_estab]])),
      MUNICIPIO       = ref_regionais_pr$municipio[match(CO_MU_INTE, ref_regionais_pr$codigo_ibge_6)],
      REGIONAL        = ref_regionais_pr$regional[match(CO_MU_INTE, ref_regionais_pr$codigo_ibge_6)],
      MACRORREGIAO    = ref_regionais_pr$macrorregiao[match(CO_MU_INTE, ref_regionais_pr$codigo_ibge_6)]
    ) %>%
    filter(
      !is.na(ESTABELECIMENTO), nzchar(ESTABELECIMENTO), ESTABELECIMENTO != "NA",
      !is.na(SEM_EPI), !is.na(MUNICIPIO)
    ) %>%
    group_by(ESTABELECIMENTO, MUNICIPIO, REGIONAL, MACRORREGIAO, SEM_EPI) %>%
    summarise(
      casos       = n(),
      obitos      = sum(EVOLUCAO == 2, na.rm = TRUE),
      uti         = sum(UTI == 1, na.rm = TRUE),
      confirmados = sum(CLASSI_FIN %in% c(1, 2, 3, 5), na.rm = TRUE),
      .groups     = "drop"
    ) %>%
    arrange(REGIONAL, ESTABELECIMENTO, SEM_EPI)

  readr::write_csv(
    casos_estabelecimento,
    file.path(dir_dados, "notificacoes_estabelecimento.csv")
  )

  message("Dados por estabelecimento exportados (Paraná): ",
          format(nrow(casos_estabelecimento), big.mark = ".", decimal.mark = ","), " linhas, ",
          n_distinct(casos_estabelecimento$ESTABELECIMENTO), " estabelecimentos, ",
          n_distinct(casos_estabelecimento$REGIONAL), " regionais.")

  # ----------------------------------------------------------------------------
  # CIRCULAÇÃO VIRAL POR ESTABELECIMENTO
  # Mesmos vírus usados nos gráficos 13/14 (circulação viral total / tendência
  # semanal), agora quebrados por estabelecimento para alimentar o filtro.
  # ----------------------------------------------------------------------------
  colunas_virus_estab <- c(
    POS_PCRFLU = "Influenza",
    PCR_VSR    = "VSR",
    PCR_RINO   = "Rinovírus",
    PCR_ADENO  = "Adenovírus",
    PCR_METAP  = "Metapneumovírus",
    PCR_SARS2  = "Covid-19"
  )
  cols_presentes_virus <- intersect(names(colunas_virus_estab), names(base_estab_pr))

  if (length(cols_presentes_virus) == 0) {
    warning("Nenhuma coluna de PCR viral encontrada na base. ",
            "Exportação de circulação viral por estabelecimento foi pulada.")
  } else {
    circulacao_viral_estab <- base_estab_pr %>%
      mutate(
        ESTABELECIMENTO = trimws(as.character(.data[[col_estab]])),
        MUNICIPIO       = ref_regionais_pr$municipio[match(CO_MU_INTE, ref_regionais_pr$codigo_ibge_6)],
        REGIONAL        = ref_regionais_pr$regional[match(CO_MU_INTE, ref_regionais_pr$codigo_ibge_6)],
        MACRORREGIAO    = ref_regionais_pr$macrorregiao[match(CO_MU_INTE, ref_regionais_pr$codigo_ibge_6)],
        across(all_of(cols_presentes_virus), ~ .x == 1, .names = "VFLAG_{.col}")
      ) %>%
      filter(
        !is.na(ESTABELECIMENTO), nzchar(ESTABELECIMENTO), ESTABELECIMENTO != "NA",
        !is.na(SEM_EPI), !is.na(MUNICIPIO)
      ) %>%
      select(ESTABELECIMENTO, MUNICIPIO, REGIONAL, MACRORREGIAO, SEM_EPI, starts_with("VFLAG_")) %>%
      tidyr::pivot_longer(
        cols      = starts_with("VFLAG_"),
        names_to  = "virus_cod",
        values_to = "positivo"
      ) %>%
      mutate(
        virus_cod = sub("^VFLAG_", "", virus_cod),
        virus     = colunas_virus_estab[virus_cod]
      ) %>%
      filter(positivo == TRUE) %>%
      count(ESTABELECIMENTO, MUNICIPIO, REGIONAL, MACRORREGIAO, SEM_EPI, virus, name = "positivos") %>%
      arrange(REGIONAL, ESTABELECIMENTO, SEM_EPI, virus)

    readr::write_csv(
      circulacao_viral_estab,
      file.path(dir_dados, "circulacao_viral_estabelecimento.csv")
    )

    message("Circulação viral por estabelecimento exportada: ",
            format(nrow(circulacao_viral_estab), big.mark = ".", decimal.mark = ","), " linhas.")
  }
}


# ==============================================================================
# CONTEXTO PARA A PÁGINA DESCRITIVA
# ==============================================================================
# descritiva.qmd lê este .rds em vez de rodar este script de novo no render.
# Contém só os objetos que descritiva_srag_15rs.R usa. Fica em ~/SIVEP_dados
# (fora do ~/Work, que vai para o OneDrive) porque tem dados por registro.

DIR_SENSIVEIS <- path.expand(Sys.getenv("SIVEP_DADOS", "~/SIVEP_dados"))
dir.create(DIR_SENSIVEIS, showWarnings = FALSE, recursive = TRUE, mode = "0700")
CAMINHO_CONTEXTO_DESCRITIVA <- file.path(DIR_SENSIVEIS, "contexto_descritiva.rds")
saveRDS(
  list(
    base_filtrada      = base_filtrada,
    casos_municipio    = casos_municipio,
    anos_carregar      = anos_carregar,
    escopo_titulo      = escopo_titulo,
    texto_rodape       = texto_rodape,
    DIR_GRAFICOS       = DIR_GRAFICOS,
    ORDEM_FAIXAS       = ORDEM_FAIXAS,
    parseia_data       = parseia_data,
    criar_faixa_etaria = criar_faixa_etaria,
    padronizar_sexo    = padronizar_sexo
  ),
  CAMINHO_CONTEXTO_DESCRITIVA
)
message("Contexto da página descritiva salvo: ", CAMINHO_CONTEXTO_DESCRITIVA)


# ==============================================================================
# RESUMO FINAL
# ==============================================================================

n_obitos   <- sum(base_filtrada$EVOLUCAO == 2, na.rm = TRUE)
n_pcr_pos  <- sum(base_filtrada$PCR_RESUL == 1, na.rm = TRUE)
letalidade <- round(n_obitos / nrow(base_filtrada) * 100, 2)

message("\n", strrep("=", 60))
message("RESUMO")
message(strrep("=", 60))
message("Escopo              : ", escopo_titulo)
message("Ano(s) analisados   : ", paste(anos_carregar, collapse = ", "))
message("Pop. IBGE 2025      : ", format(POPULACAO_ESCOPO, big.mark = ".", decimal.mark = ","))
message("Total notificações  : ", format(nrow(base_filtrada), big.mark = ".", decimal.mark = ","))
message("Tx notif. /100k hab.: ", round(nrow(base_filtrada) / POPULACAO_ESCOPO * 100000, 1))
message("Confirmados PCR     : ", format(n_pcr_pos, big.mark = ".", decimal.mark = ","))
message("Óbitos (EVOLUCAO=2) : ", format(n_obitos, big.mark = ".", decimal.mark = ","))
message("Letalidade          : ", letalidade, "%")
message("Saída               : ", DIR_GRAFICOS)
message(strrep("=", 60))
message("Concluído. Rode quarto render e git push para atualizar o site.")
