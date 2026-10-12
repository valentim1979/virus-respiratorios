# ==============================================================================
# monitor_conclusoes.R — Vigilância Epidemiológica / 15ª RS Maringá
# Depois de cada publicação com dados novos, recalcula os indicadores que
# sustentam as conclusões do artigo e registra se cada conclusão se mantém.
# Gera o histórico (só valores agregados) e um relatório em Markdown e PDF na
# pasta de pesquisa, fora do repositório, para não sujar a árvore do git.
# Uso: Rscript monitor_conclusoes.R
# ==============================================================================

suppressPackageStartupMessages({
  for (pkg in c("dplyr", "ggplot2", "tidyr", "stringr", "forcats", "scales", "writexl")) {
    library(pkg, character.only = TRUE)
  }
})

PROJETO <- normalizePath(".")
SAIDA   <- path.expand("~/Work/Avaliação do Sistema de Vigilância/pesquisa/monitoramento")
dir.create(SAIDA, recursive = TRUE, showWarnings = FALSE)

# --- Indicadores (os mesmos objetos da página Avaliação da Vigilância) ---------
list2env(readRDS(file.path(Sys.getenv("SIVEP_DADOS", "~/SIVEP_dados"), "contexto_descritiva.rds")),
         envir = environment())
# O script descritivo grava tabelas em dirname(DIR_GRAFICOS)/tabelas: desvia
# para um temporário, senão o repositório fica com alterações pendentes.
DIR_GRAFICOS <- file.path(tempdir(), "graficos")
suppressMessages(suppressWarnings(source(file.path(PROJETO, "descritiva_srag_15rs.R"), local = TRUE)))
source(file.path(PROJETO, "nowcasting.R"), local = TRUE)

data_dados <- max(parseia_data(substr(base_filtrada$DT_DIGITA, 1, 10)), na.rm = TRUE)
atrasos    <- preparar_atrasos(base_filtrada)
validacao  <- read.csv(file.path(PROJETO, "dados", "nowcasting_validacao.csv"))
val_T      <- validacao[validacao$semanas_antes == 0, ]

pct_oport <- function(ind) oport_regional$pct[oport_regional$indicador == ind]
opas      <- function(padrao) opas_indicadores$valor[grepl(padrao, opas_indicadores$indicador)][1]
sem_acento <- function(x) tolower(iconv(x, "UTF-8", "ASCII//TRANSLIT"))
situacao_rip <- function(mun) {
  s <- rip_municipio$situacao[sem_acento(rip_municipio$municipio) == sem_acento(mun)]
  if (length(s)) s else NA_character_
}
pct1 <- function(x) paste0(format(round(x, 1), nsmall = 1, decimal.mark = ","), "%")
comorb <- completitude$pct_preenchido[completitude$variavel %in%
                                        c("Cardiopatia", "Diabetes", "Obesidade", "Imunodepressão")]

# --- Indicadores registrados (valor numérico) ----------------------------------
indicadores <- tibble::tribble(
  ~id,                  ~descricao,                                                        ~valor,
  "casos",              "Casos de SRAG residentes no ano",                                 nrow(base_filtrada),
  "var_90",             "Variáveis-chave com completitude ≥ 90%",                          sum(completitude$pct_preenchido >= 90),
  "var_total",          "Variáveis-chave avaliadas",                                       nrow(completitude),
  "comorb_max",         "Maior completitude entre os campos de comorbidade (%)",           max(comorb),
  "incons",             "Inconsistência coleta × sintomas (%)",                            pct_incons,
  "conf_viral",         "Proporção com vírus respiratório confirmado (%)",                 pct_vpp,
  "media_oport",        "Média dos cinco indicadores de oportunidade (%)",                 media_oport,
  "atendimento",        "Internação até 1 dia dos sintomas (%)",                           pct_oport("Atendimento"),
  "notificacao",        "Notificação até 1 dia da internação (%)",                         pct_oport("Notificação"),
  "metas_opas",         "Metas da OPAS atingidas (de 6)",                                  sum(opas_indicadores$atinge %in% TRUE),
  "amostragem",         "Cobertura de amostragem, casos com critério para coleta (%)",     opas("^Cobertura de amostragem \\("),
  "amostragem_uti",     "Cobertura de amostragem em UTI (%)",                              opas("UTI"),
  "mun_abaixo",         "Municípios com incidência abaixo do esperado",                    sum(rip_municipio$situacao == "abaixo"),
  "mun_acima",          "Municípios com incidência acima do esperado",                     sum(rip_municipio$situacao == "acima"),
  "intern_regional",    "Residentes internados na própria regional (%)",                   internacao_fora$pct[1],
  "digit_semana",       "Casos digitados na semana de início dos sintomas (%)",            round(mean(atrasos$atraso <= 0) * 100, 1),
  "nowcast_erro_sem",   "Erro da última semana sem correção (%)",                          val_T$erro_sem_ajuste,
  "nowcast_erro_com",   "Erro da última semana com nowcasting (%)",                        val_T$erro_nowcast,
  "nowcast_cobertura",  "Cobertura do intervalo de 95% na última semana (%)",              val_T$cobertura_ic95,
  "antiviral_48h",      "Influenza tratada com antiviral em até 2 dias dos sintomas (%)",  av_flu$pct_48h
)
v <- setNames(indicadores$valor, indicadores$id)

# --- Conclusões do artigo e o critério para considerá-las mantidas ------------
# margem = distância ao limiar na unidade do indicador, para sinalizar as frágeis
conclusoes <- list(
  list(id = "qualidade_geral", bloco = "Qualidade dos dados",
       texto = "A maioria das variáveis-chave tem completitude de pelo menos 90%",
       criterio = "mais da metade das variáveis com ≥ 90%",
       valor = sprintf("%d de %d", v[["var_90"]], v[["var_total"]]),
       mantida = v[["var_90"]] > v[["var_total"]] / 2, margem = v[["var_90"]] - v[["var_total"]] / 2, escala = 1),
  list(id = "comorbidades", bloco = "Qualidade dos dados",
       texto = "Os campos de comorbidade têm preenchimento baixo",
       criterio = "todos abaixo de 80%", valor = paste("até", pct1(v[["comorb_max"]])),
       mantida = v[["comorb_max"]] < 80, margem = 80 - v[["comorb_max"]], escala = 5),
  list(id = "inconsistencia", bloco = "Qualidade dos dados",
       texto = "A inconsistência entre coleta e sintomas é aceitável",
       criterio = "≤ 20% (Ribeiro & Sanchez)", valor = pct1(v[["incons"]]),
       mantida = v[["incons"]] <= 20, margem = 20 - v[["incons"]], escala = 2),
  list(id = "confirmacao", bloco = "Qualidade dos dados",
       texto = "A proporção com vírus confirmado é satisfatória",
       criterio = "> 20% (Ribeiro & Sanchez)", valor = pct1(v[["conf_viral"]]),
       mantida = v[["conf_viral"]] > 20, margem = v[["conf_viral"]] - 20, escala = 2),
  list(id = "oportuna", bloco = "Oportunidade",
       texto = "A vigilância é oportuna pela média dos cinco indicadores",
       criterio = "média ≥ 70%", valor = pct1(v[["media_oport"]]),
       mantida = v[["media_oport"]] >= 70, margem = v[["media_oport"]] - 70, escala = 2),
  list(id = "atendimento", bloco = "Oportunidade",
       texto = "O atendimento (sintomas → internação) é o gargalo da oportunidade",
       criterio = "< 50% e o menor dos cinco indicadores",
       valor = pct1(v[["atendimento"]]),
       mantida = v[["atendimento"]] < 50 && v[["atendimento"]] == min(oport_regional$pct, na.rm = TRUE),
       margem = 50 - v[["atendimento"]], escala = 5),
  list(id = "metas_opas", bloco = "Oportunidade",
       texto = "A regional atinge cinco das seis metas da OPAS calculáveis com a ficha",
       criterio = "≥ 5 metas", valor = sprintf("%d de 6", v[["metas_opas"]]),
       mantida = v[["metas_opas"]] >= 5, margem = v[["metas_opas"]] - 5, escala = 0.5),
  list(id = "amostragem", bloco = "Oportunidade",
       texto = "A cobertura de amostragem atinge a meta da OPAS",
       criterio = "≥ 90% (casos com critério para coleta)", valor = pct1(v[["amostragem"]]),
       mantida = v[["amostragem"]] >= 90, margem = v[["amostragem"]] - 90, escala = 2),
  list(id = "maringa", bloco = "Representatividade",
       texto = "Maringá tem incidência acima do esperado para a idade",
       criterio = "IC 95% da razão acima de 1", valor = situacao_rip("Maringá"),
       mantida = identical(situacao_rip("Maringá"), "acima"), margem = NA, escala = NA),
  list(id = "nova_esperanca", bloco = "Representatividade",
       texto = "Nova Esperança tem incidência acima do esperado para a idade",
       criterio = "IC 95% da razão acima de 1", valor = situacao_rip("Nova Esperança"),
       mantida = identical(situacao_rip("Nova Esperança"), "acima"), margem = NA, escala = NA),
  list(id = "mun_abaixo", bloco = "Representatividade",
       texto = "Sarandi, Paiçandu, Mandaguaçu e Mandaguari têm incidência abaixo do esperado",
       criterio = "os quatro com IC 95% abaixo de 1",
       valor = paste(sapply(c("Sarandi", "Paiçandu", "Mandaguaçu", "Mandaguari"), situacao_rip), collapse = " / "),
       mantida = all(sapply(c("Sarandi", "Paiçandu", "Mandaguaçu", "Mandaguari"), situacao_rip) %in% "abaixo"),
       margem = NA, escala = NA),
  list(id = "intern_fora", bloco = "Representatividade",
       texto = "A internação fora da regional não explica as diferenças entre municípios",
       criterio = "≥ 95% internados na regional", valor = pct1(v[["intern_regional"]]),
       mantida = v[["intern_regional"]] >= 95, margem = v[["intern_regional"]] - 95, escala = 1),
  list(id = "digitacao", bloco = "Nowcasting",
       texto = "A minoria dos casos é digitada na semana de início dos sintomas",
       criterio = "< 50% na mesma semana", valor = pct1(v[["digit_semana"]]),
       mantida = v[["digit_semana"]] < 50, margem = 50 - v[["digit_semana"]], escala = 5),
  list(id = "nowcast_erro", bloco = "Nowcasting",
       texto = "O nowcasting reduz o erro da última semana a cerca de um terço",
       criterio = "erro com correção ≤ 50% do erro sem correção",
       valor = paste(pct1(v[["nowcast_erro_sem"]]), "→", pct1(v[["nowcast_erro_com"]])),
       mantida = v[["nowcast_erro_com"]] <= v[["nowcast_erro_sem"]] / 2,
       margem = v[["nowcast_erro_sem"]] / 2 - v[["nowcast_erro_com"]], escala = 3),
  list(id = "nowcast_cobertura", bloco = "Nowcasting",
       texto = "O intervalo de 95% do nowcasting tem cobertura próxima da nominal",
       criterio = "≥ 90% na última semana", valor = paste0(v[["nowcast_cobertura"]], "%"),
       mantida = v[["nowcast_cobertura"]] >= 90, margem = v[["nowcast_cobertura"]] - 90, escala = 5),
  list(id = "antiviral", bloco = "Tratamento",
       texto = "Cerca de metade dos casos de influenza tratados recebe antiviral em até 2 dias",
       criterio = "entre 40% e 60%", valor = pct1(v[["antiviral_48h"]]),
       mantida = v[["antiviral_48h"]] >= 40 && v[["antiviral_48h"]] <= 60,
       margem = min(v[["antiviral_48h"]] - 40, 60 - v[["antiviral_48h"]]), escala = 3)
)

registro <- dplyr::bind_rows(lapply(conclusoes, function(x) tibble::tibble(
  data_dados = as.character(data_dados), id = x$id, bloco = x$bloco, texto = x$texto,
  criterio = x$criterio, valor = x$valor, mantida = isTRUE(x$mantida),
  no_limite = !is.na(x$margem) && isTRUE(x$mantida) && x$margem < x$escala
)))

# --- Histórico: uma linha por versão dos dados (reprocessar substitui) --------
gravar <- function(novo, arquivo) {
  caminho <- file.path(SAIDA, arquivo)
  antigo <- if (file.exists(caminho)) read.csv(caminho, colClasses = "character") else NULL
  if (!is.null(antigo)) antigo <- antigo[antigo$data_dados != as.character(data_dados), ]
  tudo <- dplyr::bind_rows(antigo, dplyr::mutate(novo, dplyr::across(everything(), as.character))) %>%
    dplyr::arrange(data_dados)
  write.csv(tudo, caminho, row.names = FALSE)
  tudo
}
hist_ind <- gravar(indicadores %>% mutate(data_dados = as.character(data_dados), .before = 1),
                   "historico_indicadores.csv")
hist_rip <- gravar(rip_municipio %>%
                     transmute(data_dados = as.character(data_dados), municipio,
                               observados, esperados = round(esperados, 1), rip = round(rip, 2),
                               li = round(li, 2), ls = round(ls, 2), situacao),
                   "historico_representatividade.csv")
hist_con <- gravar(registro, "historico_conclusoes.csv")

# --- Relatório ----------------------------------------------------------------
fmt_data <- function(d) format(as.Date(d), "%d/%m/%Y")
versoes  <- sort(unique(hist_con$data_dados))
desde <- function(id_c) {
  h <- hist_con[hist_con$id == id_c, ]
  h <- h[order(h$data_dados), ]
  muda <- which(c(TRUE, h$mantida[-1] != h$mantida[-nrow(h)]))
  fmt_data(h$data_dados[max(muda)])
}
trajeto <- function(id_c) {
  h <- hist_con[hist_con$id == id_c, ]
  h <- tail(h[order(h$data_dados), ], 6)
  paste(h$valor, collapse = " → ")
}
icone <- function(m, l) ifelse(m == "TRUE" | m == TRUE, ifelse(l == "TRUE" | l == TRUE, "⚠ no limite", "✔ mantida"), "✘ caiu")

atual <- hist_con[hist_con$data_dados == as.character(data_dados), ]
n_caiu <- sum(atual$mantida != "TRUE")
n_lim  <- sum(atual$mantida == "TRUE" & atual$no_limite == "TRUE")

linhas <- c(
  "---", "fontsize: 9pt", "---", "",
  "# Monitoramento das conclusões do artigo",
  "",
  sprintf("Dados até **%s** (%s casos residentes). Versões registradas: %d (%s).",
          fmt_data(data_dados), format(v[["casos"]], big.mark = ".", decimal.mark = ","), length(versoes),
          paste(fmt_data(versoes), collapse = ", ")),
  "",
  sprintf("**Resumo:** %d de %d conclusões se mantêm (%d delas perto do limite do critério); %d caíram.",
          nrow(atual) - n_caiu, nrow(atual), n_lim, n_caiu),
  "",
  "Gerado automaticamente por `monitor_conclusoes.R` a cada publicação do painel com dados novos. \"No limite\" = mantida, mas perto do limiar do critério. A coluna *Trajetória* mostra o valor nas últimas versões.",
  ""
)
for (b in unique(atual$bloco)) {
  linhas <- c(linhas, paste("##", b), "",
              "| Conclusão | Critério | Valor atual | Situação | Desde | Trajetória |",
              "|--------------------------|----------------|----------|-----------|------------|--------------------|")
  for (i in which(atual$bloco == b)) {
    r <- atual[i, ]
    linhas <- c(linhas, sprintf("| %s | %s | %s | %s | %s | %s |", r$texto, r$criterio, r$valor,
                                icone(r$mantida, r$no_limite), desde(r$id), trajeto(r$id)))
  }
  linhas <- c(linhas, "")
}

# Mudanças de status entre versões consecutivas
mudancas <- hist_con %>% arrange(id, data_dados) %>% group_by(id) %>%
  mutate(anterior = dplyr::lag(mantida)) %>% ungroup() %>%
  filter(!is.na(anterior), anterior != mantida) %>% arrange(desc(data_dados))
linhas <- c(linhas, "## Mudanças de status", "")
linhas <- c(linhas, if (nrow(mudancas) == 0) "Nenhuma conclusão mudou de situação até agora." else
  sprintf("- **%s** — %s: %s (valor %s)", fmt_data(mudancas$data_dados), mudancas$texto,
          ifelse(mudancas$mantida == "TRUE", "voltou a se sustentar", "deixou de se sustentar"), mudancas$valor), "")

# Municípios que mudaram de classificação na razão padronizada
if (length(versoes) > 1) {
  ant <- hist_rip[hist_rip$data_dados == versoes[length(versoes) - 1], c("municipio", "situacao")]
  mud_rip <- hist_rip[hist_rip$data_dados == versoes[length(versoes)], ] %>%
    inner_join(ant, by = "municipio", suffix = c("", "_ant")) %>% filter(situacao != situacao_ant)
  linhas <- c(linhas, "## Representatividade: municípios que mudaram de classificação", "",
              if (nrow(mud_rip) == 0) "Nenhum município mudou de classificação em relação à versão anterior." else
                sprintf("- %s: %s → %s (razão %s; IC 95%% %s–%s)", mud_rip$municipio, mud_rip$situacao_ant,
                        mud_rip$situacao, mud_rip$rip, mud_rip$li, mud_rip$ls), "")
}

linhas <- c(linhas, "## Arquivos", "",
            "- `historico_conclusoes.csv`: situação de cada conclusão por versão dos dados;",
            "- `historico_indicadores.csv`: valor de cada indicador por versão;",
            "- `historico_representatividade.csv`: razão padronizada por município e versão.",
            "", "Todos contêm apenas valores agregados.")

writeLines(linhas, file.path(SAIDA, "conclusoes_painel.md"))
system2(path.expand("~/.local/bin/md-para-pdf"), shQuote(SAIDA), stdout = FALSE)
cat(sprintf("Monitoramento: %d de %d conclusões mantidas (dados até %s). Relatório em %s\n",
            nrow(atual) - n_caiu, nrow(atual), fmt_data(data_dados), SAIDA))
