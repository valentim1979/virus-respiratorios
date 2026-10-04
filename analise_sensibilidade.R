# ==============================================================================
# VIGILÂNCIA EPIDEMIOLÓGICA — 15ª REGIONAL DE SAÚDE DE MARINGÁ
# Sensibilidade da vigilância de SRAG: SIVEP-Gripe × SIH/SUS × SIM
# Autor   : Valentim Sala Junior
#
# Análise ANUAL, fora da rotina do painel (SIH e SIM saem com meses de atraso).
# Compara, para residentes da 15ª RS e anos fechados, o número de casos e
# óbitos registrados no SIVEP-Gripe com:
#   - internações no SUS (SIH/RD) com diagnóstico principal compatível com SRAG;
#   - óbitos (SIM) com causa básica compatível com SRAG, no total e só os
#     ocorridos em hospital.
# Comparação AGREGADA (sem relacionamento de registros): a razão SIVEP ÷ fonte
# externa é uma medida aproximada de cobertura, não a sensibilidade exata.
#
# Uso:  Rscript analise_sensibilidade.R [anos]   (padrão: 2024 2025)
# Requer: pacote read.dbc; caches do SIVEP gerados pelo SCRIPT_Unificado.R
#         (dbf_sivep/SRAG_API_<ano>_PR.rds).
# Saída: tabelas/sensibilidade_sivep_sih_sim.csv (ano × município × faixa)
#        tabelas/sensibilidade_resumo.csv          (ano, regional)
# Dados baixados do DATASUS ficam em dbf_sivep/datasus/ (fora do git).
# ==============================================================================

suppressMessages({ library(dplyr); library(readr) })
if (!requireNamespace("read.dbc", quietly = TRUE)) {
  stop("Instale o read.dbc: https://cran.r-project.org/src/contrib/Archive/read.dbc/")
}

ANOS <- as.integer(commandArgs(trailingOnly = TRUE))
if (length(ANOS) == 0) ANOS <- c(2024L, 2025L)

FTP       <- "ftp://ftp.datasus.gov.br/dissemin/publicos"
DIR_CACHE <- file.path("dbf_sivep", "datasus")
dir.create(DIR_CACHE, showWarnings = FALSE, recursive = TRUE)
options(timeout = max(600, getOption("timeout")))

# Municípios da 15ª RS: lidos do BLOCO 2 do SCRIPT_Unificado.R (a mesma lista do
# painel), para não manter uma segunda cópia que poderia divergir.
src <- readLines("SCRIPT_Unificado.R", encoding = "UTF-8")
ini <- grep("^municipios_15rs <- tibble::tribble\\(", src)
fim <- ini + which(grepl("^\\)", src[(ini + 1):length(src)]))[1]
municipios_15rs <- as.integer(regmatches(src[ini:fim], regexpr("(?<=^  )4[0-9]{5}", src[ini:fim], perl = TRUE)))
stopifnot(length(municipios_15rs) == 30)
pop <- read_csv(Sys.glob("sivep_15rs/populacao_pr_idade_sexo_*.csv") |> sort() |> tail(1),
                show_col_types = FALSE)
stopifnot(all(municipios_15rs %in% pop$codigo_ibge_6))

# --- CID compatíveis com SRAG -----------------------------------------------
# J09–J18 influenza e pneumonia; J20–J22 outras infecções agudas das vias
# aéreas inferiores; B34.2, U07.1, U07.2 covid-19.
cid_srag <- function(cid) {
  cid <- toupper(substr(trimws(cid), 1, 4))
  tres <- substr(cid, 1, 3)
  tres %in% c(sprintf("J%02d", 9:18), "J20", "J21", "J22") | cid %in% c("B342", "U071", "U072")
}
faixa <- function(anos) cut(anos, c(-Inf, 4, 59, Inf), labels = c("< 5 anos", "5 a 59 anos", "60 anos e mais"))

# --- Download com novas tentativas (o FTP do DATASUS falha com frequência) ---
baixar <- function(caminho) {
  destino <- file.path(DIR_CACHE, basename(caminho))
  if (file.exists(destino) && file.size(destino) > 0) return(destino)
  # curl do sistema: o download.file() do R falha com o FTP instável do DATASUS
  tmp <- paste0(destino, ".parcial")
  for (t in 1:5) {
    st <- system2("curl", c("-s", "-f", "--retry", "3", "--retry-delay", "5", "--connect-timeout", "30",
                            "--max-time", "900", "-o", shQuote(tmp), shQuote(paste0(FTP, "/", caminho))))
    if (st == 0 && file.exists(tmp) && file.size(tmp) > 0) {
      file.rename(tmp, destino); message("  baixado: ", basename(caminho)); return(destino)
    }
    unlink(tmp); Sys.sleep(10 * t)
  }
  message("  [aviso] não foi possível baixar ", caminho)
  NA_character_
}

# --- SIH/SUS: AIH reduzidas (RD) do Paraná ----------------------------------
# Um ano de internações aparece nas competências do próprio ano e dos meses
# seguintes (faturamento tardio): lê jan/ano até jun/ano+1 e filtra DT_INTER.
ler_sih <- function(ano) {
  comps <- format(seq(as.Date(sprintf("%d-01-01", ano)), as.Date(sprintf("%d-06-01", ano + 1)), by = "month"), "%y%m")
  arqs <- vapply(comps, function(c) baixar(sprintf("SIHSUS/200801_/Dados/RDPR%s.dbc", c)), character(1))
  arqs <- arqs[!is.na(arqs)]
  bind_rows(lapply(arqs, function(a) {
    read.dbc::read.dbc(a, as.is = TRUE) |>
      select(any_of(c("MUNIC_RES", "DT_INTER", "DIAG_PRINC", "COD_IDADE", "IDADE", "IDENT", "N_AIH"))) |>
      mutate(across(everything(), as.character))
  })) |>
    filter(IDENT == "1") |>                       # AIH normal (exclui continuação de longa permanência)
    distinct(N_AIH, .keep_all = TRUE) |>
    mutate(cod = as.integer(substr(MUNIC_RES, 1, 6)),
           data = as.Date(DT_INTER, "%Y%m%d"),
           anos = if_else(COD_IDADE == "4", as.integer(IDADE), 0L)) |>
    filter(cod %in% municipios_15rs, format(data, "%Y") == as.character(ano), cid_srag(DIAG_PRINC))
}

# --- SIM: declarações de óbito do Paraná (final ou preliminar) ---------------
ler_sim <- function(ano) {
  arq <- baixar(sprintf("SIM/CID10/DORES/DOPR%d.dbc", ano))
  fonte <- "final"
  if (is.na(arq)) { arq <- baixar(sprintf("SIM/PRELIM/DORES/DOPR%d.dbc", ano)); fonte <- "preliminar" }
  if (is.na(arq)) return(NULL)
  read.dbc::read.dbc(arq, as.is = TRUE) |>
    mutate(across(everything(), as.character),
           cod = as.integer(substr(CODMUNRES, 1, 6)),
           data = as.Date(DTOBITO, "%d%m%Y"),
           idade_cod = substr(IDADE, 1, 1),
           anos = if_else(idade_cod == "4", as.integer(substr(IDADE, 2, 3)),
                          if_else(idade_cod == "5", 100L + as.integer(substr(IDADE, 2, 3)), 0L)),
           hospital = LOCOCOR == "1",
           fonte_sim = fonte) |>
    filter(cod %in% municipios_15rs, format(data, "%Y") == as.character(ano), cid_srag(CAUSABAS))
}

# --- SIVEP-Gripe (caches PR da API; anos vizinhos para as viradas de ano) ----
ler_sivep <- function() {
  arqs <- Sys.glob("dbf_sivep/SRAG_API_*_PR.rds")
  if (length(arqs) == 0) stop("Rode o SCRIPT_Unificado.R antes, para gerar os caches dbf_sivep/SRAG_API_<ano>_PR.rds")
  bind_rows(lapply(arqs, readRDS)) |>
    mutate(cod = as.integer(CO_MUN_RES),
           interna = as.Date(substr(DT_INTERNA, 1, 10)),
           evolucao = as.Date(substr(DT_EVOLUCA, 1, 10)),
           cod_idade = suppressWarnings(as.integer(COD_IDADE)),
           anos = case_when(cod_idade < 3000 ~ 0L, cod_idade < 4000 ~ cod_idade - 3000L, TRUE ~ NA_integer_)) |>
    filter(cod %in% municipios_15rs)
}

sivep <- ler_sivep()
resultado <- list()
for (ano in ANOS) {
  message("\n== ", ano)
  sih <- ler_sih(ano); sim <- ler_sim(ano)
  if (is.null(sim)) { message("  SIM indisponível para ", ano); next }
  sv_int <- sivep |> filter(format(interna, "%Y") == as.character(ano))
  sv_obi <- sivep |> filter(EVOLUCAO %in% "2", format(evolucao, "%Y") == as.character(ano))

  contar <- function(d, nome) d |> count(cod, faixa = faixa(anos), name = nome)
  tab <- full_join(contar(sv_int, "sivep_internacoes"), contar(sih, "sih_internacoes_sus"), by = c("cod", "faixa")) |>
    full_join(contar(sv_obi, "sivep_obitos"), by = c("cod", "faixa")) |>
    full_join(contar(sim, "sim_obitos"), by = c("cod", "faixa")) |>
    full_join(contar(filter(sim, hospital), "sim_obitos_hospital"), by = c("cod", "faixa")) |>
    mutate(across(where(is.numeric) & !c(cod), ~ coalesce(.x, 0L)), ano = ano,
           fonte_sim = unique(sim$fonte_sim)[1])
  resultado[[as.character(ano)]] <- tab
}

detalhe <- bind_rows(resultado) |>
  left_join(distinct(pop, codigo_ibge_6, municipio), by = c("cod" = "codigo_ibge_6")) |>
  relocate(ano, cod, municipio, faixa)
write_csv(detalhe, "tabelas/sensibilidade_sivep_sih_sim.csv")

resumo <- detalhe |>
  group_by(ano, fonte_sim) |>
  summarise(across(c(sivep_internacoes, sih_internacoes_sus, sivep_obitos, sim_obitos, sim_obitos_hospital), sum),
            .groups = "drop") |>
  mutate(razao_internacoes   = round(sivep_internacoes / sih_internacoes_sus, 2),
         razao_obitos        = round(sivep_obitos / sim_obitos, 2),
         razao_obitos_hosp   = round(sivep_obitos / sim_obitos_hospital, 2))
write_csv(resumo, "tabelas/sensibilidade_resumo.csv")

message("\nResumo (residentes da 15ª RS):")
print(as.data.frame(resumo), row.names = FALSE)
message("\nRazão SIVEP ÷ SIH: o SIH cobre só internações SUS; o SIVEP inclui a rede privada.")
message("Razão SIVEP ÷ SIM: o SIM inclui óbitos fora do hospital e por causas não notificadas como SRAG.")
