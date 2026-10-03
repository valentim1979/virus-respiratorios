# ==============================================================================
# VIGILÂNCIA EPIDEMIOLÓGICA — 15ª REGIONAL DE SAÚDE DE MARINGÁ
# Nowcasting de casos de SRAG por semana de início dos sintomas
# Autor   : Valentim Sala Junior
#
# Corrige o atraso de digitação nas semanas recentes. Modelo do "triângulo de
# notificação" (chain-ladder) com regressão binomial negativa:
#
#   n[t, d] ~ BinomialNegativa(mu[t, d], theta)
#   log(mu[t, d]) = alfa[t] + beta[d]
#
# t = semana epidemiológica de início dos sintomas (domingo a sábado);
# d = atraso em semanas até a digitação no SIVEP-Gripe (DT_DIGITA), 0..D,
#     com atrasos > D somados em D. D = 4 e janela de 26 semanas foram
#     escolhidos na validação retrospectiva (out/2026): com D maior, categorias
#     de atraso longo ficam com zero casos em algumas janelas e o modelo diverge.
# Só são observadas as células com t + d <= T (T = última semana completa).
# O total da semana t é o observado mais a soma das células ainda não
# observadas, simuladas a partir dos coeficientes (normal multivariada) e da
# binomial negativa — daí a mediana e o intervalo de predição de 95%.
#
# Uso: source("nowcasting.R") e chamar nowcast_srag() / validar_nowcast().
# Usado por SCRIPT_Unificado.R (bloco NOWCASTING).
# ==============================================================================

# Domingo que inicia a semana epidemiológica da data
inicio_semana_epi <- function(data) data - as.integer(format(data, "%u")) %% 7

# Último sábado <= data (fim da última semana epidemiológica completa)
ultimo_sabado <- function(data) inicio_semana_epi(data + 1) - 1

# df precisa ter DT_SIN_PRI e DT_DIGITA (texto AAAA-MM-DD ou dd/mm/aaaa)
preparar_atrasos <- function(df) {
  data.frame(
    sin = parseia_data(substr(df$DT_SIN_PRI, 1, 10)),
    dig = parseia_data(substr(df$DT_DIGITA, 1, 10))
  ) |>
    subset(!is.na(sin) & !is.na(dig) & dig >= sin) |>
    transform(semana = inicio_semana_epi(sin),
              atraso = as.integer(inicio_semana_epi(dig) - inicio_semana_epi(sin)) %/% 7)
}

nowcast_srag <- function(df, data_corte, janela = 26, d_max = 4,
                         n_sim = 4000, semente = 2026) {
  stopifnot(requireNamespace("MASS", quietly = TRUE))
  corte  <- ultimo_sabado(as.Date(data_corte))
  T_sem  <- inicio_semana_epi(corte)                    # domingo da semana T
  semanas <- seq(T_sem - 7 * (janela - 1), T_sem, by = 7)

  a <- preparar_atrasos(df)
  a <- a[a$dig <= corte & a$semana %in% semanas, ]
  a$atraso <- pmin(a$atraso, d_max)

  # Triângulo completo (inclusive zeros) e marca do que já é observável
  grade <- expand.grid(semana = semanas, atraso = 0:d_max)
  cont  <- aggregate(list(n = rep(1L, nrow(a))), a[c("semana", "atraso")], sum)
  grade <- merge(grade, cont, all.x = TRUE)
  grade$n[is.na(grade$n)] <- 0L
  grade$t <- as.integer(grade$semana - semanas[1]) %/% 7
  grade$observado <- grade$t + grade$atraso <= janela - 1
  grade$f_semana  <- factor(grade$semana)
  grade$f_atraso  <- factor(grade$atraso)

  obs <- grade[grade$observado, ]
  ajuste <- suppressWarnings(MASS::glm.nb(n ~ f_semana + f_atraso, data = obs))

  # Simulação das células não observadas
  faltam <- grade[!grade$observado, ]
  X <- model.matrix(~ f_semana + f_atraso, data = faltam)
  set.seed(semente)
  betas <- MASS::mvrnorm(n_sim, coef(ajuste), vcov(ajuste))
  # Semana recente com zero casos digitados tem coeficiente indeterminado
  # (variância enorme); limita mu a 5× o maior total semanal observado na janela.
  teto  <- 5 * max(tapply(obs$n, obs$semana, sum), 1)
  eta   <- pmin(X %*% t(betas), log(teto))
  mu    <- exp(eta)                                     # células × simulações
  sim   <- matrix(MASS::rnegbin(length(mu), mu = as.vector(mu), theta = ajuste$theta),
                  nrow = nrow(mu))
  faltam_semana <- rowsum(sim, as.character(faltam$semana))  # semana × simulações

  observado_semana <- tapply(obs$n, as.character(obs$semana), sum)
  res <- data.frame(semana = semanas, observado = as.integer(observado_semana[as.character(semanas)]))
  tot <- matrix(res$observado, nrow = nrow(res), ncol = n_sim)
  idx <- match(rownames(faltam_semana), as.character(semanas))
  tot[idx, ] <- tot[idx, ] + faltam_semana
  res$estimado   <- apply(tot, 1, median)
  res$li_95      <- apply(tot, 1, quantile, 0.025)
  res$ls_95      <- apply(tot, 1, quantile, 0.975)
  res$se         <- lubridate::epiweek(res$semana)
  res$data_corte <- corte
  attr(res, "ajuste") <- ajuste
  attr(res, "prob_atraso") <- {
    p <- exp(c(0, coef(ajuste)[grep("^f_atraso", names(coef(ajuste)))]))
    setNames(p / sum(p), 0:d_max)
  }
  res
}

# Validação retrospectiva: refaz o nowcast em cortes passados e compara com o
# total conhecido hoje para as semanas 0, 1 e 2 antes de cada corte. Só usa
# cortes com pelo menos `d_max` semanas de seguimento depois, para que o
# "verdadeiro" esteja praticamente completo.
validar_nowcast <- function(df, data_atual, n_cortes = 20, janela = 26, d_max = 4) {
  ultimo <- ultimo_sabado(as.Date(data_atual)) - 7 * d_max
  cortes <- seq(ultimo - 7 * (n_cortes - 1), ultimo, by = 7)
  a <- preparar_atrasos(df)
  verdadeiro <- table(as.character(a$semana))

  do.call(rbind, lapply(cortes, function(cc) {
    r <- nowcast_srag(df, cc, janela = janela, d_max = d_max, n_sim = 2000)
    r <- tail(r, 3)
    r$semanas_antes <- 2:0
    r$verdadeiro <- as.integer(verdadeiro[as.character(r$semana)])
    r$verdadeiro[is.na(r$verdadeiro)] <- 0L
    r
  }))
}

resumir_validacao <- function(v) {
  do.call(rbind, lapply(split(v, v$semanas_antes), function(x) data.frame(
    semanas_antes   = x$semanas_antes[1],
    n_cortes        = nrow(x),
    cobertura_ic95  = round(mean(x$verdadeiro >= x$li_95 & x$verdadeiro <= x$ls_95) * 100, 1),
    erro_nowcast    = round(mean(abs(x$estimado  - x$verdadeiro) / pmax(x$verdadeiro, 1)) * 100, 1),
    erro_sem_ajuste = round(mean(abs(x$observado - x$verdadeiro) / pmax(x$verdadeiro, 1)) * 100, 1)
  )))
}
