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
    subtitle = paste0("Por 100.000 habitantes | Pop. IBGE 2025",
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
