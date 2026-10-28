# ==============================================================================
# DIAGRAMA DE CONTROLE E CENÁRIO EPIDEMIOLÓGICO — PLANO DE CONTINGÊNCIA PR
# ==============================================================================
# Reproduz, para o escopo do painel (15ª RS ou um município), a metodologia
# do "Plano de Contingência para Vírus Respiratórios do Estado do Paraná",
# 2ª ed., setembro/2026, seção 9 (pp. 25–33):
#
# - SRAG hospitalizado (HOSPITAL = 1) por semana epidemiológica de início dos
#   sintomas; série histórica de 5 anos, excluídos 2020 e 2021.
# - Canal endêmico: mediana (Q2) como linha central e 3º quartil (Q3) como
#   limite superior (limiar epidêmico), por semana epidemiológica.
# - Diagrama por vírus: mesma construção com os casos confirmados por RT-PCR.
#   Vírus com série irregular na regional ficam só com a tendência (o Plano
#   manda analisá-los de forma qualitativa).
# - Tendência: regressão linear nas 6 semanas anteriores às 2 mais recentes
#   (janela de 8 semanas sem as 2 últimas). Conta como critério quando a
#   inclinação é positiva e a última semana da janela passa do Q3.
# - Óbitos por SRAG hospitalizado: alerta se o número subir por 3 semanas
#   seguidas dentro das últimas 8 semanas.
# - Cenário (Quadro 3): 0 Normalidade, 1 Mobilização, 2 Alerta, 3 Situação de
#   emergência; o 4 (Crise) depende da ocupação de leitos e não é calculado.
#
# Uso: source("diagrama_controle.R"); dc <- diagrama_controle(base, ano, corte)
# Usado por SCRIPT_Unificado.R (bloco GRÁFICO 06b).
# ==============================================================================

ANOS_EXCLUIDOS_CANAL <- c(2020, 2021)
N_ANOS_CANAL         <- 5
VIRUS_COM_CANAL      <- c("Influenza A", "Influenza B", "SARS-CoV-2", "VSR", "Rinovírus")
VIRUS_SO_TENDENCIA   <- c("Adenovírus", "Metapneumovírus", "Parainfluenza")

NOMES_CENARIO <- c("0" = "Normalidade", "1" = "Mobilização", "2" = "Alerta",
                   "3" = "Situação de emergência")

# Domingo que inicia a semana epidemiológica da data
dc_inicio_semana <- function(data) data - as.integer(format(data, "%u")) %% 7

# Códigos do SIVEP chegam como número ou texto conforme o ano/fonte
dc_eh <- function(x, valor = 1) suppressWarnings(as.integer(as.character(x))) %in% valor

dc_inclinacao <- function(y) unname(coef(lm(y ~ seq_along(y)))[2])

# TRUE se o número subiu por 3 semanas seguidas (3 aumentos consecutivos)
dc_ascensao <- function(y, semanas = 3) {
  r <- rle(diff(y) > 0)
  any(r$values & r$lengths >= semanas)
}

# base: casos da regional (todos os anos disponíveis), com ANO_BASE,
# DT_SIN_PRI, HOSPITAL, EVOLUCAO e campos de RT-PCR.
# data_corte: data de exportação; avalia-se a última semana completa.
diagrama_controle <- function(base, ano_atual, data_corte) {

  casos <- base %>%
    filter(dc_eh(HOSPITAL)) %>%
    mutate(inicio = dc_inicio_semana(parseia_data(substr(as.character(DT_SIN_PRI), 1, 10)))) %>%
    filter(!is.na(inicio))

  eventos <- bind_rows(
    casos %>% transmute(inicio, serie = "SRAG hospitalizado"),
    casos %>% filter(dc_eh(EVOLUCAO, 2)) %>% transmute(inicio, serie = "Óbitos por SRAG"),
    casos %>% transmute(
      inicio,
      `Influenza A`     = dc_eh(POS_PCRFLU) & dc_eh(TP_FLU_PCR, 1),
      `Influenza B`     = dc_eh(POS_PCRFLU) & dc_eh(TP_FLU_PCR, 2),
      `SARS-CoV-2`      = dc_eh(PCR_SARS2),
      VSR               = dc_eh(PCR_VSR),
      `Rinovírus`       = dc_eh(PCR_RINO),
      `Adenovírus`      = dc_eh(PCR_ADENO),
      `Metapneumovírus` = dc_eh(PCR_METAP),
      Parainfluenza     = dc_eh(PCR_PARA1) | dc_eh(PCR_PARA2) | dc_eh(PCR_PARA3) | dc_eh(PCR_PARA4)
    ) %>%
      tidyr::pivot_longer(-inicio, names_to = "serie", values_to = "positivo") %>%
      filter(positivo) %>%
      select(inicio, serie)
  )

  # Anos de referência: os 5 anos epidemiológicos mais recentes antes do
  # atual, sem 2020-2021, que tenham dados na base.
  anos_base <- sort(unique(MMWRweek::MMWRweek(casos$inicio)$MMWRyear))
  anos_ref  <- tail(setdiff(anos_base[anos_base < ano_atual], ANOS_EXCLUIDOS_CANAL), N_ANOS_CANAL)
  if (length(anos_ref) < 2) stop("Menos de 2 anos de referência para o diagrama de controle")

  t_atual <- dc_inicio_semana(dc_inicio_semana(data_corte + 1) - 1)  # última semana completa
  semanas <- seq(MMWRweek::MMWRweek2Date(min(anos_ref), 1, 1), t_atual, by = "week")

  series <- c("SRAG hospitalizado", "Óbitos por SRAG", VIRUS_COM_CANAL, VIRUS_SO_TENDENCIA)
  semanal <- eventos %>%
    filter(inicio %in% semanas) %>%
    count(serie, inicio) %>%
    tidyr::complete(serie = series, inicio = semanas, fill = list(n = 0L)) %>%
    mutate(ano = MMWRweek::MMWRweek(inicio)$MMWRyear,
           se  = MMWRweek::MMWRweek(inicio)$MMWRweek)

  # SE 53 só existe em alguns anos: usa os limites da SE 52
  canal <- semanal %>%
    filter(ano %in% anos_ref, se <= 52, serie %in% c("SRAG hospitalizado", VIRUS_COM_CANAL)) %>%
    group_by(serie, se) %>%
    summarise(q2 = median(n), q3 = quantile(n, 0.75, names = FALSE), .groups = "drop")
  canal <- bind_rows(canal, canal %>% filter(se == 52) %>% mutate(se = 53))

  valor <- function(s, datas) semanal$n[semanal$serie == s][match(datas, semanal$inicio[semanal$serie == s])]

  avaliar <- function(t) {
    janela <- t - 7 * (7:2)   # t-7 ... t-2
    ref    <- t - 14
    se_ref <- MMWRweek::MMWRweek(ref)$MMWRweek

    criterios <- lapply(c("SRAG hospitalizado", VIRUS_COM_CANAL, VIRUS_SO_TENDENCIA), function(s) {
      y   <- valor(s, janela)
      lim <- canal[canal$serie == s & canal$se == se_ref, ]
      tibble(serie = s, casos_ref = tail(y, 1),
             q2 = if (nrow(lim)) lim$q2 else NA_real_,
             q3 = if (nrow(lim)) lim$q3 else NA_real_,
             inclinacao = round(dc_inclinacao(y), 2))
    }) %>%
      bind_rows() %>%
      mutate(
        tipo = case_when(serie == "SRAG hospitalizado" ~ "geral",
                         serie %in% VIRUS_COM_CANAL    ~ "vírus com canal",
                         TRUE                          ~ "vírus só tendência"),
        acima_q3  = casos_ref > q3,
        tendencia = inclinacao > 0,
        criterio  = tipo == "vírus com canal" & acima_q3 & tendencia
      )

    obitos <- valor("Óbitos por SRAG", t - 7 * (7:0))
    geral  <- criterios[criterios$tipo == "geral", ]
    virus  <- criterios$serie[criterios$criterio]
    asc    <- dc_ascensao(obitos)

    cenario <- if (geral$acima_q3 && length(virus) && asc) 3L
               else if (geral$acima_q3 && length(virus)) 2L
               else if (length(virus)) 1L
               else 0L

    list(
      resumo = tibble(
        semana_avaliada = t, se_avaliada = MMWRweek::MMWRweek(t)$MMWRweek,
        semana_ref = ref, se_ref = se_ref,
        janela = paste0("SE ", MMWRweek::MMWRweek(min(janela))$MMWRweek, " a ", se_ref),
        srag_ref = geral$casos_ref, srag_q2 = geral$q2, srag_q3 = geral$q3,
        srag_inclinacao = geral$inclinacao,
        srag_zona = if (geral$acima_q3) "acima do limiar epidêmico (Q3)"
                    else if (geral$casos_ref > geral$q2) "entre a mediana e o limiar"
                    else "até a mediana",
        virus_criterio = paste(virus, collapse = ", "),
        virus_so_tendencia_alta = paste(criterios$serie[criterios$tipo == "vírus só tendência" &
                                                          criterios$tendencia], collapse = ", "),
        obitos_8sem = paste(obitos, collapse = " "),
        obitos_ascensao = asc,
        cenario = cenario
      ),
      criterios = criterios
    )
  }

  # Cenário de cada semana do ano atual (histórico) e critérios da última
  semanas_ano <- semanas[MMWRweek::MMWRweek(semanas)$MMWRyear == ano_atual]
  avaliacoes  <- lapply(semanas_ano, avaliar)
  cenarios    <- bind_rows(lapply(avaliacoes, `[[`, "resumo")) %>%
    mutate(
      # Cenário 3 por mais de 2 semanas: o Plano manda avaliar o Cenário 4,
      # que depende da ocupação de leitos (fora do SIVEP-Gripe).
      persistente_3 = cenario == 3 & lag(cenario, 1, default = 0) == 3 & lag(cenario, 2, default = 0) == 3,
      cenario_nome  = NOMES_CENARIO[as.character(cenario)]
    )

  list(
    semanal   = semanal,
    canal     = canal,
    anos_ref  = anos_ref,
    cenarios  = cenarios,
    criterios = avaliacoes[[length(avaliacoes)]]$criterios,
    atual     = cenarios[nrow(cenarios), ],
    ano_atual = ano_atual
  )
}
