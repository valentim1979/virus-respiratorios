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
- **Semana epidemiológica:** semana epidemiológica de **início dos sintomas** (`SEM_PRI`), padrão do InfoGripe/Fiocruz e do Ministério da Saúde para análise de tendência, por aproximar o momento da infecção. Todas as séries semanais (curva epidêmica, canal endêmico, notificados, confirmados, variação semanal, tendência viral e séries por estabelecimento) usam essa semana.
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
| Valor preditivo positivo da definição de caso | casos com `CLASSI_FIN` = 1, 2 ou 5 ÷ casos de SRAG | satisfatório se > 20% |
| Oportunidade de atendimento | % com `DT_INTERNA` − `DT_SIN_PRI` ≤ 1 dia | — |
| Oportunidade de notificação | % com `DT_NOTIFIC` − `DT_INTERNA` ≤ 1 dia | — |
| Oportunidade de tratamento | % dos tratados com `DT_ANTIVIR` − `DT_INTERNA` ≤ 2 dias | — |
| Oportunidade de coleta | % com `DT_COLETA` − `DT_INTERNA` ≤ 7 dias | — |
| Oportunidade de encerramento | % dos encerrados com `DT_ENCERRA` − `DT_NOTIFIC` ≤ 60 dias | — |

A vigilância é considerada oportuna quando a média simples dos cinco indicadores de oportunidade é ≥ 70%. Intervalos negativos contam como oportunos. Intervalos menores que −30 ou maiores que 120 dias são excluídos como erro de digitação. Os indicadores são apresentados para a regional e por município de residência.

### 6.2 Canal endêmico

O canal endêmico é construído com as contagens semanais de casos da 15ª RS nos anos de referência **pós-pandêmicos** (de 2022 ao ano anterior ao corrente; 2020 e 2021 são excluídos pelo perfil atípico da pandemia de covid-19). Para cada semana epidemiológica, calculam-se a mediana e os percentis 25, 75 e 90 das contagens dos anos de referência. A contagem da semana do ano corrente é classificada em:

- **abaixo do esperado:** menor que P25;
- **esperado:** de P25 a P75;
- **alerta:** maior que P75 e até P90;
- **epidêmico:** maior que P90.

O canal só é gerado com pelo menos dois anos de referência.

## 7. Análises descritivas

Para o ano corrente, o painel apresenta:

- curva epidêmica comparada com os anos anteriores;
- distribuição semanal de notificados e confirmados;
- incidência e mortalidade por município, em gráficos e mapas coropléticos;
- distribuição por sexo, raça/cor, faixa etária (pirâmides de notificados e de óbitos), classificação final e evolução;
- circulação viral: total, tendência semanal, tipos e linhagens de influenza, composição por faixa etária e variação anual desde 2022.

A página de estatística descritiva acrescenta:

- completitude das variáveis-chave;
- oportunidade de notificação;
- tempo de internação até o desfecho (cura ou óbito, entre 0 e 120 dias);
- frequência de comorbidades, no total e entre óbitos;
- letalidade por faixa etária e sexo;
- proporção de UTI por faixa etária;
- taxas de incidência, internação em UTI e mortalidade por 100 mil habitantes por faixa etária, e pirâmide de incidência por faixa etária e sexo;
- critério de confirmação;
- uso de antiviral e tempo até o início do tratamento, para influenza confirmada e para todos os casos de SRAG;
- situação vacinal contra covid-19;
- situação vacinal contra influenza (`VACINA`) entre casos e óbitos de influenza confirmada;
- consistência, valor preditivo positivo e indicadores de oportunidade da vigilância (seção 6.1);
- mortalidade por município, com tabela-resumo municipal.

As interpretações que dependem de inferência e não podem ser confirmadas apenas com os dados descritivos são sinalizadas no painel como **[Inferência]**.

## 8. Modelagem

### 8.1 Nowcasting — correção do atraso de digitação

**Problema.** As contagens das semanas mais recentes são subestimadas porque parte dos casos ainda não foi digitada no SIVEP-Gripe. Isso produz uma falsa tendência de queda no fim da curva. Na 15ª RS, em 2026, 26% dos casos foram digitados na mesma semana epidemiológica do início dos sintomas, 82% até a semana seguinte, 93% até 2 semanas, 96% até 3 semanas e 98% até 8 semanas.

**Modelo.** Usa-se o modelo do triângulo de notificação (*chain-ladder*) com regressão binomial negativa — versão frequentista da abordagem de Bastos et al. (2019), usada no InfoGripe/Fiocruz. Para cada semana epidemiológica de início dos sintomas *t* (domingo a sábado) e atraso *d* (semanas inteiras entre a semana de início dos sintomas e a semana de digitação, `DT_DIGITA`):

n<sub>t,d</sub> ~ Binomial Negativa(μ<sub>t,d</sub>, θ), com log(μ<sub>t,d</sub>) = α<sub>t</sub> + β<sub>d</sub>

- α<sub>t</sub> é o efeito da semana de início dos sintomas (nível da epidemia) e β<sub>d</sub>, o efeito do atraso (distribuição de atraso, suposta constante dentro da janela).
- **Atraso máximo D = 4:** atrasos de 4 semanas ou mais são agrupados na categoria 4.
- **Janela de 26 semanas:** o modelo usa as últimas 26 semanas epidemiológicas, inclusive da virada do ano, já que usa os casos de todos os anos carregados.
- **Corte:** os dados são truncados no último sábado anterior à data da digitação mais recente, para que a semana T (a mais recente) e todas as células observadas correspondam a semanas completas.
- **Ajuste:** são usadas só as células observáveis (t + d ≤ T), com `MASS::glm.nb`.
- **Estimativa:** o total da semana *t* é a soma dos casos já digitados com as células ainda não observadas (t + d > T). Essas células são simuladas 4.000 vezes: os coeficientes são sorteados de uma normal multivariada com a matriz de covariância estimada, e as contagens, da binomial negativa com o θ estimado. São reportados a mediana e os percentis 2,5 e 97,5 (intervalo de predição de 95%).
- **Proteção numérica:** quando a semana mais recente não tem nenhum caso digitado, seu coeficiente fica indeterminado. Por isso o preditor linear simulado é limitado a log(5 × maior total semanal observado na janela).
- **Escopo:** o modelo é ajustado para o escopo do painel (15ª RS, por município de residência).

**Escolha de D e da janela.** Foram comparados D = 3, 4 e 5 e janelas de 16 e 26 semanas na validação retrospectiva. Com D maior, categorias de atraso longo ficam sem nenhum caso em algumas janelas, o coeficiente diverge e o total estimado explode (erros acima de 200% num teste inicial com D = 8). D = 4 com 26 semanas teve o melhor equilíbrio entre erro e cobertura.

**Validação retrospectiva.** O nowcast foi refeito em 20 cortes semanais passados (sábados), usando só os casos digitados até cada corte. As estimativas das três semanas mais recentes de cada corte foram comparadas com o total conhecido hoje. Só entraram cortes com pelo menos D semanas de seguimento posterior, para que o total de referência estivesse praticamente completo. A validação é refeita automaticamente a cada atualização do painel e publicada junto com a estimativa. Resultado da execução de 03/10/2026, com cortes de 18/04/2026 a 29/08/2026 (a versão mais recente fica em `dados/nowcasting_validacao.csv`):

| Semana em relação ao corte | Erro absoluto médio sem correção | Erro absoluto médio do nowcast | Cobertura do intervalo de 95% |
|---|---|---|---|
| Última semana (T) | 74,1% | 27,1% | 90% |
| Penúltima (T − 1) | 17,5% | 7,2% | 95% |
| Antepenúltima (T − 2) | 7,5% | 3,2% | 100% |

O erro é a média de |estimado − final| ÷ final (o final é limitado a no mínimo 1), em %.

**Apresentação.** O painel mostra, na aba "Estimativa (nowcasting)", os casos já digitados (barras) e o total estimado com o intervalo de 95% para as 26 semanas da janela, além da tabela das últimas semanas e do desempenho na validação. As demais séries continuam mostrando apenas os casos digitados.

## 9. Software e reprodutibilidade

Todo o processamento é feito em R e publicado com Quarto como site estático no GitHub Pages:

- **R** 4.6.1;
- **pacotes:** MASS 7.3.65 (nowcasting), dplyr 1.2.1, ggplot2 4.0.3, sf 1.1.3, tmap 4.4.1, readr 2.2.0, foreign 0.8.91, writexl 2.0.1, tidytext 0.4.3, knitr 1.52, kableExtra 1.4.1;
- **Quarto** 1.10.18.

A população por município, sexo e idade é obtida por `baixar_populacao.R`, que preenche automaticamente o formulário do Tabnet (UF Paraná, linha = município, coluna = idade simples, um pedido por sexo). O script verifica se vieram os 399 municípios e se o total estadual está na faixa esperada. A tabela resultante fica versionada no repositório.

O código e o histórico de alterações estão versionados em git (repositório `valentim1979/virus-respiratorios`). O fluxo completo — anonimização, análise, renderização e publicação — é executado automaticamente quando uma nova exportação do SIVEP-Gripe é disponibilizada.

## 10. Limitações

- **Semanas recentes incompletas:** como as séries usam a semana de início dos sintomas, as semanas mais recentes acumulam casos ainda não internados, notificados ou digitados. O efeito é mais intenso do que com a semana de notificação. O painel alerta o leitor e apresenta a estimativa por nowcasting (seção 8.1), mas as demais séries, o canal endêmico e os indicadores do ano corrente continuam usando apenas os casos digitados.
- **Letalidade entre encerrados:** restringir o denominador aos casos encerrados evita a subestimação pelos casos ainda internados. Em contrapartida, pode superestimar a letalidade no ano corrente se os óbitos forem registrados mais rápido que as altas, e exclui casos com evolução ignorada.
- **Denominador:** as taxas usam a estimativa populacional mais recente disponível (hoje, 2025) para todos os anos, inclusive o ano corrente, que ainda não tem estimativa publicada. As estimativas municipais por idade e sexo do Ministério da Saúde são projeções e têm incerteza maior em municípios pequenos e nas faixas etárias extremas.
- **Menores de 1 ano:** a população é publicada por ano de idade, então as taxas não separam 0–6 e 6–11 meses (essa divisão continua disponível nas contagens absolutas). A idade do caso vem de `COD_IDADE`; códigos em dias ou meses entram como 0 ano.
- **Nowcasting:** o modelo supõe que a distribuição de atraso é constante na janela de 26 semanas. Mudanças operacionais na digitação (mutirões, greves, troca de sistema) violam essa hipótese. A estimativa da última semana é muito incerta (intervalo largo) porque depende de cerca de 1/4 dos casos. O modelo corrige apenas o atraso de digitação de casos que serão notificados — não corrige subnotificação.
- **Canal endêmico frágil:** o canal é baseado em poucos anos de referência (pós-2022), o que torna os percentis instáveis. Ele não é ajustado por tendência nem pelo tamanho da população.
- **Qualidade do preenchimento:** comorbidades, vacinação e uso de antiviral dependem da completitude dos campos (seção 6), e o não preenchimento não equivale à ausência da condição.
- **Casos de residentes fora do estado:** casos de residentes da 15ª RS notificados fora do Paraná podem não constar da exportação estadual. Na base aberta de 2026 isso representou 0,4% dos residentes do PR.

## 11. Referências

- BRASIL. Lei nº 13.709, de 14 de agosto de 2018. Lei Geral de Proteção de Dados Pessoais (LGPD).
- BRASIL. Ministério da Saúde. *Guia de Vigilância em Saúde*. 5. ed. Brasília: SVS, 2022.
- BRASIL. Ministério da Saúde. *Instrutivo de preenchimento da ficha de notificação de SRAG hospitalizado*. Brasília: DEVIT/SVS, 2022.
- BRASIL. Ministério da Saúde. DATASUS. *População residente – Estudo de estimativas populacionais por município, idade e sexo 2000-2025 – Brasil*. Tabnet. Disponível em: http://tabnet.datasus.gov.br/cgi/deftohtm.exe?ibge/cnv/popsvs2024br.def.
- BRASIL. Ministério da Saúde. *Guia de manejo e tratamento de influenza 2023*. Brasília: MS, 2023.
- MUTHURI, S. G. et al. Effectiveness of neuraminidase inhibitors in reducing mortality in patients admitted to hospital with influenza A H1N1pdm09 virus infection: a meta-analysis of individual participant data. *The Lancet Respiratory Medicine*, v. 2, n. 5, p. 395–404, 2014.
- RIBEIRO, I. G.; SANCHEZ, M. N. Avaliação do sistema de vigilância da síndrome respiratória aguda grave (SRAG) com ênfase em influenza, no Brasil, 2014 a 2016. *Epidemiologia e Serviços de Saúde*, v. 29, n. 3, e2020066, 2020.
- BASTOS, L. S. et al. Modelling reporting delays for outbreak detection in infectious disease data. *Journal of the Royal Statistical Society: Series A*, v. 182, n. 2, p. 535–555, 2019.
- MEYER, S.; HELD, L.; HÖHLE, M. Spatio-temporal analysis of epidemic phenomena using the R package surveillance. *Journal of Statistical Software*, v. 77, n. 11, 2017.

---

## Histórico de alterações

| Data | Alteração |
|---|---|
| 03/10/2026 | Nowcasting implementado (seção 8.1): triângulo de notificação com regressão binomial negativa, D = 4, janela de 26 semanas, intervalo de predição de 95% por simulação e validação retrospectiva em 20 cortes, publicados na aba "Estimativa (nowcasting)" do painel. |
| 03/10/2026 | População passa a vir do estudo de estimativas por município, idade e sexo do Ministério da Saúde (DATASUS/Tabnet), baixado por `baixar_populacao.R`, em vez de valores digitados no código (totais idênticos). Novas taxas de incidência, UTI e mortalidade por faixa etária e pirâmide de incidência por sexo (seção 4d da página descritiva). Rótulos de população passam a indicar o ano da estimativa usada. |
| 03/10/2026 | Página descritiva: indicadores de qualidade (inconsistência, VPP) e os cinco indicadores de oportunidade de Ribeiro & Sanchez (2020), com tabela por município; vacinação contra influenza entre casos e óbitos de influenza; quadro de indicação e posologia do oseltamivir (Guia MS 2023); correção da descrição dos campos de vacinação contra covid-19. |
| 03/10/2026 | Antiviral: seção passa a separar influenza confirmada e todos os casos de SRAG e ganha o indicador de oportunidade do tratamento (até 2 dias do início dos sintomas). |
| 03/10/2026 | Séries semanais passam da semana de notificação (`SEM_NOT`) para a de início dos sintomas (`SEM_PRI`). Letalidade passa a usar os casos encerrados como denominador (antes: todos os notificados). O painel ganha um quadro "Como ler este painel" e a página Sobre ganha um resumo da metodologia. |
| 03/10/2026 | Documento criado com a metodologia vigente. Inclusão da base estadual do SIVEP-Gripe (DBF) para o ano corrente, com anonimização por lista de permissão; a página descritiva passa a reutilizar os objetos da análise principal. |
