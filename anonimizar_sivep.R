# ==============================================================================
# VIGILÂNCIA EPIDEMIOLÓGICA — 15ª REGIONAL DE SAÚDE DE MARINGÁ
# Anonimização do DBF exportado do SIVEP-Gripe (LGPD)
# Autor   : Valentim Sala Junior
#
# Lê o DBF (ou .zip com DBF) baixado manualmente do SIVEP-Gripe em
# ~/SIVEP_entrada, mantém só as colunas de colunas_permitidas.txt (as do dado
# aberto do Ministério, sem DT_NASC/NU_NOTIFIC, mais bairro e unidade), grava a
# base anonimizada em ~/SIVEP_dados/ (fora do ~/Work, que vai para o OneDrive)
# e APAGA o arquivo bruto.
#
# Uso: Rscript anonimizar_sivep.R [pasta_de_entrada]
# Saída: ~/SIVEP_dados/sivep_local_anon_<ano>.rds (data.frame só de texto,
#        como o CSV da API) com atributos origem, exportado_em, processado_em.
#        O ano é o predominante em DT_SIN_PRI (o SIVEP exporta por ano).
# ==============================================================================

suppressMessages(library(foreign))

PASTA_ENTRADA   <- path.expand(commandArgs(trailingOnly = TRUE)[1])
if (is.na(PASTA_ENTRADA)) PASTA_ENTRADA <- path.expand("~/SIVEP_entrada")
PASTA_ERRO      <- file.path(PASTA_ENTRADA, "erro")
DIR_PROJETO     <- local({
  arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(arg)) dirname(normalizePath(sub("^--file=", "", arg))) else getwd()
})
ARQUIVO_COLUNAS <- file.path(DIR_PROJETO, "colunas_permitidas.txt")
DIR_SENSIVEIS   <- path.expand(Sys.getenv("SIVEP_DADOS", "~/SIVEP_dados"))

# Identificadores diretos: se algum aparecer na saída, é bug na lista de
# colunas permitidas — o script aborta sem gravar nada.
PROIBIDAS <- c("NM_PACIENT", "NM_MAE_PAC", "NU_CPF", "NU_CNS", "NU_TELEFON",
               "NU_DDD_TEL", "NM_LOGRADO", "NU_NUMERO", "NM_COMPLEM", "NU_CEP",
               "DT_NASC", "NU_NOTIFIC", "OBSERVA")

permitidas <- readLines(ARQUIVO_COLUNAS, encoding = "UTF-8")
permitidas <- toupper(trimws(sub("#.*$", "", permitidas)))
permitidas <- permitidas[permitidas != ""]
stopifnot(!any(PROIBIDAS %in% permitidas))

# --- Localiza o arquivo bruto mais recente ---
brutos <- list.files(PASTA_ENTRADA, pattern = "\\.(dbf|zip)$",
                     ignore.case = TRUE, full.names = TRUE)
if (length(brutos) == 0) stop("Nenhum .dbf ou .zip em ", PASTA_ENTRADA)
bruto <- brutos[which.max(file.mtime(brutos))]
message("Arquivo bruto: ", basename(bruto))

tmp <- tempfile("sivep_")
dir.create(tmp, mode = "0700")
on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

processar <- function() {
  caminho_dbf <- bruto
  if (grepl("\\.zip$", bruto, ignore.case = TRUE)) {
    utils::unzip(bruto, exdir = tmp)
    dbfs <- list.files(tmp, pattern = "\\.dbf$", ignore.case = TRUE,
                       full.names = TRUE, recursive = TRUE)
    if (length(dbfs) != 1) stop("O .zip deve conter exatamente 1 DBF (tem ", length(dbfs), ")")
    caminho_dbf <- dbfs
  }

  df <- foreign::read.dbf(caminho_dbf, as.is = TRUE)
  names(df) <- toupper(names(df))
  message("Registros: ", nrow(df), " | colunas no DBF: ", ncol(df))

  # Só nomes de colunas vão para o log — nunca valores.
  descartadas <- setdiff(names(df), permitidas)
  message("Colunas descartadas (", length(descartadas), "): ",
          paste(sort(descartadas), collapse = ", "))
  ausentes <- setdiff(permitidas, names(df))
  if (length(ausentes)) {
    message("Colunas permitidas que não vieram no DBF (", length(ausentes), "): ",
            paste(sort(ausentes), collapse = ", "))
  }

  df <- df[, intersect(names(df), permitidas), drop = FALSE]
  stopifnot(!any(PROIBIDAS %in% names(df)))

  # Mesmo formato do CSV da API: tudo texto, datas AAAA-MM-DD, UTF-8.
  df[] <- lapply(df, function(x) {
    if (inherits(x, "Date")) return(format(x, "%Y-%m-%d"))
    x <- as.character(x)
    enc <- iconv(x, from = "latin1", to = "UTF-8")
    ifelse(validUTF8(x), x, enc)
  })

  anos <- substr(df$DT_SIN_PRI, 1, 4)
  dist <- sort(table(anos, useNA = "ifany"), decreasing = TRUE)
  message("Ano de início dos sintomas: ",
          paste(names(dist), dist, sep = " = ", collapse = " | "))
  ano <- names(dist)[1]
  if (is.na(ano) || !grepl("^20[0-9]{2}$", ano)) stop("Não consegui identificar o ano da base")
  if (dist[1] / nrow(df) < 0.95) stop("Base mistura anos (", ano, " é só ",
                                      round(100 * dist[1] / nrow(df)), "%) — exporte um ano por arquivo")
  ARQUIVO_SAIDA <- file.path(DIR_SENSIVEIS, paste0("sivep_local_anon_", ano, ".rds"))

  attr(df, "origem")        <- basename(bruto)
  attr(df, "exportado_em")  <- as.Date(file.mtime(bruto))
  attr(df, "processado_em") <- Sys.time()

  dir.create(DIR_SENSIVEIS, showWarnings = FALSE, recursive = TRUE, mode = "0700")
  tmp_saida <- paste0(ARQUIVO_SAIDA, ".tmp")
  saveRDS(df, tmp_saida)
  stopifnot(identical(dim(readRDS(tmp_saida)), dim(df)))
  file.rename(tmp_saida, ARQUIVO_SAIDA)
  Sys.chmod(ARQUIVO_SAIDA, "0600")
  message("Base anonimizada: ", ARQUIVO_SAIDA, " (", nrow(df), " x ", ncol(df), ")")
}

ok <- tryCatch({ processar(); TRUE }, error = function(e) {
  message("[erro] ", conditionMessage(e))
  FALSE
})

if (ok) {
  # O bruto (com nome, CPF, endereço) não fica no disco.
  unlink(brutos)
  message("Arquivo(s) bruto(s) apagado(s): ", paste(basename(brutos), collapse = ", "))
} else {
  # Tira da pasta vigiada para o systemd não disparar em loop.
  dir.create(PASTA_ERRO, showWarnings = FALSE, mode = "0700")
  file.rename(bruto, file.path(PASTA_ERRO, basename(bruto)))
  message("Bruto movido para ", PASTA_ERRO, " — corrija e mova de volta.")
  quit(status = 1)
}
