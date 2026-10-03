# ==============================================================================
# VIGILÂNCIA EPIDEMIOLÓGICA — 15ª REGIONAL DE SAÚDE DE MARINGÁ
# Download da população residente por município, sexo e idade simples (PR)
# Autor   : Valentim Sala Junior
#
# Fonte: Ministério da Saúde — "Estudo de Estimativas Populacionais por
# Município, Idade e Sexo 2000-2025" (DATASUS/Tabnet). O script preenche o
# formulário do Tabnet, uma vez por sexo, e grava o resultado em formato longo.
#
# Uso: Rscript baixar_populacao.R [ano]   (sem ano: o mais recente disponível)
# Saída: sivep_15rs/populacao_pr_idade_sexo_<ano>.csv
#        colunas codigo_ibge_6, municipio, sexo, idade (0-80; 80 = 80 anos e
#        mais), populacao
# Rodar uma vez por ano, quando o Ministério publicar uma nova estimativa.
# ==============================================================================

# Se o Ministério publicar o estudo com outro nome de arquivo .def, troque aqui.
DEF_TABNET <- "ibge/cnv/popsvs2024br.def"
URL_FORM   <- paste0("http://tabnet.datasus.gov.br/cgi/deftohtm.exe?", DEF_TABNET)
URL_TABCGI <- paste0("http://tabnet.datasus.gov.br/cgi/tabcgi.exe?", DEF_TABNET)
UF_PARANA  <- "16"

DIR_PROJETO <- local({
  arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(arg)) dirname(normalizePath(sub("^--file=", "", arg))) else getwd()
})

# --- Ano: o pedido ou o mais recente oferecido pelo formulário ---------------
form <- readLines(URL_FORM, encoding = "latin1", warn = FALSE)
anos_disponiveis <- as.integer(paste0("20", regmatches(
  form, regexpr('(?<=VALUE="pop)[0-9]{2}(?=\\.dbf")', form, perl = TRUE))))
ano <- as.integer(commandArgs(trailingOnly = TRUE)[1])
if (is.na(ano)) ano <- max(anos_disponiveis)
if (!ano %in% anos_disponiveis) {
  stop("Ano ", ano, " não disponível no Tabnet. Disponíveis: ",
       paste(sort(anos_disponiveis), collapse = ", "))
}
message("Baixando população do PR por município, sexo e idade — ", ano)

# --- Consulta ao Tabnet (campos e valores em latin1, como o formulário) -------
consultar_tabnet <- function(sexo_cod) {
  campos <- c(
    "Linha"                 = "Município",
    "Coluna"                = "Idade_simples",
    "Incremento"            = "População_residente",
    "Arquivos"              = sprintf("pop%02d.dbf", ano %% 100),
    "SUnidade_da_Federação" = UF_PARANA,
    "SSexo"                 = sexo_cod,
    "formato"               = "prn",
    "mostre"                = "Mostra"
  )
  # URLencode() e curl_escape() codificam em UTF-8; o Tabnet só entende latin1.
  codificar <- function(x) vapply(x, function(s) {
    bytes <- charToRaw(iconv(s, from = "UTF-8", to = "latin1"))
    paste0(ifelse(grepl("[A-Za-z0-9._~-]", rawToChar(bytes, multiple = TRUE), useBytes = TRUE) &
                    as.integer(bytes) < 128,
                  rawToChar(bytes, multiple = TRUE), sprintf("%%%02X", as.integer(bytes))),
           collapse = "")
  }, character(1), USE.NAMES = FALSE)
  corpo <- paste(paste0(codificar(names(campos)), "=", codificar(campos)), collapse = "&")

  resp <- httr::POST(URL_TABCGI, body = corpo, httr::content_type("application/x-www-form-urlencoded"),
                     httr::timeout(180))
  httr::stop_for_status(resp)
  html <- httr::content(resp, as = "text", encoding = "latin1")
  pre  <- regmatches(html, regexpr("(?s)<PRE>.*?</PRE>", html, perl = TRUE, ignore.case = TRUE))
  if (length(pre) == 0) stop("Resposta do Tabnet sem tabela (sexo ", sexo_cod, ")")
  txt <- gsub("(?i)</?PRE>", "", pre, perl = TRUE)

  tab <- utils::read.csv2(text = txt, check.names = FALSE, colClasses = "character",
                          strip.white = TRUE)
  tab <- tab[grepl("^[0-9]{6} ", tab[[1]]), ]          # só linhas de município
  idades <- setdiff(names(tab)[-1], "Total")
  stopifnot(length(idades) == 81)                      # 0 a 80 anos e mais

  data.frame(
    codigo_ibge_6 = rep(as.integer(substr(tab[[1]], 1, 6)), each = length(idades)),
    municipio     = rep(trimws(substring(tab[[1]], 8)), each = length(idades)),
    idade         = rep(0:80, times = nrow(tab)),
    populacao     = as.integer(unlist(lapply(seq_len(nrow(tab)), function(i) unlist(tab[i, idades])))),
    stringsAsFactors = FALSE
  )
}

pop <- rbind(
  cbind(consultar_tabnet("1"), sexo = "Masculino"),
  cbind(consultar_tabnet("2"), sexo = "Feminino")
)
pop <- pop[, c("codigo_ibge_6", "municipio", "sexo", "idade", "populacao")]
pop$populacao[is.na(pop$populacao)] <- 0L

# --- Verificações -------------------------------------------------------------
n_mun <- length(unique(pop$codigo_ibge_6))
total <- sum(pop$populacao)
message("Municípios: ", n_mun, " | População do PR: ", format(total, big.mark = ".", decimal.mark = ","))
if (n_mun != 399) stop("Esperados 399 municípios do PR, vieram ", n_mun)
if (total < 10e6 || total > 14e6) stop("Total do PR fora do esperado: ", total)

saida <- file.path(DIR_PROJETO, "sivep_15rs", paste0("populacao_pr_idade_sexo_", ano, ".csv"))
utils::write.csv(pop, saida, row.names = FALSE, fileEncoding = "UTF-8")
message("Gravado: ", saida)
