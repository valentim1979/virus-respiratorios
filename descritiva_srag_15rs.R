# ==============================================================================
# VIGILÂNCIA EPIDEMIOLÓGICA — 15ª REGIONAL DE SAÚDE DE MARINGÁ
# Script complementar: Estatística Descritiva
# Autor   : Valentim Sala Junior
# Depende : objetos de SCRIPT_Unificado.R (base_filtrada, casos_municipio,
#           texto_rodape, etc.). Em descritiva.qmd eles vêm de
#           ~/SIVEP_dados/contexto_descritiva.rds, salvo pelo script principal.
# Saída   : objetos gD01–gD12 e tabela_resumo_mun, exibidos por
#           descritiva.qmd, e tabelas/descritiva_15rs_<ano>.xlsx
# ==============================================================================


# ==============================================================================
# BLOCO D1 — COMPLETITUDE DAS VARIÁVEIS-CHAVE
# ==============================================================================
# Mostra a proporção de registros com preenchimento válido por campo.
# Interpretação: quanto mais próximo de 100%, melhor a qualidade do dado.

variaveis_chave <- list(
  "Sexo"                 = "CS_SEXO",
  "Idade"                = "COD_IDADE",
  "Raça/Cor"             = "CS_RACA",
  "Bairro"               = "BAIRRO",
  "Semana de início dos sintomas" = "SEM_PRI",
  "Critério Confirmação"  = "CRITERIO",
  "Evolução (Desfecho)"  = "EVOLUCAO",
  "Data Início Sintomas" = "DT_SIN_PRI",
  "Data Internação"      = "DT_INTERNA",
  "Cardiopatia"          = "CARDIOPATI",
  "Diabetes"             = "DIABETES",
  "Obesidade"            = "OBESIDADE",
  "Imunodepressão"       = "IMUNODEPRE",
  "Antiviral"            = "ANTIVIRAL",
  "Vacinação COVID"      = "VACINA_COV"
)

# Valores que representam ausência de informação no SIVEP-Gripe
eh_ausente <- function(x) {
  is.na(x) | x %in% c("", " ", "9", 9, "99", 99, "999", 999,
                       "IGNORADO", "NAO INFORMADO", "SEM INFORMACAO")
}

completitude <- purrr::map_dfr(names(variaveis_chave), function(label) {
  col <- variaveis_chave[[label]]
  if (!col %in% names(base_filtrada)) {
    return(tibble::tibble(variavel = label, pct_preenchido = NA_real_, n_total = nrow(base_filtrada)))
  }
  n_total     <- nrow(base_filtrada)
  n_ausente   <- sum(eh_ausente(base_filtrada[[col]]))
  pct         <- round((1 - n_ausente / n_total) * 100, 1)
  tibble::tibble(variavel = label, pct_preenchido = pct, n_total = n_total)
}) %>%
  filter(!is.na(pct_preenchido)) %>%
  arrange(pct_preenchido)

gD01 <- ggplot(completitude,
               aes(x = pct_preenchido,
                   y = fct_reorder(variavel, pct_preenchido),
                   fill = pct_preenchido)) +
  geom_col() +
  geom_text(aes(label = paste0(pct_preenchido, "%")), hjust = -0.1, size = 3.5) +
  geom_vline(xintercept = 80, linetype = "dashed", color = "#A30000", linewidth = 0.7) +
  annotate("text", x = 81, y = 1, label = "80% (ref.)",
           hjust = 0, size = 3, color = "#A30000") +
  scale_x_continuous(limits = c(0, 115), expand = expansion(mult = c(0, 0))) +
  scale_fill_gradient(low = "#d73027", high = "#1a9850", limits = c(0, 100), guide = "none") +
  labs(
    title    = paste0("Completitude das Variáveis-Chave — ", escopo_titulo),
    subtitle = paste0("N = ", format(nrow(base_filtrada), big.mark = ".", decimal.mark = ","),
                      " | Linha tracejada = referência 80%"),
    x = "% de registros preenchidos", y = NULL,
    caption  = texto_rodape
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))



# ==============================================================================
# BLOCO D1b — CONSISTÊNCIA E VALOR PREDITIVO POSITIVO
# ==============================================================================
# Ribeiro & Sanchez (2020), Epidemiol. Serv. Saúde 29(3):e2020066:
# - inconsistência: % de amostras com coleta antes do início dos sintomas
#   (aceitável se <= 20%);
# - VPP da definição de caso: % de casos de SRAG com vírus respiratório
#   confirmado (satisfatório se > 20%). Aqui: classificação final influenza,
#   outro vírus respiratório ou covid-19.

coleta_valida <- base_filtrada %>%
  mutate(dt_col = parseia_data(DT_COLETA), dt_sin = parseia_data(DT_SIN_PRI)) %>%
  filter(!is.na(dt_col), !is.na(dt_sin))
n_incons   <- sum(coleta_valida$dt_col < coleta_valida$dt_sin)
pct_incons <- round(n_incons / max(nrow(coleta_valida), 1) * 100, 1)

n_virus  <- sum(base_filtrada$CLASSI_FIN %in% c(1, 2, 5))
pct_vpp  <- round(n_virus / max(nrow(base_filtrada), 1) * 100, 1)

tabela_qualidade <- tibble::tibble(
  Indicador  = c("Inconsistência (coleta antes do início dos sintomas)",
                 "Valor preditivo positivo (vírus respiratório confirmado)"),
  Numerador  = c(n_incons, n_virus),
  Denominador = c(nrow(coleta_valida), nrow(base_filtrada)),
  `Valor (%)` = c(pct_incons, pct_vpp),
  Referência = c("≤ 20%", "> 20%"),
  Situação   = c(if (pct_incons <= 20) "Aceitável" else "Não aceitável",
                 if (pct_vpp > 20) "Satisfatório" else "Insatisfatório")
)


# ==============================================================================
# BLOCO D1c — CONSISTÊNCIA: REGRAS POR UNIDADE NOTIFICADORA
# ==============================================================================
# Combinações impossíveis ou improváveis entre campos da ficha, nos casos do
# ano notificados pelas unidades do escopo (base_notif_escopo). Cada regra só
# se aplica aos registros com os campos envolvidos preenchidos.

consistencia_regras <- NULL
consistencia_unidade <- NULL
if (exists("base_notif_escopo") && !is.null(base_notif_escopo) && nrow(base_notif_escopo) > 0) {
  cons <- base_notif_escopo %>%
    mutate(
      sin = parseia_data(substr(DT_SIN_PRI, 1, 10)), int = parseia_data(substr(DT_INTERNA, 1, 10)),
      notif = parseia_data(substr(DT_NOTIFIC, 1, 10)), col = parseia_data(substr(DT_COLETA, 1, 10)),
      evo = parseia_data(substr(DT_EVOLUCA, 1, 10)), uti_in = parseia_data(substr(DT_ENTUTI, 1, 10)),
      uti_out = parseia_data(substr(DT_SAIDUTI, 1, 10))
    )
  regra <- function(id, descricao, aplicavel, violacao) {
    list(id = id, descricao = descricao, ap = aplicavel %in% TRUE, vi = (aplicavel & violacao) %in% TRUE)
  }
  # O SIVEP-Gripe já bloqueia na digitação as combinações IMPOSSÍVEIS (datas fora
  # de ordem, gestante do sexo masculino, classificação laboratorial sem exame
  # positivo etc.): em out/2026, 11 regras desse tipo deram 0 inconsistências.
  # Ficam aqui as que o sistema NÃO bloqueia — registros incompletos ou
  # intervalos implausíveis, que a unidade pode revisar.
  regras <- with(cons, list(
    regra("encerrado_sem_data", "Classificação final informada sem data de encerramento",
          !is.na(CLASSI_FIN) & CLASSI_FIN != "", is.na(parseia_data(substr(DT_ENCERRA, 1, 10)))),
    regra("evolucao_sem_classificacao", "Evolução (cura ou óbito) informada sem classificação final",
          EVOLUCAO %in% c(1, 2, 3), is.na(CLASSI_FIN) | CLASSI_FIN == ""),
    regra("uti_sem_data", "Internação em UTI informada sem data de entrada",
          UTI %in% 1, is.na(uti_in)),
    regra("antiviral_sem_data", "Antiviral informado sem data de início",
          ANTIVIRAL %in% 1, is.na(parseia_data(substr(DT_ANTIVIR, 1, 10)))),
    regra("internacao_tardia", "Internação mais de 30 dias após o início dos sintomas",
          !is.na(int) & !is.na(sin), as.numeric(int - sin) > 30),
    regra("evolucao_tardia", "Evolução mais de 120 dias após a internação",
          !is.na(evo) & !is.na(int), as.numeric(evo - int) > 120)
  ))

  consistencia_regras <- purrr::map_dfr(regras, function(r) tibble::tibble(
    regra = r$descricao, aplicaveis = sum(r$ap), inconsistentes = sum(r$vi),
    pct = if (sum(r$ap) > 0) round(sum(r$vi) / sum(r$ap) * 100, 1) else NA_real_
  )) %>% arrange(desc(pct))

  violou <- Reduce(`|`, lapply(regras, function(r) r$vi))
  regra_top <- vapply(seq_len(nrow(cons)), function(i) {
    ids <- vapply(regras, function(r) if (r$vi[i]) r$descricao else NA_character_, character(1))
    ids <- ids[!is.na(ids)]
    if (length(ids)) ids[1] else NA_character_
  }, character(1))

  consistencia_unidade <- cons %>%
    mutate(violou = violou, regra_top = regra_top,
           unidade = stringr::str_squish(ID_UNIDADE),
           unidade = if_else(is.na(unidade) | unidade == "", "Unidade não informada", unidade)) %>%
    group_by(unidade) %>% mutate(n_un = n()) %>% ungroup() %>%
    mutate(unidade = if_else(n_un < 5, "Outras unidades (< 5 casos cada)", unidade)) %>%
    group_by(unidade) %>%
    summarise(
      municipio = paste(sort(unique(stringr::str_to_title(na.omit(municipio_notif)))), collapse = ", "),
      registros = n(),
      com_inconsistencia = sum(violou),
      pct = round(com_inconsistencia / registros * 100, 1),
      regra_mais_comum = {
        tb <- sort(table(na.omit(regra_top)), decreasing = TRUE)
        if (length(tb)) names(tb)[1] else "—"
      },
      .groups = "drop"
    ) %>%
    arrange(unidade == "Outras unidades (< 5 casos cada)", desc(pct), desc(registros))
}



# ==============================================================================
# BLOCO D2 — OPORTUNIDADE: SINTOMAS → NOTIFICAÇÃO
# ==============================================================================
# Mede o tempo (em dias) entre o início dos sintomas e a notificação.
# Valores altos podem indicar subnotificação precoce ou atraso no sistema.

oportunidade <- base_filtrada %>%
  mutate(
    dt_sin   = parseia_data(DT_SIN_PRI),
    dt_notif = parseia_data(DT_NOTIFIC),
    dias_sin_notif = as.integer(dt_notif - dt_sin)
  ) %>%
  filter(
    !is.na(dias_sin_notif),
    dias_sin_notif >= 0,
    dias_sin_notif <= 60   # remove outliers extremos (provavelmente erro de digitação)
  )

n_op   <- nrow(oportunidade)
med_op <- median(oportunidade$dias_sin_notif)
p25_op <- quantile(oportunidade$dias_sin_notif, 0.25)
p75_op <- quantile(oportunidade$dias_sin_notif, 0.75)

gD02 <- ggplot(oportunidade, aes(x = dias_sin_notif)) +
  geom_histogram(binwidth = 1, fill = "#0057A3", color = "white", alpha = 0.85) +
  geom_vline(xintercept = med_op, color = "#A30000", linewidth = 1, linetype = "solid") +
  geom_vline(xintercept = 7,      color = "#FF8C00", linewidth = 0.8, linetype = "dashed") +
  annotate("text", x = med_op + 0.5, y = Inf, vjust = 1.5, hjust = 0,
           label = paste0("Mediana: ", med_op, " dias"), color = "#A30000", size = 3.5) +
  annotate("text", x = 7.5, y = Inf, vjust = 3, hjust = 0,
           label = "7 dias (ref.)", color = "#FF8C00", size = 3) +
  scale_x_continuous(breaks = seq(0, 60, by = 5)) +
  labs(
    title    = paste0("Oportunidade de Notificação — ", escopo_titulo),
    subtitle = paste0("Dias entre início dos sintomas e notificação | N = ",
                      format(n_op, big.mark = ".", decimal.mark = ","),
                      " | Mediana: ", med_op, " dias",
                      " | P25–P75: ", p25_op, "–", p75_op, " dias"),
    x = "Dias (sintomas → notificação)", y = "Número de casos",
    caption = texto_rodape
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))



# ==============================================================================
# BLOCO D2b — INDICADORES DE OPORTUNIDADE DA VIGILÂNCIA
# ==============================================================================
# Ribeiro & Sanchez (2020): cada indicador é o % de casos com o intervalo
# dentro do prazo; o sistema é oportuno se a média simples dos percentuais
# for >= 70%. Intervalos fora de [-30, 120] dias são tratados como erro de
# digitação e excluídos.

indicadores_oport <- tibble::tribble(
  ~indicador,           ~inicio,      ~fim,         ~prazo, ~filtro,
  "Atendimento",        "DT_SIN_PRI", "DT_INTERNA", 1,      "todos",
  "Notificação",        "DT_INTERNA", "DT_NOTIFIC", 1,      "todos",
  "Tratamento antiviral","DT_INTERNA", "DT_ANTIVIR", 2,      "tratados",
  "Coleta de amostra",  "DT_INTERNA", "DT_COLETA",  7,      "todos",
  "Encerramento",       "DT_NOTIFIC", "DT_ENCERRA", 60,     "todos"
)
descricao_oport <- c(
  "Atendimento"          = "Início dos sintomas → internação (≤ 1 dia)",
  "Notificação"          = "Internação → notificação (≤ 1 dia)",
  "Tratamento antiviral" = "Internação → início do antiviral (≤ 2 dias)",
  "Coleta de amostra"    = "Internação → coleta da amostra (≤ 7 dias)",
  "Encerramento"         = "Notificação → encerramento (≤ 60 dias)"
)

calcular_oportunidade <- function(df) {
  purrr::pmap_dfr(indicadores_oport, function(indicador, inicio, fim, prazo, filtro) {
    d <- if (filtro == "tratados") dplyr::filter(df, ANTIVIRAL == 1) else df
    dias <- as.numeric(parseia_data(d[[fim]]) - parseia_data(d[[inicio]]))
    dias <- dias[!is.na(dias) & dias >= -30 & dias <= 120]
    tibble::tibble(indicador = indicador, n = length(dias),
                   oportunos = sum(dias <= prazo),
                   pct = if (length(dias) > 0) round(mean(dias <= prazo) * 100, 1) else NA_real_)
  })
}

oport_regional <- calcular_oportunidade(base_filtrada)
media_oport    <- round(mean(oport_regional$pct, na.rm = TRUE), 1)

gD02b <- oport_regional %>%
  mutate(rotulo = descricao_oport[indicador],
         rotulo = factor(rotulo, levels = rev(descricao_oport)),
         situacao = if_else(pct >= 70, "Oportuno (≥ 70%)", "Abaixo da meta")) %>%
  ggplot(aes(x = pct, y = rotulo, fill = situacao)) +
  geom_col(width = 0.6) +
  geom_vline(xintercept = 70, linetype = "dashed", color = "#A30000") +
  geom_text(aes(label = paste0(format(pct, decimal.mark = ","), "% (", oportunos, "/", n, ")")),
            hjust = -0.05, size = 3.5) +
  scale_fill_manual(values = c("Oportuno (≥ 70%)" = "#2E7D32", "Abaixo da meta" = "#FF8F00"), name = NULL) +
  scale_x_continuous(limits = c(0, 118), breaks = seq(0, 100, 20)) +
  labs(
    title    = paste0("Oportunidade da Vigilância de SRAG — ", escopo_titulo),
    subtitle = paste0("% de casos dentro do prazo | Média dos indicadores: ",
                      format(media_oport, decimal.mark = ","), "% (meta ≥ 70%) | Linha tracejada = 70%"),
    x = "% oportuno", y = NULL, caption = texto_rodape
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"), legend.position = "top")

oport_municipio <- base_filtrada %>%
  dplyr::left_join(dplyr::select(casos_municipio, CO_MUN_RES, municipio), by = "CO_MUN_RES") %>%
  dplyr::group_split(municipio) %>%
  purrr::map_dfr(function(d) {
    calcular_oportunidade(d) %>%
      dplyr::mutate(municipio = stringr::str_to_title(d$municipio[1]))
  }) %>%
  dplyr::mutate(valor = dplyr::if_else(n > 0, paste0(format(pct, decimal.mark = ","), "% (", n, ")"), "—")) %>%
  dplyr::select(municipio, indicador, valor) %>%
  tidyr::pivot_wider(names_from = indicador, values_from = valor) %>%
  dplyr::arrange(municipio)


# ==============================================================================
# BLOCO D2c — OPORTUNIDADE DE DIGITAÇÃO POR UNIDADE NOTIFICADORA
# ==============================================================================
# Casos do ano notificados por unidades do escopo (base_notif_escopo, inclui
# não residentes — quem digita é a unidade). Intervalo principal: notificação
# (DT_NOTIFIC) → digitação no SIVEP-Gripe (DT_DIGITA). Intervalos negativos
# são excluídos como erro de data. ID_UNIDADE só existe na base exportada do
# SIVEP (não no dado aberto da API).
# A base só contém casos JÁ digitados: notificações recentes ainda não
# digitadas (as mais atrasadas) não aparecem, o que faria os meses recentes
# parecerem melhores. Por isso só entram notificações com pelo menos
# SEGUIMENTO_DIGITACAO dias até a digitação mais recente da base.

digitacao <- NULL
etapas_digitacao <- NULL
digitacao_mes <- NULL
digitacao_unidade <- NULL
gD02c <- NULL
if (exists("base_notif_escopo") && !is.null(base_notif_escopo) && nrow(base_notif_escopo) > 0) {
  digitacao <- base_notif_escopo %>%
    mutate(
      sin   = parseia_data(substr(DT_SIN_PRI, 1, 10)),
      int   = parseia_data(substr(DT_INTERNA, 1, 10)),
      notif = parseia_data(substr(DT_NOTIFIC, 1, 10)),
      dig   = parseia_data(substr(DT_DIGITA, 1, 10)),
      dias  = as.integer(dig - notif)
    )
  SEGUIMENTO_DIGITACAO <- 30
  data_ultima_digitacao <- max(digitacao$dig, na.rm = TRUE)
  data_limite_notif     <- data_ultima_digitacao - SEGUIMENTO_DIGITACAO
  digitacao <- digitacao %>% filter(!is.na(notif), notif <= data_limite_notif)

  resumo_intervalo <- function(x) {
    x <- x[!is.na(x) & x >= 0]
    tibble::tibble(n = length(x), mediana = median(x), p90 = unname(quantile(x, 0.9, type = 1)))
  }
  etapas_digitacao <- dplyr::bind_rows(
    resumo_intervalo(as.integer(digitacao$int - digitacao$sin))   %>% mutate(etapa = "Início dos sintomas → internação"),
    resumo_intervalo(as.integer(digitacao$notif - digitacao$int)) %>% mutate(etapa = "Internação → notificação"),
    resumo_intervalo(digitacao$dias)                               %>% mutate(etapa = "Notificação → digitação no SIVEP-Gripe"),
    resumo_intervalo(as.integer(digitacao$dig - digitacao$sin))   %>% mutate(etapa = "Início dos sintomas → digitação (total)")
  ) %>% select(etapa, n, mediana, p90)

  resumir_digitacao <- function(d) {
    d %>% summarise(
      casos      = n(),
      mediana    = median(dias, na.rm = TRUE),
      p90        = unname(quantile(dias, 0.9, na.rm = TRUE, type = 1)),
      ate_1_dia  = round(mean(dias <= 1, na.rm = TRUE) * 100, 1),
      ate_7_dias = round(mean(dias <= 7, na.rm = TRUE) * 100, 1),
      mais_30    = sum(dias > 30, na.rm = TRUE),
      .groups = "drop"
    )
  }
  dig_valida <- digitacao %>% filter(!is.na(dias), dias >= 0)

  digitacao_mes <- dig_valida %>%
    mutate(mes = lubridate::floor_date(notif, "month")) %>%
    group_by(mes) %>%
    resumir_digitacao()

  gD02c <- digitacao_mes %>%
    filter(casos >= 5, lubridate::ceiling_date(mes + 1, "month") - 1 <= data_limite_notif) %>%   # só meses completos
    ggplot(aes(x = mes, y = ate_1_dia)) +
    geom_col(fill = "#0057A3", width = 20) +
    geom_text(aes(label = paste0(format(ate_1_dia, decimal.mark = ","), "%\n(n=", casos, ")")),
              vjust = -0.3, size = 3, lineheight = 0.9) +
    scale_x_date(date_labels = "%m/%Y", date_breaks = "1 month") +
    scale_y_continuous(limits = c(0, 115), breaks = seq(0, 100, 20)) +
    labs(
      title    = paste0("Casos Digitados em até 1 Dia da Notificação, por Mês — ", escopo_titulo),
      subtitle = paste0("Unidades notificadoras do escopo | Notificações até ", format(data_limite_notif, "%d/%m/%Y"),
                        " (", SEGUIMENTO_DIGITACAO, " dias antes da última digitação) | Meses completos com pelo menos 5 casos"),
      x = "Mês da notificação", y = "% digitados em até 1 dia", caption = texto_rodape
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))

  if ("ID_UNIDADE" %in% names(dig_valida)) {
    digitacao_unidade <- dig_valida %>%
      mutate(unidade = stringr::str_squish(ID_UNIDADE),
             unidade = if_else(is.na(unidade) | unidade == "", "Unidade não informada", unidade)) %>%
      group_by(unidade) %>%
      mutate(casos_unidade = n()) %>%
      ungroup() %>%
      mutate(unidade = if_else(casos_unidade < 5, "Outras unidades (< 5 casos cada)", unidade)) %>%
      group_by(unidade) %>%
      summarise(municipio = paste(sort(unique(stringr::str_to_title(na.omit(municipio_notif)))), collapse = ", "),
                resumir_digitacao(pick(everything())), .groups = "drop") %>%
      arrange(unidade == "Outras unidades (< 5 casos cada)", ate_1_dia, desc(casos))
  }
}

# ==============================================================================
# BLOCO D3 — OPORTUNIDADE: INTERNAÇÃO → DESFECHO
# ==============================================================================

tempo_desfecho <- base_filtrada %>%
  mutate(
    dt_intern  = parseia_data(DT_INTERNA),
    dt_desfech = parseia_data(DT_EVOLUCA),
    dias_intern_desf = as.integer(dt_desfech - dt_intern),
    desfecho = case_when(
      EVOLUCAO == 1 ~ "Cura",
      EVOLUCAO == 2 ~ "Óbito por SRAG",
      EVOLUCAO == 3 ~ "Óbito por Outras Causas",
      TRUE          ~ "Outros/Ignorado"
    )
  ) %>%
  filter(
    !is.na(dias_intern_desf),
    dias_intern_desf >= 0,
    dias_intern_desf <= 120,
    desfecho %in% c("Cura", "Óbito por SRAG")
  )

if (nrow(tempo_desfecho) > 0) {
  gD03 <- ggplot(tempo_desfecho, aes(x = dias_intern_desf, fill = desfecho)) +
    geom_histogram(binwidth = 2, color = "white", alpha = 0.85,
                   position = "identity") +
    scale_fill_manual(values = c("Cura" = "#1a9850", "Óbito por SRAG" = "#A30000")) +
    facet_wrap(~ desfecho, scales = "free_y", ncol = 1) +
    scale_x_continuous(breaks = seq(0, 120, by = 10)) +
    labs(
      title    = paste0("Tempo de Internação até o Desfecho — ", escopo_titulo),
      subtitle = "Dias entre internação e desfecho (cura ou óbito por SRAG)",
      x = "Dias (internação → desfecho)", y = "Número de casos",
      fill = NULL, caption = texto_rodape
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"), legend.position = "none")
  
}


# ==============================================================================
# BLOCO D4 — COMORBIDADES: FREQUÊNCIA GERAL
# ==============================================================================
# Cada campo binário: 1 = sim, 2 = não, 9 = ignorado.
# Conta apenas os registros com valor == 1.

campos_comorbidade <- c(
  "Cardiopatia"          = "CARDIOPATI",
  "Diabetes"             = "DIABETES",
  "Obesidade"            = "OBESIDADE",
  "Doença Renal"         = "RENAL",
  "Asma"                 = "ASMA",
  "Imunodepressão"       = "IMUNODEPRE",
  "Doença Neurológica"   = "NEUROLOGIC",
  "Doença Hepática"      = "HEPATICA",
  "Doença Hematológica"  = "HEMATOLO",
  "Pneumopatia"          = "PNEUMOPATI",
  "Síndrome de Down"     = "SIND_DOWN",
  "Puérpera"             = "PUERPERA"
)

freq_comorbidade <- purrr::map_dfr(names(campos_comorbidade), function(label) {
  col <- campos_comorbidade[[label]]
  if (!col %in% names(base_filtrada)) return(NULL)
  n   <- sum(as.character(base_filtrada[[col]]) == "1", na.rm = TRUE)
  pct <- round(n / nrow(base_filtrada) * 100, 1)
  tibble::tibble(comorbidade = label, n = n, pct = pct)
}) %>%
  filter(n > 0) %>%
  arrange(desc(n))

if (nrow(freq_comorbidade) > 0) {
  gD04 <- ggplot(freq_comorbidade,
                 aes(x = n, y = fct_reorder(comorbidade, n))) +
    geom_col(fill = "#6A0572") +
    geom_text(aes(label = paste0(n, " (", pct, "%)")), hjust = -0.08, size = 3.5) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.22))) +
    labs(
      title    = paste0("Comorbidades — Frequência Total — ", escopo_titulo),
      subtitle = paste0("N = ", format(nrow(base_filtrada), big.mark = ".", decimal.mark = ","),
                        " notificações | % sobre o total de registros"),
      x = "Número de casos", y = NULL,
      caption = texto_rodape
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))
  
}


# ==============================================================================
# BLOCO D5 — COMORBIDADES: NOTIFICADOS vs ÓBITOS
# ==============================================================================

freq_comorbidade_obitos <- purrr::map_dfr(names(campos_comorbidade), function(label) {
  col <- campos_comorbidade[[label]]
  if (!col %in% names(base_filtrada)) return(NULL)
  
  n_total  <- sum(as.character(base_filtrada[[col]]) == "1", na.rm = TRUE)
  n_obitos <- sum(as.character(base_filtrada[[col]]) == "1" &
                    base_filtrada$EVOLUCAO == 2, na.rm = TRUE)
  
  bind_rows(
    tibble::tibble(comorbidade = label, grupo = "Notificados", n = n_total),
    tibble::tibble(comorbidade = label, grupo = "Óbitos",      n = n_obitos)
  )
}) %>%
  filter(n > 0)

if (nrow(freq_comorbidade_obitos) > 0) {
  gD05 <- ggplot(freq_comorbidade_obitos,
                 aes(x = n, y = fct_reorder(comorbidade, n), fill = grupo)) +
    geom_col(position = "dodge") +
    geom_text(aes(label = n),
              position = position_dodge(width = 0.9), hjust = -0.1, size = 3) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.2))) +
    scale_fill_manual(values = c("Notificados" = "#6A0572", "Óbitos" = "#A30000")) +
    labs(
      title    = paste0("Comorbidades — Notificados vs Óbitos — ", escopo_titulo),
      subtitle = "Registros com campo = 1 (Sim) em cada grupo",
      x = "Número de casos", y = NULL, fill = NULL,
      caption = texto_rodape
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"), legend.position = "bottom")
  
}


# ==============================================================================
# BLOCO D6 — LETALIDADE POR FAIXA ETÁRIA
# ==============================================================================

letalidade_faixa <- base_filtrada %>%
  criar_faixa_etaria() %>%
  filter(faixa_etaria %in% ORDEM_FAIXAS) %>%
  group_by(faixa_etaria) %>%
  summarise(
    casos      = n(),
    encerrados = sum(EVOLUCAO %in% c(1, 2, 3), na.rm = TRUE),
    obitos     = sum(EVOLUCAO == 2, na.rm = TRUE),
    .groups    = "drop"
  ) %>%
  mutate(
    faixa_etaria    = factor(faixa_etaria, levels = ORDEM_FAIXAS),
    letalidade_pct  = round(obitos / encerrados * 100, 1)
  ) %>%
  filter(encerrados >= 5)   # remove faixas com n muito pequeno

gD06 <- ggplot(letalidade_faixa,
               aes(x = faixa_etaria, y = letalidade_pct)) +
  geom_col(fill = "#A30000") +
  geom_text(aes(label = paste0(letalidade_pct, "%\n(", obitos, "/", encerrados, ")")),
            vjust = -0.3, size = 3) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.25))) +
  labs(
    title    = paste0("Letalidade por Faixa Etária — ", escopo_titulo),
    subtitle = "% óbitos por SRAG / casos encerrados (com desfecho) na faixa | Mínimo 5 encerrados",
    x = "Faixa Etária", y = "Letalidade (%)",
    caption = texto_rodape
  ) +
  theme_minimal() +
  theme(
    axis.text.x  = element_text(angle = 40, hjust = 1),
    plot.title   = element_text(face = "bold")
  )



# ==============================================================================
# BLOCO D7 — LETALIDADE POR SEXO
# ==============================================================================

letalidade_sexo <- base_filtrada %>%
  padronizar_sexo() %>%
  filter(sexo != "Ignorado") %>%
  group_by(sexo) %>%
  summarise(
    casos      = n(),
    encerrados = sum(EVOLUCAO %in% c(1, 2, 3), na.rm = TRUE),
    obitos     = sum(EVOLUCAO == 2, na.rm = TRUE),
    .groups    = "drop"
  ) %>%
  mutate(letalidade_pct = round(obitos / encerrados * 100, 1))

gD07 <- ggplot(letalidade_sexo,
               aes(x = sexo, y = letalidade_pct, fill = sexo)) +
  geom_col(width = 0.5) +
  geom_text(aes(label = paste0(letalidade_pct, "%\n(", obitos, "/", encerrados, ")")),
            vjust = -0.3, size = 4) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.2))) +
  scale_fill_manual(values = c("Masculino" = "#0057A3", "Feminino" = "#E91E8C"),
                    guide = "none") +
  labs(
    title    = paste0("Letalidade por Sexo — ", escopo_titulo),
    subtitle = "% óbitos por SRAG / casos encerrados (com desfecho) por sexo",
    x = NULL, y = "Letalidade (%)",
    caption = texto_rodape
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))



# ==============================================================================
# BLOCO D8 — USO DE UTI POR FAIXA ETÁRIA
# ==============================================================================

uti_faixa <- base_filtrada %>%
  criar_faixa_etaria() %>%
  filter(faixa_etaria %in% ORDEM_FAIXAS) %>%
  group_by(faixa_etaria) %>%
  summarise(
    casos     = n(),
    uti       = sum(UTI_SIM, na.rm = TRUE),
    .groups   = "drop"
  ) %>%
  mutate(
    faixa_etaria = factor(faixa_etaria, levels = ORDEM_FAIXAS),
    pct_uti      = round(uti / casos * 100, 1)
  ) %>%
  filter(casos >= 5)

gD08 <- ggplot(uti_faixa,
               aes(x = faixa_etaria, y = pct_uti)) +
  geom_col(fill = "#E65100") +
  geom_text(aes(label = paste0(pct_uti, "%\n(", uti, ")")),
            vjust = -0.3, size = 3) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.25))) +
  labs(
    title    = paste0("Uso de UTI por Faixa Etária — ", escopo_titulo),
    subtitle = "% internados em UTI / total notificados na faixa | Mínimo 5 casos",
    x = "Faixa Etária", y = "% em UTI",
    caption = texto_rodape
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 40, hjust = 1),
    plot.title  = element_text(face = "bold")
  )



# ==============================================================================
# BLOCO D8b — TAXAS POR FAIXA ETÁRIA E SEXO (POR 100 MIL HABITANTES)
# ==============================================================================
# Numerador: casos, óbitos por SRAG e internações em UTI de base_filtrada.
# Denominador: população residente do escopo por idade e sexo (estimativas do
# Ministério da Saúde/DATASUS, ver baixar_populacao.R), em pop_idade_escopo.
# A população só existe por idade em anos, então < 1 ano não é subdividido.
# COD_IDADE: 1xxx = dias, 2xxx = meses, 3xxx = anos.

FAIXAS_TAXA <- c("< 1 ano", "1-4", "5-9", "10-14", "15-19", "20-29", "30-39",
                 "40-49", "50-59", "60-69", "70-79", "80 e mais")
faixa_taxa <- function(anos) {
  cut(anos, breaks = c(-Inf, 0, 4, 9, 14, 19, 29, 39, 49, 59, 69, 79, Inf),
      labels = FAIXAS_TAXA)
}

taxas_faixa <- NULL
gD08b <- NULL
gD08c <- NULL
if (exists("pop_idade_escopo") && !is.null(pop_idade_escopo)) {
  casos_idade <- base_filtrada %>%
    padronizar_sexo() %>%
    mutate(
      cod  = suppressWarnings(as.integer(COD_IDADE)),
      anos = case_when(cod < 3000 ~ 0L, cod < 4000 ~ cod - 3000L, TRUE ~ NA_integer_),
      faixa = faixa_taxa(anos)
    ) %>%
    filter(!is.na(faixa))

  pop_faixa_sexo <- pop_idade_escopo %>%
    mutate(faixa = faixa_taxa(idade)) %>%
    group_by(faixa, sexo) %>%
    summarise(populacao = sum(populacao), .groups = "drop")

  taxas_faixa <- casos_idade %>%
    group_by(faixa) %>%
    summarise(casos = n(),
              obitos = sum(EVOLUCAO == 2, na.rm = TRUE),
              uti = sum(UTI == 1, na.rm = TRUE), .groups = "drop") %>%
    tidyr::complete(faixa, fill = list(casos = 0L, obitos = 0L, uti = 0L)) %>%
    left_join(pop_faixa_sexo %>% group_by(faixa) %>% summarise(populacao = sum(populacao)),
              by = "faixa") %>%
    mutate(
      incidencia_100k  = round(casos  / populacao * 1e5, 1),
      mortalidade_100k = round(obitos / populacao * 1e5, 1),
      uti_100k         = round(uti    / populacao * 1e5, 1)
    )

  gD08b <- taxas_faixa %>%
    select(faixa, `Incidência` = incidencia_100k, `Internação em UTI` = uti_100k,
           `Mortalidade` = mortalidade_100k) %>%
    tidyr::pivot_longer(-faixa, names_to = "indicador", values_to = "taxa") %>%
    mutate(indicador = factor(indicador, levels = c("Incidência", "Internação em UTI", "Mortalidade"))) %>%
    ggplot(aes(x = faixa, y = taxa, fill = indicador)) +
    geom_col(show.legend = FALSE) +
    geom_text(aes(label = format(taxa, decimal.mark = ",")), vjust = -0.3, size = 2.8) +
    facet_wrap(~ indicador, ncol = 1, scales = "free_y") +
    scale_fill_manual(values = c("Incidência" = "#0057A3", "Internação em UTI" = "#FF8F00",
                                 "Mortalidade" = "#A30000")) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
    labs(
      title    = paste0("Taxas de SRAG por Faixa Etária — ", escopo_titulo),
      subtitle = paste0("Por 100.000 habitantes | ", ROTULO_POPULACAO,
                        " (Ministério da Saúde/DATASUS) | Ano(s): ", paste(anos_carregar, collapse = ", ")),
      x = "Faixa etária (anos)", y = "Por 100.000 hab.", caption = texto_rodape
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"), strip.text = element_text(face = "bold"))

  piramide_taxa <- casos_idade %>%
    filter(sexo %in% c("Masculino", "Feminino")) %>%
    count(faixa, sexo, name = "casos") %>%
    tidyr::complete(faixa, sexo, fill = list(casos = 0L)) %>%
    left_join(pop_faixa_sexo, by = c("faixa", "sexo")) %>%
    mutate(taxa = round(casos / populacao * 1e5, 1),
           taxa_plot = if_else(sexo == "Masculino", -taxa, taxa))
  lim <- max(piramide_taxa$taxa, na.rm = TRUE) * 1.2

  gD08c <- ggplot(piramide_taxa, aes(x = taxa_plot, y = faixa, fill = sexo)) +
    geom_col(width = 0.8) +
    geom_text(aes(label = format(taxa, decimal.mark = ","),
                  hjust = if_else(sexo == "Masculino", 1.1, -0.1)), size = 3) +
    geom_vline(xintercept = 0, color = "grey40") +
    scale_x_continuous(labels = function(x) format(abs(x), decimal.mark = ","), limits = c(-lim, lim)) +
    scale_fill_manual(values = c("Masculino" = "#0057A3", "Feminino" = "#E91E8C"), name = NULL) +
    labs(
      title    = paste0("Incidência de SRAG por Faixa Etária e Sexo — ", escopo_titulo),
      subtitle = paste0("Casos por 100.000 habitantes de cada faixa e sexo | ", ROTULO_POPULACAO),
      x = "Casos por 100.000 hab.", y = "Faixa etária (anos)", caption = texto_rodape
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"), legend.position = "top")
}



# ==============================================================================
# BLOCO D8c — REPRESENTATIVIDADE
# ==============================================================================
# 1) Razão de incidência padronizada por idade (padronização indireta) por
#    município de residência: observados ÷ esperados, sendo os esperados as
#    taxas da regional por faixa etária aplicadas à população do município.
#    IC 95% exato de Poisson. Municípios muito acima ou abaixo de 1 indicam
#    diferença real de risco ou de notificação/acesso.
# 2) Residentes internados fora da regional (CO_MU_INTE fora do escopo).

rip_municipio <- NULL
gD08d <- NULL
internacao_fora <- NULL
if (exists("pop_mun_idade") && !is.null(pop_mun_idade) && !is.null(taxas_faixa)) {
  taxa_ref <- taxas_faixa %>% transmute(faixa, taxa_ref = casos / populacao)
  esperados <- pop_mun_idade %>%
    mutate(faixa = faixa_taxa(idade)) %>%
    group_by(codigo_ibge_6, faixa) %>% summarise(populacao = sum(populacao), .groups = "drop") %>%
    left_join(taxa_ref, by = "faixa") %>%
    group_by(codigo_ibge_6) %>%
    # esperados antes de populacao: no summarise, populacao = sum(...) mudaria o valor usado em seguida
    summarise(esperados = sum(populacao * taxa_ref), populacao = sum(populacao), .groups = "drop")
  observados <- casos_idade %>% count(codigo_ibge_6 = as.integer(CO_MUN_RES), name = "observados")
  rip_municipio <- esperados %>%
    left_join(observados, by = "codigo_ibge_6") %>%
    mutate(observados = coalesce(observados, 0L)) %>%
    left_join(municipios_15rs %>% select(codigo_ibge_6, municipio), by = "codigo_ibge_6") %>%
    mutate(
      municipio = stringr::str_to_title(municipio),
      rip = observados / esperados,
      li  = qchisq(0.025, 2 * observados) / 2 / esperados,
      ls  = qchisq(0.975, 2 * (observados + 1)) / 2 / esperados,
      li  = if_else(observados == 0, 0, li),
      situacao = case_when(li > 1 ~ "acima", ls < 1 ~ "abaixo", TRUE ~ "compativel")
    ) %>%
    arrange(desc(rip))

  n_mun <- nrow(rip_municipio)
  # Escala log: razão 0 (município sem casos) não tem posição; vai ao piso 0,1
  # com círculo vazado e nota.
  piso <- 0.1
  dados_rip <- rip_municipio %>%
    mutate(rip_plot = pmax(rip, piso), li_plot = pmax(li, piso), sem_casos = observados == 0)
  gD08d <- ggplot(dados_rip, aes(x = rip_plot, y = forcats::fct_reorder(municipio, rip))) +
    geom_vline(xintercept = 1, linetype = "dashed", color = "grey40") +
    geom_errorbarh(aes(xmin = li_plot, xmax = ls, color = situacao), height = 0.3) +
    geom_point(aes(color = situacao, shape = sem_casos), size = 2.4, fill = "white", stroke = 1.1) +
    scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 21), guide = "none") +
    scale_color_manual(values = c("acima" = "#C62828", "abaixo" = "#0057A3", "compativel" = "grey55"),
                       labels = c("acima" = "Acima do esperado", "abaixo" = "Abaixo do esperado",
                                  "compativel" = "Compatível com a regional"), name = NULL) +
    scale_x_continuous(trans = "log2", breaks = c(0.125, 0.25, 0.5, 1, 2, 4), limits = c(piso, 5),
                       labels = function(x) sub(".", ",", as.character(x), fixed = TRUE)) +
    labs(
      title    = paste0("Razão de Incidência Padronizada por Idade, por Município — ", escopo_titulo),
      subtitle = paste0("Casos observados ÷ esperados pelas taxas da regional por faixa etária | IC 95% | ",
                        ROTULO_POPULACAO, " | escala logarítmica\nCírculo vazado = município sem casos no ano (razão 0)"),
      x = "Razão observado/esperado (1 = igual à regional)", y = NULL, caption = texto_rodape
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"), legend.position = "top")
}

if ("CO_MU_INTE" %in% names(base_filtrada)) {
  cod_escopo <- if (exists("municipios_15rs")) municipios_15rs$codigo_ibge_6 else unique(as.integer(base_filtrada$CO_MUN_RES))
  mu_inte <- suppressWarnings(as.integer(base_filtrada$CO_MU_INTE))
  internacao_fora <- tibble::tibble(
    situacao = c("Internados em município da regional", "Internados fora da regional, no Paraná",
                 "Internados fora do Paraná", "Município de internação não informado"),
    casos = c(sum(mu_inte %in% cod_escopo), sum(!is.na(mu_inte) & !(mu_inte %in% cod_escopo) & mu_inte %/% 10000 == 41),
              sum(!is.na(mu_inte) & mu_inte %/% 10000 != 41), sum(is.na(mu_inte)))
  ) %>% mutate(pct = round(casos / sum(casos) * 100, 1))
}



# ==============================================================================
# BLOCO D9 — CRITÉRIO DE CONFIRMAÇÃO
# ==============================================================================
# CRITERIO: 1 = Laboratorial, 2 = Clínico-Epidemiológico,
#           3 = Clínico-Imagem, 4 = Clínico

criterio_conf <- base_filtrada %>%
  filter(CLASSI_FIN %in% c(1, 2, 3, 5)) %>%   # apenas confirmados
  mutate(
    criterio_label = case_when(
      CRITERIO == 1 ~ "Laboratorial",
      CRITERIO == 2 ~ "Clínico-Epidemiológico",
      CRITERIO == 3 ~ "Clínico-Imagem",
      CRITERIO == 4 ~ "Clínico",
      TRUE          ~ "Não informado"
    )
  ) %>%
  group_by(criterio_label) %>%
  summarise(total = n(), .groups = "drop") %>%
  mutate(pct = round(total / sum(total) * 100, 1)) %>%
  arrange(desc(total))

n_crit <- sum(criterio_conf$total)

gD09 <- ggplot(criterio_conf,
               aes(x = total, y = fct_reorder(criterio_label, total))) +
  geom_col(fill = "#2A9D8F") +
  geom_text(aes(label = paste0(total, " (", pct, "%)")),
            hjust = -0.08, size = 3.5) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.22))) +
  labs(
    title    = paste0("Critério de Confirmação — SRAG Confirmado — ", escopo_titulo,
                      " (N = ", format(n_crit, big.mark = ".", decimal.mark = ","), ")"),
    subtitle = "Somente casos com classificação final confirmada (CLASSI_FIN = 1, 2, 3 ou 5)",
    x = "Casos confirmados", y = NULL,
    caption = texto_rodape
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))



# ==============================================================================
# BLOCO D10 — USO DE ANTIVIRAL
# ==============================================================================
# ANTIVIRAL: 1 = Sim, 2 = Não, 9 = Ignorado. TP_ANTIVIR: 1 = oseltamivir,
# 2 = zanamivir, 3 = outro. DT_ANTIVIR: data de início do antiviral.
# O Guia de Manejo e Tratamento de Influenza (MS, 2023) indica oseltamivir
# imediato para todo caso de SRAG, com maior benefício até 48 h do início dos
# sintomas. A página mostra dois grupos: influenza confirmada (CLASSI_FIN = 1)
# e todos os casos de SRAG.

analisar_antiviral <- function(df, grupo) {
  dist <- df %>%
    mutate(
      antiviral_label = case_when(
        ANTIVIRAL == 1 ~ "Sim",
        ANTIVIRAL == 2 ~ "Não",
        TRUE           ~ "Ignorado/Não registrado"
      )
    ) %>%
    count(antiviral_label, name = "total") %>%
    mutate(pct = round(total / sum(total) * 100, 1))

  g_dist <- ggplot(dist, aes(x = total, y = fct_reorder(antiviral_label, total))) +
    geom_col(fill = "#457B9D") +
    geom_text(aes(label = paste0(total, " (", format(pct, decimal.mark = ","), "%)")),
              hjust = -0.08, size = 3.5) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.22))) +
    labs(
      title    = paste0("Uso de Antiviral — ", grupo, " — ", escopo_titulo,
                        " (N = ", format(nrow(df), big.mark = ".", decimal.mark = ","), ")"),
      x = "Número de casos", y = NULL, caption = texto_rodape
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))

  # Oportunidade: dias entre início dos sintomas e início do antiviral
  tratados <- df %>%
    filter(ANTIVIRAL == 1) %>%
    mutate(dias = as.numeric(parseia_data(DT_ANTIVIR) - parseia_data(DT_SIN_PRI))) %>%
    filter(!is.na(dias), dias >= 0, dias <= 60)

  ate_48h <- sum(tratados$dias <= 2)
  pct_48h <- if (nrow(tratados) > 0) round(ate_48h / nrow(tratados) * 100, 1) else NA_real_

  g_oport <- NULL
  if (nrow(tratados) > 0) {
    g_oport <- tratados %>%
      mutate(dias_cat = factor(pmin(dias, 14), levels = 0:14,
                               labels = c(0:13, "14+")),
             janela   = factor(if_else(dias <= 2, "Até 2 dias (≈ 48 h)", "Após 2 dias"),
                               levels = c("Até 2 dias (≈ 48 h)", "Após 2 dias"))) %>%
      count(dias_cat, janela, .drop = FALSE) %>%
      filter(!(n == 0 & ((as.integer(dias_cat) <= 3 & janela == "Após 2 dias") |
                         (as.integer(dias_cat) > 3 & janela != "Após 2 dias")))) %>%
      ggplot(aes(x = dias_cat, y = n, fill = janela)) +
      geom_col() +
      geom_text(aes(label = n), vjust = -0.4, size = 3) +
      scale_fill_manual(values = c("Até 2 dias (≈ 48 h)" = "#2E7D32", "Após 2 dias" = "#FF8F00"), name = NULL) +
      scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
      labs(
        title    = paste0("Tempo entre Início dos Sintomas e Início do Antiviral — ", grupo),
        subtitle = paste0(format(pct_48h, decimal.mark = ","), "% iniciaram em até 2 dias (",
                          ate_48h, "/", nrow(tratados), ") | Mediana: ",
                          median(tratados$dias), " dias | Referência: até 48 h (MS, 2023)"),
        x = "Dias desde o início dos sintomas", y = "Casos tratados", caption = texto_rodape
      ) +
      theme_minimal() +
      theme(plot.title = element_text(face = "bold"), legend.position = "top")
  }

  list(
    dist = dist, g_dist = g_dist, g_oport = g_oport,
    n = nrow(df), n_tratados = sum(df$ANTIVIRAL == 1, na.rm = TRUE),
    pct_tratados = round(sum(df$ANTIVIRAL == 1, na.rm = TRUE) / max(nrow(df), 1) * 100, 1),
    n_com_data = nrow(tratados), ate_48h = ate_48h, pct_48h = pct_48h,
    mediana_dias = if (nrow(tratados) > 0) median(tratados$dias) else NA_real_
  )
}

av_flu  <- analisar_antiviral(base_filtrada %>% filter(CLASSI_FIN == 1), "Influenza confirmada")
av_srag <- analisar_antiviral(base_filtrada, "Todos os casos de SRAG")

# --- Óbitos por influenza: tratamento e tempo até o antiviral -------------------
# Óbitos (EVOLUCAO = 2) entre os casos de influenza confirmada, comparados com
# os casos de influenza que evoluíram para cura (EVOLUCAO = 1).
CAT_TRAT <- c("Antiviral em até 2 dias", "Antiviral em 3 a 5 dias", "Antiviral após 5 dias",
              "Antiviral sem data válida", "Não recebeu antiviral", "Ignorado/Não registrado")

trat_desfecho <- base_filtrada %>%
  filter(CLASSI_FIN == 1, EVOLUCAO %in% c(1, 2)) %>%
  mutate(
    desfecho = if_else(EVOLUCAO == 2, "Óbitos por influenza", "Curados de influenza"),
    dias = as.numeric(parseia_data(DT_ANTIVIR) - parseia_data(DT_SIN_PRI)),
    dias = if_else(!is.na(dias) & dias >= 0 & dias <= 60, dias, NA_real_),
    categoria = case_when(
      ANTIVIRAL == 1 & !is.na(dias) & dias <= 2 ~ CAT_TRAT[1],
      ANTIVIRAL == 1 & !is.na(dias) & dias <= 5 ~ CAT_TRAT[2],
      ANTIVIRAL == 1 & !is.na(dias)             ~ CAT_TRAT[3],
      ANTIVIRAL == 1                            ~ CAT_TRAT[4],
      ANTIVIRAL == 2                            ~ CAT_TRAT[5],
      TRUE                                      ~ CAT_TRAT[6]
    ),
    categoria = factor(categoria, levels = CAT_TRAT),
    desfecho  = factor(desfecho, levels = c("Óbitos por influenza", "Curados de influenza"))
  )

tabela_trat_desfecho <- trat_desfecho %>%
  group_by(desfecho) %>%
  summarise(
    casos            = n(),
    tratados         = sum(ANTIVIRAL == 1, na.rm = TRUE),
    pct_tratados     = round(tratados / casos * 100, 1),
    nao_tratados     = sum(ANTIVIRAL == 2, na.rm = TRUE),
    ate_2_dias       = sum(categoria == CAT_TRAT[1]),
    pct_ate_2_dias   = round(ate_2_dias / pmax(sum(!is.na(dias) & ANTIVIRAL == 1), 1) * 100, 1),
    mediana_dias     = median(dias[ANTIVIRAL == 1], na.rm = TRUE),
    .groups = "drop"
  )

gD10c <- NULL
if (nrow(trat_desfecho) > 0) {
  gD10c <- trat_desfecho %>%
    count(desfecho, categoria, .drop = FALSE) %>%
    group_by(desfecho) %>%
    mutate(total = sum(n), pct = if_else(total > 0, n / total * 100, 0)) %>%
    ungroup() %>%
    mutate(desfecho_lab = paste0(desfecho, "\n(N = ", total, ")")) %>%
    ggplot(aes(x = pct, y = desfecho_lab, fill = categoria)) +
    geom_col(width = 0.6, position = position_stack(reverse = TRUE)) +
    geom_text(aes(label = ifelse(pct >= 4, paste0(n, "\n", format(round(pct, 1), decimal.mark = ","), "%"), "")),
              position = position_stack(vjust = 0.5, reverse = TRUE), size = 3, color = "white", lineheight = 0.9) +
    scale_fill_manual(values = c("Antiviral em até 2 dias" = "#1B5E20", "Antiviral em 3 a 5 dias" = "#66BB6A",
                                 "Antiviral após 5 dias" = "#FF8F00", "Antiviral sem data válida" = "#8D6E63",
                                 "Não recebeu antiviral" = "#C62828", "Ignorado/Não registrado" = "grey60"),
                      name = NULL, drop = FALSE) +
    guides(fill = guide_legend(nrow = 2)) +
    labs(
      title    = "Tratamento Antiviral e Tempo até o Início — Óbitos e Curados de Influenza",
      subtitle = paste0(escopo_titulo, " | Dias entre o início dos sintomas e o início do antiviral | ",
                        "Influenza confirmada (classificação final)"),
      x = "% dos casos", y = NULL, caption = texto_rodape
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"), legend.position = "top")
}

# Mantidos para a planilha Excel e para compatibilidade
antiviral_dist <- av_srag$dist
gD10 <- av_srag$g_dist



# ==============================================================================
# BLOCO D11 — STATUS VACINAL (COVID-19)
# ==============================================================================
# VACINA_COV: 1 = Sim, 2 = Não, 9 = Ignorado

vacinal_dist <- base_filtrada %>%
  mutate(
    vacina_label = case_when(
      VACINA_COV == 1 ~ "Vacinado",
      VACINA_COV == 2 ~ "Não vacinado",
      TRUE            ~ "Ignorado/Não registrado"
    )
  ) %>%
  group_by(vacina_label) %>%
  summarise(total = n(), .groups = "drop") %>%
  mutate(pct = round(total / sum(total) * 100, 1))

gD11 <- ggplot(vacinal_dist,
               aes(x = total, y = fct_reorder(vacina_label, total))) +
  geom_col(fill = "#264653") +
  geom_text(aes(label = paste0(total, " (", pct, "%)")),
            hjust = -0.08, size = 3.5) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.22))) +
  labs(
    title    = paste0("Status Vacinal contra COVID-19 — ", escopo_titulo,
                      " (N = ", format(nrow(base_filtrada), big.mark = ".", decimal.mark = ","), ")"),
    subtitle = "[Não verificado] Completitude deste campo varia muito por período e município.",
    x = "Número de casos", y = NULL,
    caption = texto_rodape
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))



# ==============================================================================
# BLOCO D11b — VACINAÇÃO CONTRA INFLUENZA
# ==============================================================================
# VACINA: 1 = Sim, 2 = Não, 9 = Ignorado (vacina contra gripe na última
# campanha). Comparação entre casos e óbitos de influenza confirmada.

rotular_vacina <- function(x) dplyr::case_when(
  x == 1 ~ "Vacinado",
  x == 2 ~ "Não vacinado",
  TRUE   ~ "Ignorado/Não registrado"
)

vacina_flu <- dplyr::bind_rows(
  base_filtrada %>% dplyr::filter(CLASSI_FIN == 1) %>%
    dplyr::mutate(grupo = "Casos de influenza"),
  base_filtrada %>% dplyr::filter(CLASSI_FIN == 1, EVOLUCAO == 2) %>%
    dplyr::mutate(grupo = "Óbitos por influenza")
) %>%
  dplyr::mutate(status = factor(rotular_vacina(VACINA),
                                levels = c("Vacinado", "Não vacinado", "Ignorado/Não registrado"))) %>%
  dplyr::count(grupo, status, .drop = FALSE) %>%
  dplyr::group_by(grupo) %>%
  dplyr::mutate(total = sum(n), pct = round(n / total * 100, 1)) %>%
  dplyr::ungroup()

n_flu_casos  <- sum(base_filtrada$CLASSI_FIN == 1, na.rm = TRUE)
n_flu_obitos <- sum(base_filtrada$CLASSI_FIN == 1 & base_filtrada$EVOLUCAO == 2, na.rm = TRUE)

gD11b <- vacina_flu %>%
  dplyr::mutate(grupo = paste0(grupo, " (N = ", total, ")")) %>%
  ggplot(aes(x = pct, y = grupo, fill = status)) +
  geom_col(width = 0.6, position = position_stack(reverse = TRUE)) +
  geom_text(aes(label = ifelse(pct >= 4, paste0(format(pct, decimal.mark = ","), "%"), "")),
            position = position_stack(vjust = 0.5, reverse = TRUE), color = "white", size = 3.5) +
  scale_fill_manual(values = c("Vacinado" = "#2E7D32", "Não vacinado" = "#C62828",
                               "Ignorado/Não registrado" = "grey60"), name = NULL) +
  labs(
    title    = "Vacinação contra Influenza — Casos e Óbitos de Influenza Confirmada",
    subtitle = paste0(escopo_titulo, " | Vacina contra gripe na última campanha, conforme registrado no SIVEP-Gripe"),
    x = "% dos casos", y = NULL, caption = texto_rodape
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"), legend.position = "top")


# ==============================================================================
# BLOCO D12 — MORTALIDADE POR MUNICÍPIO (gráfico de barras)
# ==============================================================================
# Complementa o mapa já existente com uma visualização ordenada.

gD12 <- casos_municipio %>%
  filter(obitos_srag > 0) %>%
  mutate(
    municipio = fct_reorder(str_to_title(municipio), mortalidade_100k),
    rotulo    = paste0(mortalidade_100k, " /100k  (", obitos_srag, " óbitos)")
  ) %>%
  ggplot(aes(x = mortalidade_100k, y = municipio)) +
  geom_col(fill = "#A30000") +
  geom_text(aes(label = rotulo), hjust = -0.05, size = 3) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.3))) +
  labs(
    title    = paste0("Mortalidade por SRAG por Município — 15ª RS Maringá",
                      " (N = ", format(sum(casos_municipio$obitos_srag), big.mark = ".", decimal.mark = ","), " óbitos)"),
    subtitle = paste0("Por 100.000 habitantes | ", ROTULO_POPULACAO,
                      " | Ano(s): ", paste(anos_carregar, collapse = ", ")),
    x = "Mortalidade por 100.000 hab.", y = "Município",
    caption = texto_rodape
  ) +
  theme_minimal() +
  theme(plot.title = element_text(face = "bold"))



# ==============================================================================
# BLOCO D13 — TABELA-RESUMO DESCRITIVA POR MUNICÍPIO
# ==============================================================================

tabela_resumo_mun <- casos_municipio %>%
  select(municipio, casos, encerrados, obitos_srag, uti,
         incidencia_100k, mortalidade_100k, letalidade_pct) %>%
  mutate(
    municipio       = str_to_title(municipio),
    pct_uti         = round(uti / casos * 100, 1)
  ) %>%
  arrange(desc(incidencia_100k))

dir_tabelas <- file.path(dirname(DIR_GRAFICOS), "tabelas")
if (!dir.exists(dir_tabelas)) dir.create(dir_tabelas, recursive = TRUE)

writexl::write_xlsx(
  list(
    "resumo_municipios" = tabela_resumo_mun,
    "completitude"      = completitude,
    "comorbidades"      = freq_comorbidade,
    "letalidade_faixa"  = letalidade_faixa,
    "uti_faixa"         = uti_faixa,
    "criterio_conf"     = criterio_conf,
    "antiviral"         = antiviral_dist,
    "antiviral_influenza" = av_flu$dist,
    "antiviral_desfecho_flu" = tabela_trat_desfecho,
    "oportunidade"      = oport_regional,
    "taxas_faixa_etaria" = if (is.null(taxas_faixa)) tibble::tibble() else taxas_faixa,
    "oportunidade_mun"  = oport_municipio,
    "digitacao_unidade" = if (is.null(digitacao_unidade)) tibble::tibble() else digitacao_unidade,
    "digitacao_mes"     = if (is.null(digitacao_mes)) tibble::tibble() else digitacao_mes,
    "qualidade"         = tabela_qualidade,
    "consistencia_regras" = if (is.null(consistencia_regras)) tibble::tibble() else consistencia_regras,
    "consistencia_unidade" = if (is.null(consistencia_unidade)) tibble::tibble() else consistencia_unidade,
    "representatividade_rip" = if (is.null(rip_municipio)) tibble::tibble() else rip_municipio,
    "internacao_fora"   = if (is.null(internacao_fora)) tibble::tibble() else internacao_fora,
    "vacina_influenza"  = vacina_flu,
    "vacinal"           = vacinal_dist
  ),
  file.path(dir_tabelas, paste0("descritiva_15rs_", paste(anos_carregar, collapse = "_"), ".xlsx"))
)

message("Tabela Excel da estatística descritiva salva.")


# ==============================================================================
# RESUMO DO BLOCO DESCRITIVO
# ==============================================================================

message("\n", strrep("=", 60))
message("ESTATÍSTICA DESCRITIVA — RESUMO")
message(strrep("=", 60))
message("Gráficos gerados : D01 a D12")
message("Excel            : descritiva_15rs_", paste(anos_carregar, collapse = "_"), ".xlsx")
message(strrep("-", 60))
message("Completitude média (campos-chave): ",
        round(mean(completitude$pct_preenchido, na.rm = TRUE), 1), "%")
if (exists("oportunidade") && nrow(oportunidade) > 0) {
  message("Oportunidade notificação (mediana): ", med_op, " dias")
}
message("Comorbidade mais frequente: ",
        if (nrow(freq_comorbidade) > 0) freq_comorbidade$comorbidade[1] else "—")
message(strrep("=", 60))
