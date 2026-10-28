# Metodologia — Painel de Vigilância de SRAG da 15ª Regional de Saúde de Maringá/PR

Documento vivo, redigido no formato de seção de Métodos, para servir de base a artigos e à tese. Descreve o que o código deste repositório faz de fato; cada alteração metodológica deve ser registrada aqui e no [histórico](#histórico-de-alterações). O código citado está em `SCRIPT_Unificado.R` (análise principal), `descritiva_srag_15rs.R` (estatística descritiva) e `anonimizar_sivep.R` (anonimização).

---

## 1. Desenho do estudo

Estudo descritivo, de base populacional, com dados secundários de vigilância, dos casos de Síndrome Respiratória Aguda Grave (SRAG) hospitalizados notificados ao Sistema de Informação da Vigilância Epidemiológica da Gripe (SIVEP-Gripe), residentes na área de abrangência da 15ª Regional de Saúde do Paraná (Maringá). O produto é um painel (*dashboard*) web atualizado continuamente, que apoia o monitoramento semanal da situação epidemiológica.

## 2. Área e população

A 15ª Regional de Saúde compreende **30 municípios** do noroeste do Paraná, com **909.489 habitantes** em 2025. A lista de municípios, com o código IBGE de 6 dígitos, está fixada no `BLOCO 2` do script principal.

**População (denominadores).** As taxas usam a população residente do *Estudo de Estimativas Populacionais por Município, Idade e Sexo 2000-2025* do Ministério da Saúde, disponível no DATASUS/Tabnet. O script `baixar_populacao.R` consulta o Tabnet e baixa a população de todos os municípios do Paraná por sexo e idade simples (0 a 79 anos e "80 anos e mais"). O arquivo é gravado em `sivep_15rs/populacao_pr_idade_sexo_<ano>.csv`. O script principal usa o ano mais recente disponível, tanto para os totais municipais quanto para as taxas por faixa etária e sexo. Os totais municipais de 2025 coincidem exatamente com os valores usados anteriormente no painel (por exemplo, Maringá com 429.660 habitantes). A estimativa é atualizada uma vez por ano, quando o Ministério publica o novo estudo. Para análises estaduais, municípios, regionais e macrorregiões do Paraná (399 municípios, 22 regionais, 4 macrorregiões) vêm de `sivep_15rs/parana_macrorregiao.csv`; a malha municipal, do IBGE (2024).

## 3. Fontes de dados

| Período | Fonte | Atualização |
|---|---|---|
| Ano corrente (quando disponível) | Base estadual (PR) exportada do SIVEP-Gripe (DBF), por ano, pelo próprio serviço de vigilância | Diária (exportação manual) |
| Demais anos (2019 em diante) | Dados abertos de SRAG do Ministério da Saúde, via API do Portal Brasileiro de Dados Abertos (dados.gov.br; conjunto `39a4995f-4a6e-440f-8c8f-b00c81fae0d0`) | Semanal a quinzenal; anos encerrados são baixados uma única vez |

A base aberta do Ministério é publicada com defasagem de uma a duas semanas em relação ao sistema (por exemplo, o arquivo de 2026 disponível em 02/10/2026 tinha data de corte 28/09/2026). Por isso, para o ano corrente, o painel prioriza a exportação direta do SIVEP-Gripe. Dos arquivos nacionais da API são mantidos apenas os registros com residência, notificação ou internação no Paraná (UF ou código IBGE do município iniciado por 41), o que abrange todos os recortes usados no painel. Os dois formatos usam o mesmo dicionário de dados do SIVEP-Gripe e são harmonizados para o mesmo formato (todas as variáveis como texto; datas no padrão AAAA-MM-DD) antes da análise. A data de referência dos dados exibida no painel é a data da exportação do DBF ou, na sua ausência, a data de download do arquivo da API.

## 4. Aspectos éticos e proteção de dados (LGPD)

O estudo utiliza dados secundários de vigilância. A base exportada do SIVEP-Gripe contém dados pessoais e é tratada da seguinte forma (`anonimizar_sivep.R`), em conformidade com a Lei nº 13.709/2018 (LGPD):

1. **Minimização por lista de permissão:** são mantidas apenas as variáveis listadas em `colunas_permitidas.txt`, que reproduzem o conjunto de variáveis publicado como dado aberto pelo Ministério da Saúde, **excluindo** ainda a data de nascimento (`DT_NASC`) e o número da notificação (`NU_NOTIFIC`), e **acrescentando** apenas o bairro de residência (`NM_BAIRRO`) e a unidade notificadora (`ID_UNIDADE`, `CO_UNI_NOT`). Toda variável fora da lista é descartada, inclusive campos novos que o sistema venha a criar.
2. **Barreira de identificadores diretos:** o processamento é abortado, sem gravar nada, se algum identificador direto (nome, nome da mãe, CPF, CNS, telefone, logradouro, número, complemento, CEP, data de nascimento, número da notificação, observações) estiver presente na saída.
3. **Eliminação do dado bruto:** após a gravação e a verificação da base anonimizada, o arquivo original é apagado.
4. **Segregação do armazenamento:** a base anonimizada, em nível de registro, fica em diretório local de acesso restrito (permissão 0700), fora de pastas sincronizadas com serviços de nuvem e fora do repositório de código.
5. **Divulgação apenas agregada:** o painel publica somente contagens, proporções e taxas agregadas por semana, município, faixa etária, sexo e agente etiológico.

Por manter idade, sexo, município, bairro e datas, a base em nível de registro é considerada **pseudonimizada**, e não anonimizada no sentido estrito, pois a combinação desses atributos pode permitir reidentificação em áreas pequenas. Por isso não é compartilhada.

## 5. Definições operacionais

- **Caso de SRAG:** toda notificação de SRAG hospitalizado no SIVEP-Gripe cujo município de **residência** (`CO_MUN_RES`) pertence à 15ª RS. As análises estaduais de notificação usam a UF de notificação (`SG_UF_NOT = PR`), e as de estabelecimento usam o município de internação (`CO_MU_INTE`).
- **Ano do caso:** ano do arquivo de origem (`ANO_BASE`). Nos arquivos do Ministério e nas exportações anuais, notificação e início dos sintomas pertencem ao mesmo ano.
- **Semana epidemiológica:** semana epidemiológica de **início dos sintomas** (`SEM_PRI`), padrão do InfoGripe/Fiocruz e do Ministério da Saúde para análise de tendência, por aproximar o momento da infecção. Todas as séries semanais (curva epidêmica, diagrama de controle, notificados, confirmados, variação semanal, tendência viral e séries por estabelecimento) usam essa semana.
- **Classificação final** (`CLASSI_FIN`): 1 = influenza; 2 = outro vírus respiratório; 3 = outro agente etiológico; 4 = SRAG não especificada; 5 = covid-19. **Caso confirmado** (etiologia definida): classificações 1, 2, 3 ou 5.
- **Óbito por SRAG:** `EVOLUCAO = 2`. Óbito por outras causas: `EVOLUCAO = 3`.
- **Caso encerrado:** caso com desfecho registrado — `EVOLUCAO` igual a 1 (cura), 2 (óbito por SRAG) ou 3 (óbito por outras causas). Casos com evolução ignorada (9) ou em branco não são considerados encerrados.
- **Internação em UTI:** `UTI = 1`.
- **Faixa etária:** derivada de `COD_IDADE` (código do SIVEP em que o primeiro dígito indica a unidade e os três seguintes, o valor), agrupada em 0–6 meses, 6–11 meses, 1–4, 5–9, 10–14, 15–19, 20–29, 30–39, 40–49, 50–59 e 60 anos ou mais.
- **Detecção viral:** caso com RT-PCR positivo (`PCR_RESUL = 1`, `POS_PCRFLU = 1` ou `POS_PCROUT = 1`). Os agentes são identificados pelas variáveis específicas (`POS_PCRFLU`, `PCR_SARS2`, `PCR_VSR`, `PCR_RINO`, `PCR_ADENO`, `PCR_METAP`, `PCR_PARA1`–`PCR_PARA4`, `PCR_BOCA`, `PCR_OUTRO`). Um caso pode ter mais de um agente detectado.
- **Informação ausente:** valores vazios, `9`, `99`, `999`, "IGNORADO", "NAO INFORMADO" ou "SEM INFORMACAO".

## 6. Indicadores

| Indicador | Cálculo |
|---|---|
| Taxa de incidência de SRAG | casos residentes no período ÷ população residente estimada × 100.000 |
| Taxa de mortalidade por SRAG | óbitos por SRAG ÷ população residente estimada × 100.000 |
| Taxas específicas por faixa etária | casos, internações em UTI e óbitos por SRAG da faixa ÷ população da faixa × 100.000. Faixas: < 1 ano, 1–4, 5–9, 10–14, 15–19 e decenais de 20 a 79, mais 80 anos e mais. Também é calculada a incidência por faixa etária e sexo |
| Letalidade | óbitos por SRAG ÷ casos encerrados × 100 (faixas etárias com menos de 5 casos encerrados são omitidas) |
| Proporção de internação em UTI | casos com `UTI = 1` ÷ casos notificados × 100 |
| Variação semanal | (casos da semana − casos da semana anterior) ÷ casos da semana anterior × 100 |
| Completitude | registros com preenchimento válido ÷ total de registros × 100, por variável-chave; referência mínima de 80% |
| Oportunidade de notificação | dias entre o início dos sintomas (`DT_SIN_PRI`) e a notificação (`DT_NOTIFIC`); referência de até 7 dias |
| Proporção de tratamento antiviral | casos com `ANTIVIRAL = 1` ÷ casos do grupo × 100, para influenza confirmada (`CLASSI_FIN = 1`) e para todos os casos de SRAG |
| Oportunidade do tratamento antiviral | % dos tratados com início do antiviral (`DT_ANTIVIR`) até 2 dias após o início dos sintomas (`DT_SIN_PRI`) — aproximação da janela de 48 h do Guia de Manejo e Tratamento de Influenza (MS, 2023), já que o sistema registra só datas; são excluídos intervalos negativos ou maiores que 60 dias |

### 6.1 Qualidade e oportunidade da vigilância

Seguindo a avaliação nacional da vigilância de SRAG (Ribeiro & Sanchez, 2020), o painel calcula:

| Indicador | Cálculo | Referência |
|---|---|---|
| Inconsistência | amostras com `DT_COLETA` anterior a `DT_SIN_PRI` ÷ amostras com as duas datas | aceitável se ≤ 20% |
| Proporção com vírus respiratório confirmado ("VPP" em Ribeiro & Sanchez, 2020) | casos com `CLASSI_FIN` = 1, 2 ou 5 ÷ casos de SRAG | satisfatório se > 20% |
| Oportunidade de atendimento | % com `DT_INTERNA` − `DT_SIN_PRI` ≤ 1 dia | — |
| Oportunidade de notificação | % com `DT_NOTIFIC` − `DT_INTERNA` ≤ 1 dia | — |
| Oportunidade de tratamento | % dos tratados com `DT_ANTIVIR` − `DT_INTERNA` ≤ 2 dias | — |
| Oportunidade de coleta | % com `DT_COLETA` − `DT_INTERNA` ≤ 7 dias | — |
| Oportunidade de encerramento | % dos encerrados com `DT_ENCERRA` − `DT_NOTIFIC` ≤ 60 dias | — |

A vigilância é considerada oportuna quando a média simples dos cinco indicadores de oportunidade é ≥ 70%. Intervalos negativos contam como oportunos. Intervalos menores que −30 ou maiores que 120 dias são excluídos como erro de digitação. Os indicadores são apresentados para a regional e por município de residência.

O indicador que Ribeiro e Sanchez (2020) chamam de "valor preditivo positivo da definição de caso" é, na prática, a proporção de casos com vírus respiratório confirmado. O valor preditivo positivo no sentido das diretrizes do CDC (2001) — casos notificados que de fato têm a condição sob vigilância ÷ casos notificados — exigiria um padrão-ouro externo. Avaliações internacionais apontam o uso da positividade como "VPP" como um erro frequente; por isso o painel usa o nome descritivo e cita a origem.

**Metas da OPAS.** Para os casos notificados pelas unidades do escopo, o painel calcula os indicadores das diretrizes operacionais da OPAS para a vigilância sentinela de SRAG (PAHO, 2014, Anexo 7) que dependem só das datas da ficha:

| Indicador (OPAS, 2014) | Cálculo no painel | Meta |
|---|---|---|
| Oportunidade da notificação | mediana de `DT_NOTIFIC` − `DT_INTERNA` | ≤ 1 dia |
| Cobertura de investigação | casos com classificação final e `DT_ENCERRA` ÷ casos com evolução (1, 2 ou 3) registrada há pelo menos 30 dias | 90% |
| Cobertura de amostragem | casos com amostra (`AMOSTRA` = 1) coletada até 10 dias do início dos sintomas ÷ casos com critério válido para coleta (internados até 10 dias do início dos sintomas, `DT_INTERNA` − `DT_SIN_PRI` ≤ 10) | 90% |
| Oportunidade da coleta | mediana de `DT_COLETA` − `DT_INTERNA` | ≤ 2 dias |
| Cobertura de amostragem em UTI | casos com `UTI` = 1 e amostra ÷ casos com `UTI` = 1 | 100% |
| Cobertura de amostragem nos óbitos | óbitos por SRAG com amostra ÷ óbitos por SRAG | 100% |

Intervalos negativos ou maiores que 120 dias são excluídos das medianas. Na cobertura de amostragem, a OPAS restringe o denominador aos casos com critério válido para coleta, porque a amostra deve ser colhida até 10 dias do início dos sintomas; o painel usa como critério a internação até o 10º dia, primeiro momento em que a unidade pode coletar. O valor sobre todos os casos é apresentado como descritor: a diferença vem sobretudo de pacientes internados tardiamente, o que não depende da vigilância. Os demais indicadores do Anexo 7 (notificação dos denominadores semanais, captação comparada à busca ativa, qualidade, recebimento e processamento do espécime, oportunidade do boletim) exigem dados que a ficha do SIVEP-Gripe não traz.

### 6.2 Consistência por regras e representatividade

**Consistência (atributo do protocolo da OMS, 2001).** Nos casos do ano notificados pelas unidades do escopo, são verificadas regras de coerência entre campos. Onze regras de combinações impossíveis tiveram zero ocorrências na base de 2026, porque o SIVEP-Gripe as bloqueia na digitação: coleta, notificação ou internação antes dos sintomas (exceto infecção hospitalar), evolução antes da internação, saída da UTI antes da entrada, óbito sem data, gestante do sexo masculino, critério laboratorial sem amostra e classificação laboratorial de influenza, outro vírus ou covid-19 sem exame positivo correspondente. O painel mostra as regras que o sistema não bloqueia, com o percentual sobre os registros em que cada uma se aplica e a proporção de registros com pelo menos uma ocorrência por unidade notificadora:

- classificação final sem data de encerramento;
- evolução sem classificação final;
- UTI sem data de entrada;
- antiviral sem data de início;
- internação mais de 30 dias após o início dos sintomas;
- evolução mais de 120 dias após a internação.

**Representatividade (atributo do protocolo da OMS, 2001).** Para cada município de residência, calcula-se a razão de incidência padronizada por idade (padronização indireta): casos observados ÷ casos esperados, sendo os esperados a soma, nas faixas etárias, da taxa da regional × população do município. O intervalo de confiança de 95% é exato de Poisson (qui-quadrado). A razão é classificada como acima ou abaixo do esperado quando o intervalo exclui 1. Também se apresenta a distribuição dos residentes por local de internação (na regional, em outra regional do Paraná, fora do estado ou não informado).

### 6.3 Sensibilidade: comparação com SIH/SUS e SIM (análise anual)

Análise feita fora da rotina do painel, uma vez por ano e só para anos fechados, porque o SIH/SUS e o SIM são publicados com meses de atraso (`analise_sensibilidade.R`). Para os residentes da 15ª RS, compara de forma agregada (sem relacionamento de registros), por ano, município e faixa etária (< 5, 5–59, 60 anos e mais):

- casos do SIVEP-Gripe com data de internação no ano × internações no SUS (SIH/RD, AIH normal, sem duplicidade de número da AIH) com data de internação no ano e diagnóstico principal compatível com SRAG;
- óbitos por SRAG no SIVEP-Gripe (`EVOLUCAO = 2`, data da evolução no ano) × óbitos no SIM com causa básica compatível com SRAG, no total e só os ocorridos em hospital.

CID compatíveis com SRAG: J09–J18 (influenza e pneumonia), J20–J22 (outras infecções agudas das vias aéreas inferiores), B34.2, U07.1 e U07.2 (covid-19). Para cada ano de internação, o SIH é lido das competências de janeiro do ano a junho do ano seguinte, para incluir o faturamento tardio. Usa-se o SIM final quando publicado e, na falta dele, o preliminar.

Os óbitos também são comparados por grupo de causa: no SIM pela causa básica (influenza J09–J11; covid-19 B34.2, U07; pneumonia e demais J12–J22) e no SIVEP-Gripe pela classificação final (influenza; covid-19; demais). Arquivos do DATASUS obtidos manualmente podem ser colocados em `dbf_sivep/datasus/` (o SIM preliminar com o sufixo `_preliminar`) e a análise roda sem acesso ao FTP com `SENS_OFFLINE=1`.

As razões SIVEP ÷ SIH e SIVEP ÷ SIM medem a cobertura relativa, não a sensibilidade exata: o SIH cobre só o SUS, enquanto o SIVEP inclui a rede privada; o SIM inclui óbitos fora do hospital e pacientes que não preencheram a definição de caso de SRAG. A estimativa exata exigiria relacionamento probabilístico de registros, inviável com a base anonimizada.

### 6.4 Oportunidade de digitação por unidade notificadora

Mede o tempo entre a notificação (`DT_NOTIFIC`) e a digitação no SIVEP-Gripe (`DT_DIGITA`), para os casos do ano notificados por unidades localizadas nos municípios do escopo (`CO_MUN_NOT`), **inclusive de pacientes residentes em outras regionais**, já que a digitação é feita pela unidade notificadora (`ID_UNIDADE`, disponível apenas na base exportada do SIVEP-Gripe). Para cada unidade são apresentados o número de casos, a mediana e o percentil 90 do intervalo, a proporção digitada em até 1 dia e em até 7 dias, e o número de casos digitados mais de 30 dias após a notificação. Unidades com menos de 5 casos no ano são agrupadas. Intervalos negativos são excluídos como erro de data. Também é apresentada a mediana e o percentil 90 de cada etapa da cadeia — início dos sintomas → internação → notificação → digitação — e a proporção mensal de casos digitados em até 1 dia.

**Viés de seleção e correção.** A base contém apenas casos já digitados. Notificações recentes ainda não digitadas — justamente as de maior atraso — não aparecem, o que faria os períodos recentes parecerem mais oportunos. Na primeira versão da análise, por exemplo, setembro e outubro de 2026 apareciam com 81% e 100% de casos digitados em até 1 dia. Por isso só entram notificações com pelo menos 30 dias de acompanhamento até a digitação mais recente da base, e o gráfico mensal só mostra meses completos dentro desse período. Não foi identificada norma do Ministério da Saúde com prazo para a digitação da ficha de SRAG; por isso os percentuais em até 1 e até 7 dias são apresentados como descritores, sem meta.

### 6.5 Diagrama de controle e cenário epidemiológico

Segue a metodologia do Plano de Contingência para Vírus Respiratórios do Estado do Paraná (SESA-PR, 2ª ed., setembro de 2026, seção 9), aplicada aos residentes do escopo do painel (15ª RS ou um município) em vez do estado inteiro (`diagrama_controle.R`).

- **Série:** casos de SRAG hospitalizado (`HOSPITAL` = 1) por semana epidemiológica de início dos sintomas. O ano e a semana epidemiológica são calculados a partir de `DT_SIN_PRI` (calendário MMWR), de modo que um caso com sintomas no fim de dezembro, notificado no ano seguinte, entra no ano epidemiológico correto. Semanas sem casos contam como zero.
- **Anos de referência:** os 5 anos epidemiológicos mais recentes antes do ano corrente, excluídos 2020 e 2021 (pandemia). Para 2026: 2019, 2022, 2023, 2024 e 2025. Os anos anteriores vêm da base aberta (API dados.gov.br).
- **Canal endêmico:** para cada semana, a mediana (Q2) das contagens dos anos de referência é a linha central e o 3º quartil (Q3, `quantile` tipo 7 do R) é o limite superior, ou **limiar epidêmico**. A SE 53 usa os limites da SE 52.
- **Diagrama por vírus:** mesma construção com os casos com RT-PCR positivo para Influenza A (`POS_PCRFLU` = 1 e `TP_FLU_PCR` = 1), Influenza B (`TP_FLU_PCR` = 2), SARS-CoV-2, VSR e Rinovírus. Adenovírus, Metapneumovírus e Parainfluenza (1 a 4) têm série irregular na regional; para eles o Plano prevê só a tendência, analisada de forma qualitativa, e eles não entram no cálculo automático do cenário.
- **Semana avaliada e tendência:** a semana avaliada (t) é a última semana completa antes da exportação da base. A tendência é a inclinação de uma regressão linear simples das contagens nas semanas t−7 a t−2 (as 8 últimas semanas sem as 2 mais recentes, que ainda estão incompletas). O Plano não define teste de significância; qualquer inclinação positiva conta como tendência de aumento. Um vírus **cumpre o critério** quando a inclinação é positiva **e** a contagem da semana t−2 passa do Q3 dessa semana.
- **Óbitos:** óbitos por SRAG (`EVOLUCAO` = 2) entre os hospitalizados, por semana de início dos sintomas. Há ascensão quando o número sobe por 3 semanas seguidas (3 aumentos consecutivos) dentro das semanas t−7 a t.
- **Cenário (Quadro 3 do Plano):** 0 — Normalidade, se nenhum vírus cumpre o critério; 1 — Mobilização, se algum vírus cumpre o critério e o SRAG geral está até o Q3; 2 — Alerta, se algum vírus cumpre o critério e o SRAG geral passa do Q3; 3 — Situação de emergência, critérios do Cenário 2 mais ascensão de óbitos. O Cenário 4 (Crise) exige a persistência do Cenário 3 por mais de 2 semanas e colapso assistencial (ocupação de leitos), que não está no SIVEP-Gripe; o painel só sinaliza quando o Cenário 3 se mantém por 3 semanas seguidas. SRAG geral acima do Q3 sem vírus que cumpra o critério não tem cenário próprio no Quadro 3 e fica no Cenário 0, com a zona do SRAG geral informada.
- **Histórico:** o cenário é recalculado para cada semana do ano corrente como se ela fosse a mais recente, com os dados disponíveis hoje (portanto, mais completos do que estavam na época).

O canal anterior (percentis 25, 75 e 90 de 2022 em diante, até 25/10/2026) foi substituído por este método para o painel usar os mesmos limiares da SESA-PR.

## 7. Análises descritivas

Para o ano corrente, o painel apresenta:

- curva epidêmica comparada com os anos anteriores;
- distribuição semanal de notificados e confirmados;
- incidência e mortalidade por município, em gráficos e mapas coropléticos;
- distribuição por sexo, raça/cor, faixa etária (pirâmides de notificados e de óbitos), classificação final e evolução;
- circulação viral: total, tendência semanal, tipos e linhagens de influenza, composição por faixa etária e variação anual desde 2022.

O site tem duas páginas de detalhamento, que leem o mesmo contexto salvo pelo script principal.

A página **Perfil dos Casos** (`descritiva.qmd`) descreve os casos:

- frequência de comorbidades, no total e entre óbitos;
- letalidade por faixa etária e sexo;
- proporção de UTI por faixa etária;
- tempo de internação até o desfecho (cura ou óbito, entre 0 e 120 dias);
- taxas de incidência, internação em UTI e mortalidade por 100 mil habitantes por faixa etária, e pirâmide de incidência por faixa etária e sexo;
- critério de confirmação;
- uso de antiviral e tempo até o início do tratamento, para influenza confirmada e para todos os casos de SRAG;
- tratamento antiviral entre os óbitos por influenza (`CLASSI_FIN = 1` e `EVOLUCAO = 2`), comparado aos casos de influenza com cura (`EVOLUCAO = 1`): proporção tratada, proporção com início em até 2 dias e mediana de dias entre o início dos sintomas e o antiviral, em categorias (até 2 dias, 3 a 5, após 5, sem data válida, não tratado, ignorado);
- situação vacinal contra covid-19;
- situação vacinal contra influenza (`VACINA`) entre casos e óbitos de influenza confirmada;
- mortalidade por município, com tabela-resumo municipal.

A página **Avaliação da Vigilância** (`avaliacao.qmd`) organiza os indicadores da seção 6 pelos atributos das diretrizes do CDC (2001) e da OMS (2001, 2006):

- qualidade dos dados: completitude das variáveis-chave, inconsistência, proporção com vírus respiratório confirmado (seção 6.1) e regras de consistência por unidade notificadora (seção 6.2);
- oportunidade: os cinco indicadores de Ribeiro & Sanchez (2020), regionais e por município, as metas da OPAS (seção 6.1), o tempo de cada etapa até a digitação e a oportunidade de digitação por unidade notificadora e por mês (seção 6.4) e o intervalo entre o início dos sintomas e a notificação;
- representatividade: razão de incidência padronizada por idade, por município, e local de internação dos residentes (seção 6.2).

Sensibilidade, valor preditivo positivo, aceitabilidade, simplicidade, flexibilidade e estabilidade não são calculados no painel.

As interpretações que dependem de inferência e não podem ser confirmadas apenas com os dados descritivos são redigidas no painel como hipóteses ("pode indicar", "é compatível com"), separadas da descrição dos resultados.

## 8. Modelagem

### 8.1 Nowcasting — correção do atraso de digitação

**Problema.** As contagens das semanas mais recentes são subestimadas porque parte dos casos ainda não foi digitada no SIVEP-Gripe. Isso produz uma falsa tendência de queda no fim da curva. Na 15ª RS, em 2026 (exportação de 09/10/2026), 27% dos casos foram digitados na mesma semana epidemiológica do início dos sintomas, 82% até a semana seguinte, 93% até 2 semanas, 96% até 3 semanas e 98% até 8 semanas.

**Modelo.** Usa-se o modelo do triângulo de notificação (*chain-ladder*) com regressão binomial negativa — versão frequentista da abordagem de Bastos et al. (2019), usada no InfoGripe/Fiocruz. Para cada semana epidemiológica de início dos sintomas *t* (domingo a sábado) e atraso *d* (semanas inteiras entre a semana de início dos sintomas e a semana de digitação, `DT_DIGITA`):

n<sub>t,d</sub> ~ Binomial Negativa(μ<sub>t,d</sub>, θ), com log(μ<sub>t,d</sub>) = α<sub>t</sub> + β<sub>d</sub>

- α<sub>t</sub> é o efeito da semana de início dos sintomas (nível da epidemia) e β<sub>d</sub>, o efeito do atraso (distribuição de atraso, suposta constante dentro da janela).
- A estrutura — contagens por semana de ocorrência × atraso, verossimilhança binomial negativa e distribuição de atraso homogênea no tempo, com truncamento à direita — é a do nowcasting proposto por Höhle e an der Heiden (2014). Bastos et al. (2019), McGough et al. (2020) e Günther et al. (2020) estendem a abordagem com modelos bayesianos que suavizam α<sub>t</sub> no tempo (passeio aleatório) e permitem que a distribuição de atraso varie. Essas extensões exigem INLA ou JAGS e são uma evolução possível deste painel.
- **Atraso máximo D = 4:** atrasos de 4 semanas ou mais são agrupados na categoria 4.
- **Janela de 26 semanas:** o modelo usa as últimas 26 semanas epidemiológicas, inclusive da virada do ano, já que usa os casos de todos os anos carregados.
- **Corte:** os dados são truncados no último sábado anterior à data da digitação mais recente, para que a semana T (a mais recente) e todas as células observadas correspondam a semanas completas.
- **Ajuste:** são usadas só as células observáveis (t + d ≤ T), com `MASS::glm.nb`.
- **Estimativa:** o total da semana *t* é a soma dos casos já digitados com as células ainda não observadas (t + d > T). Essas células são simuladas 4.000 vezes: os coeficientes são sorteados de uma normal multivariada com a matriz de covariância estimada, e as contagens, da binomial negativa com o θ estimado. São reportados a mediana e os percentis 2,5 e 97,5 (intervalo de predição de 95%).
- **Proteção numérica:** quando a semana mais recente não tem nenhum caso digitado, seu coeficiente fica indeterminado. Por isso o preditor linear simulado é limitado a log(5 × maior total semanal observado na janela).
- **Escopo:** o modelo é ajustado para o escopo do painel (15ª RS, por município de residência).

**Escolha de D e da janela.** Foram comparados D = 3, 4 e 5 e janelas de 16 e 26 semanas na validação retrospectiva. Com D maior, categorias de atraso longo ficam sem nenhum caso em algumas janelas, o coeficiente diverge e o total estimado explode (erros acima de 200% num teste inicial com D = 8). D = 4 com 26 semanas teve o melhor equilíbrio entre erro e cobertura.

**Validação retrospectiva.** O nowcast foi refeito em 20 cortes semanais passados (sábados), usando só os casos digitados até cada corte. As estimativas das três semanas mais recentes de cada corte foram comparadas com o total conhecido hoje. Só entraram cortes com pelo menos D semanas de seguimento posterior, para que o total de referência estivesse praticamente completo. A validação é refeita automaticamente a cada atualização do painel e publicada junto com a estimativa. Resultado da execução de 09/10/2026, com cortes de 25/04/2026 a 05/09/2026 (a versão mais recente fica em `dados/nowcasting_validacao.csv`):

| Semana em relação ao corte | Erro absoluto médio sem correção | Erro absoluto médio do nowcast | Cobertura do intervalo de 95% |
|---|---|---|---|
| Última semana (T) | 74,6% | 24,3% | 95% |
| Penúltima (T − 1) | 17,4% | 7,6% | 95% |
| Antepenúltima (T − 2) | 7,3% | 3,6% | 100% |

O erro é a média de |estimado − final| ÷ final (o final é limitado a no mínimo 1), em %.

**Apresentação.** O painel mostra, na aba "Estimativa (nowcasting)", os casos já digitados (barras) e o total estimado com o intervalo de 95% para as 26 semanas da janela, além da tabela das últimas semanas e do desempenho na validação. Um segundo gráfico (`graficos/06d_nowcasting_validacao.png`) mostra a validação semana a semana: para cada um dos 20 cortes, a estimativa da última semana do corte (mediana e intervalo de 95%) e os casos digitados até o corte, sobre o total conhecido hoje. As demais séries continuam mostrando apenas os casos digitados.

## 9. Software e reprodutibilidade

Todo o processamento é feito em R e publicado com Quarto como site estático no GitHub Pages:

- **R** 4.6.1;
- **pacotes:** MASS 7.3.65 (nowcasting), dplyr 1.2.1, ggplot2 4.0.3, sf 1.1.3, tmap 4.4.1, readr 2.2.0, foreign 0.8.91, writexl 2.0.1, tidytext 0.4.3, knitr 1.52, kableExtra 1.4.1;
- **Quarto** 1.10.18.

A população por município, sexo e idade é obtida por `baixar_populacao.R`, que preenche automaticamente o formulário do Tabnet (UF Paraná, linha = município, coluna = idade simples, um pedido por sexo). O script verifica se vieram os 399 municípios e se o total estadual está na faixa esperada. A tabela resultante fica versionada no repositório.

O código e o histórico de alterações estão versionados em git (repositório `valentim1979/virus-respiratorios`). O fluxo completo — anonimização, análise, renderização e publicação — é executado automaticamente quando uma nova exportação do SIVEP-Gripe é disponibilizada.

## 10. Limitações

- **Semanas recentes incompletas:** como as séries usam a semana de início dos sintomas, as semanas mais recentes acumulam casos ainda não internados, notificados ou digitados. O efeito é mais intenso do que com a semana de notificação. O painel alerta o leitor e apresenta a estimativa por nowcasting (seção 8.1), mas as demais séries, o diagrama de controle e os indicadores do ano corrente continuam usando apenas os casos digitados.
- **Letalidade entre encerrados:** restringir o denominador aos casos encerrados evita a subestimação pelos casos ainda internados. Em contrapartida, pode superestimar a letalidade no ano corrente se os óbitos forem registrados mais rápido que as altas, e exclui casos com evolução ignorada.
- **Denominador:** as taxas usam a estimativa populacional mais recente disponível (hoje, 2025) para todos os anos, inclusive o ano corrente, que ainda não tem estimativa publicada. As estimativas municipais por idade e sexo do Ministério da Saúde são projeções e têm incerteza maior em municípios pequenos e nas faixas etárias extremas.
- **Menores de 1 ano:** a população é publicada por ano de idade, então as taxas não separam 0–6 e 6–11 meses (essa divisão continua disponível nas contagens absolutas). A idade do caso vem de `COD_IDADE`; códigos em dias ou meses entram como 0 ano.
- **Nowcasting:** o modelo supõe que a distribuição de atraso é constante na janela de 26 semanas. Mudanças operacionais na digitação (mutirões, greves, troca de sistema) violam essa hipótese. A estimativa da última semana é muito incerta (intervalo largo) porque depende de cerca de 1/4 dos casos. O modelo corrige apenas o atraso de digitação de casos que serão notificados — não corrige subnotificação.
- **Mudança na definição de caso:** a Nota Técnica nº 11/2026-CGCOVID/DEDT/SVSA/MS (agosto de 2026) passou a definir SRAG como síndrome gripal hospitalizada com dispneia, taquipneia e/ou saturação de O₂ ≤ 94% em ar ambiente; a ficha do SIVEP-Gripe (2023) ainda registra o critério de saturação < 95% e está em atualização. Quando a ficha mudar, contagens de anos anteriores e posteriores podem não ser diretamente comparáveis, o que afeta a curva comparativa, o diagrama de controle e o nowcasting.
- **Diagrama de controle com poucos casos:** o Plano foi desenhado para o estado inteiro. Na regional, as contagens semanais por vírus são pequenas e o Q3 de alguns vírus é zero em boa parte do ano (Influenza B em 48 das 53 semanas), de modo que um único caso com inclinação positiva cumpre o critério e leva ao Cenário 1. Em 2026, com a exportação de 25/10/2026, 18 das 42 semanas avaliadas ficaram em Cenário 1 e uma (SE 28) em Cenário 2. Com 5 anos de referência os quartis são instáveis, 2019 (anterior à pandemia) tem notificação menor que os anos seguintes, e o canal não é ajustado pelo tamanho da população. A tendência em 6 pontos sem teste de significância é sensível a flutuações aleatórias.
- **Qualidade do preenchimento:** comorbidades, vacinação e uso de antiviral dependem da completitude dos campos (seção 6), e o não preenchimento não equivale à ausência da condição.
- **Casos de residentes fora do estado:** casos de residentes da 15ª RS notificados fora do Paraná podem não constar da exportação estadual. Na base aberta de 2026 isso representou 0,4% dos residentes do PR.

## 11. Referências

- BRASIL. Lei nº 13.709, de 14 de agosto de 2018. Lei Geral de Proteção de Dados Pessoais (LGPD).
- BRASIL. Ministério da Saúde. *Guia de Vigilância em Saúde*. 5. ed. Brasília: SVS, 2022.
- BRASIL. Ministério da Saúde. *Instrutivo de preenchimento da ficha de notificação de SRAG hospitalizado*. Brasília: DEVIT/SVS, 2022.
- PAN AMERICAN HEALTH ORGANIZATION. *Operational guidelines for sentinel severe acute respiratory infection (SARI) surveillance*. Washington, DC: PAHO, 2014.
- BRASIL. Ministério da Saúde. Nota Técnica nº 11/2026-CGCOVID/DEDT/SVSA/MS. Brasília: Ministério da Saúde, 2026.
- WORLD HEALTH ORGANIZATION. *Protocol for the assessment of national communicable disease surveillance and response systems: guidelines for assessment teams*. Geneva: WHO, 2001. WHO/CDS/CSR/ISR/2001.2.
- BRASIL. Ministério da Saúde. DATASUS. *População residente – Estudo de estimativas populacionais por município, idade e sexo 2000-2025 – Brasil*. Tabnet. Disponível em: http://tabnet.datasus.gov.br/cgi/deftohtm.exe?ibge/cnv/popsvs2024br.def.
- BRASIL. Ministério da Saúde. *Guia de manejo e tratamento de influenza 2023*. Brasília: MS, 2023.
- MUTHURI, S. G. et al. Effectiveness of neuraminidase inhibitors in reducing mortality in patients admitted to hospital with influenza A H1N1pdm09 virus infection: a meta-analysis of individual participant data. *The Lancet Respiratory Medicine*, v. 2, n. 5, p. 395–404, 2014.
- RIBEIRO, I. G.; SANCHEZ, M. N. Avaliação do sistema de vigilância da síndrome respiratória aguda grave (SRAG) com ênfase em influenza, no Brasil, 2014 a 2016. *Epidemiologia e Serviços de Saúde*, v. 29, n. 3, e2020066, 2020.
- BASTOS, L. S. et al. A modelling approach for correcting reporting delays in disease surveillance data. *Statistics in Medicine*, v. 38, p. 4363–4377, 2019. DOI: 10.1002/sim.8303.
- GÜNTHER, F. et al. Nowcasting the COVID-19 pandemic in Bavaria. *Biometrical Journal*, 2020. DOI: 10.1002/bimj.202000112.
- HÖHLE, M.; AN DER HEIDEN, M. Bayesian nowcasting during the STEC O104:H4 outbreak in Germany, 2011. *Biometrics*, 2014. DOI: 10.1111/biom.12194.
- McGOUGH, S. F. et al. Nowcasting by Bayesian Smoothing: a flexible, generalizable model for real-time epidemic tracking. *PLOS Computational Biology*, 2020, e1007735.
- BASTOS, L. S. et al. COVID-19 e hospitalizações por SRAG no Brasil: uma comparação até a 12ª semana epidemiológica de 2020. *Cadernos de Saúde Pública*, v. 36, n. 4, e00070120, 2020. (Aplicação da correção do atraso de notificação às hospitalizações por SRAG.)
- PARANÁ. Secretaria de Estado da Saúde. *Plano de Contingência para Vírus Respiratórios do Estado do Paraná*. 2. ed. rev. e atual. Curitiba: SESA, set. 2026.
- MEYER, S.; HELD, L.; HÖHLE, M. Spatio-temporal analysis of epidemic phenomena using the R package surveillance. *Journal of Statistical Software*, v. 77, n. 11, 2017.

---

## Histórico de alterações

| Data | Alteração |
|---|---|
| 28/10/2026 | Canal endêmico substituído pelo diagrama de controle do Plano de Contingência para Vírus Respiratórios do Paraná (2026): SRAG hospitalizado, 5 anos de referência sem 2020–2021 (2019 e 2022–2025), mediana e Q3 como limiar epidêmico, tendência linear nas semanas t−7 a t−2, diagrama por vírus (RT-PCR), ascensão de óbitos e cenário 0 a 3 (seção 6.5). Antes: percentis 25, 75 e 90, com zonas esperado/alerta/epidêmico. Corrige também um erro do canal anterior, que dizia usar 2022–2025 mas só usava 2024 e 2025 (os demais anos não estavam na base usada). |
| 25/10/2026 | Nowcasting: novo gráfico da validação retrospectiva semana a semana (estimativa feita na época × total conhecido hoje) e número de casos digitados dentro das colunas do gráfico da estimativa. Gráfico de tendência viral ganha aviso sobre o atraso do resultado do RT-PCR. Nenhum cálculo mudou. |
| 10/10/2026 | Cobertura de amostragem (metas da OPAS) passa a usar no denominador os casos com critério válido para coleta (internados até 10 dias do início dos sintomas), como no Anexo 7; antes eram todos os casos de SRAG. Com a exportação de 09/10/2026: 98,5% (1.431 casos), ante 92,9% sobre todos os 1.537. |
| 09/10/2026 | A página "Estatística Descritiva" foi dividida em "Perfil dos Casos" (`descritiva.qmd`) e "Avaliação da Vigilância" (`avaliacao.qmd`), esta organizada pelos atributos de avaliação (qualidade dos dados, oportunidade, representatividade). Nenhum cálculo mudou. |
| 09/10/2026 | Exemplos numéricos do nowcasting (seção 8.1) atualizados para a exportação de 09/10/2026: distribuição do atraso de digitação e resultado da validação retrospectiva (cortes de 25/04 a 05/09/2026). |
| 08/10/2026 | Metas da OPAS (2014, Anexo 7) calculáveis com a ficha; o "VPP" passa a ser chamado de proporção com vírus respiratório confirmado, com a ressalva conceitual; registrada como limitação a nova definição de caso de SRAG (NT 11/2026, saturação ≤ 94%). |
| 05/10/2026 | Sensibilidade: comparação dos óbitos por grupo de causa (SIM × SIVEP) e execução com arquivos locais (`SENS_OFFLINE=1`). Primeira execução só com o SIM (2024 final, 2025 preliminar); o SIH aguarda o restabelecimento do FTP do DATASUS. |
| 04/10/2026 | Consistência por regras (as que o SIVEP-Gripe não bloqueia) por unidade notificadora e representatividade (razão de incidência padronizada por idade por município e local de internação dos residentes), conforme os atributos do protocolo da OMS (2001). |
| 03/10/2026 | Nowcasting: incluídas as referências de Höhle & an der Heiden (2014), McGough et al. (2020) e Günther et al. (2020), e a relação do modelo do painel com essa literatura. |
| 03/10/2026 | Correção da referência de Bastos et al. (2019): o artigo de método do nowcasting do InfoGripe é *Statistics in Medicine* 38:4363–77 (a citação anterior, atribuída ao *JRSS Series A*, estava errada). Incluído Bastos et al. (2020), *Cad Saúde Pública*. |
| 03/10/2026 | Removidos do painel os rótulos "[Inferência]" e o quadro que os explicava; as interpretações seguem redigidas como hipóteses. |
| 03/10/2026 | Antiviral: tabela e gráfico do tratamento e do tempo até o antiviral entre óbitos e curados de influenza confirmada. |
| 03/10/2026 | Oportunidade de digitação por unidade notificadora (seção 6.2): cadeia de tempos até a digitação, série mensal e tabela por unidade, com corte de 30 dias de acompanhamento para evitar o viés de casos ainda não digitados. |
| 03/10/2026 | Nowcasting implementado (seção 8.1): triângulo de notificação com regressão binomial negativa, D = 4, janela de 26 semanas, intervalo de predição de 95% por simulação e validação retrospectiva em 20 cortes, publicados na aba "Estimativa (nowcasting)" do painel. |
| 03/10/2026 | População passa a vir do estudo de estimativas por município, idade e sexo do Ministério da Saúde (DATASUS/Tabnet), baixado por `baixar_populacao.R`, em vez de valores digitados no código (totais idênticos). Novas taxas de incidência, UTI e mortalidade por faixa etária e pirâmide de incidência por sexo (seção 4d da página descritiva). Rótulos de população passam a indicar o ano da estimativa usada. |
| 03/10/2026 | Página descritiva: indicadores de qualidade (inconsistência, VPP) e os cinco indicadores de oportunidade de Ribeiro & Sanchez (2020), com tabela por município; vacinação contra influenza entre casos e óbitos de influenza; quadro de indicação e posologia do oseltamivir (Guia MS 2023); correção da descrição dos campos de vacinação contra covid-19. |
| 03/10/2026 | Antiviral: seção passa a separar influenza confirmada e todos os casos de SRAG e ganha o indicador de oportunidade do tratamento (até 2 dias do início dos sintomas). |
| 03/10/2026 | Séries semanais passam da semana de notificação (`SEM_NOT`) para a de início dos sintomas (`SEM_PRI`). Letalidade passa a usar os casos encerrados como denominador (antes: todos os notificados). O painel ganha um quadro "Como ler este painel" e a página Sobre ganha um resumo da metodologia. |
| 03/10/2026 | Documento criado com a metodologia vigente. Inclusão da base estadual do SIVEP-Gripe (DBF) para o ano corrente, com anonimização por lista de permissão; a página descritiva passa a reutilizar os objetos da análise principal. |
