# Metodologia — Painel de Vigilância de SRAG da 15ª Regional de Saúde de Maringá/PR

Documento vivo, redigido no formato de seção de Métodos, para servir de base a artigos e à tese. Descreve o que o código deste repositório faz de fato; cada alteração metodológica deve ser registrada aqui e no [histórico](#histórico-de-alterações). O código citado está em `SCRIPT_Unificado.R` (análise principal), `descritiva_srag_15rs.R` (estatística descritiva) e `anonimizar_sivep.R` (anonimização).

---

## 1. Desenho do estudo

Estudo descritivo, de base populacional, com dados secundários de vigilância, dos casos de Síndrome Respiratória Aguda Grave (SRAG) hospitalizados notificados ao Sistema de Informação da Vigilância Epidemiológica da Gripe (SIVEP-Gripe), residentes na área de abrangência da 15ª Regional de Saúde do Paraná (Maringá). O produto é um painel (*dashboard*) web atualizado continuamente, que apoia o monitoramento semanal da situação epidemiológica.

## 2. Área e população

A 15ª Regional de Saúde compreende **30 municípios** do noroeste do Paraná, com **909.489 habitantes** (estimativa populacional do IBGE para 2025, usada como denominador de todas as taxas). A lista de municípios, com código IBGE de 6 dígitos e população, está fixada no `BLOCO 2` do script principal. Para análises estaduais, municípios, regionais e macrorregiões do Paraná (399 municípios, 22 regionais, 4 macrorregiões) vêm de `sivep_15rs/parana_macrorregiao.csv`; a malha municipal, do IBGE (2024).

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
| Taxa de incidência de SRAG | casos residentes no período ÷ população IBGE 2025 × 100.000 |
| Taxa de mortalidade por SRAG | óbitos por SRAG ÷ população IBGE 2025 × 100.000 |
| Letalidade | óbitos por SRAG ÷ casos encerrados × 100 (faixas etárias com menos de 5 casos encerrados são omitidas) |
| Proporção de internação em UTI | casos com `UTI = 1` ÷ casos notificados × 100 |
| Variação semanal | (casos da semana − casos da semana anterior) ÷ casos da semana anterior × 100 |
| Completitude | registros com preenchimento válido ÷ total de registros × 100, por variável-chave; referência mínima de 80% |
| Oportunidade de notificação | dias entre o início dos sintomas (`DT_SIN_PRI`) e a notificação (`DT_NOTIFIC`); referência de até 7 dias |
| Proporção de tratamento antiviral | casos com `ANTIVIRAL = 1` ÷ casos do grupo × 100, para influenza confirmada (`CLASSI_FIN = 1`) e para todos os casos de SRAG |
| Oportunidade do tratamento antiviral | % dos tratados com início do antiviral (`DT_ANTIVIR`) até 2 dias após o início dos sintomas (`DT_SIN_PRI`) — aproximação da janela de 48 h do Guia de Manejo e Tratamento de Influenza (MS, 2023), já que o sistema registra só datas; são excluídos intervalos negativos ou maiores que 60 dias |

### 6.1 Canal endêmico

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
- critério de confirmação;
- uso de antiviral e tempo até o início do tratamento, para influenza confirmada e para todos os casos de SRAG;
- situação vacinal;
- mortalidade por município, com tabela-resumo municipal.

As interpretações que dependem de inferência e não podem ser confirmadas apenas com os dados descritivos são sinalizadas no painel como **[Inferência]**.

## 8. Modelagem (em desenvolvimento)

### 8.1 Nowcasting — correção do atraso de notificação (planejado)

**Problema.** As contagens das semanas mais recentes são subestimadas porque parte dos casos ainda não foi digitada no sistema (atraso de notificação). Isso produz uma falsa tendência de queda no fim da curva.

**Abordagem prevista.** Estimar a distribuição do atraso entre o início dos sintomas (ou a notificação) e a digitação (`DT_DIGITA`), usando a base do ano corrente, e corrigir as contagens das semanas recentes com intervalos de credibilidade ou confiança. Métodos candidatos:

- modelo bayesiano hierárquico de contagens por semana de ocorrência × atraso, como no InfoGripe/Fiocruz (Bastos et al., 2019);
- função `nowcast()` do pacote R `surveillance` (Meyer, Held & Höhle, 2017).

Esta seção será detalhada (especificação do modelo, priors, janela de estimação, validação retrospectiva) quando a implementação for concluída.

## 9. Software e reprodutibilidade

Todo o processamento é feito em R e publicado com Quarto como site estático no GitHub Pages:

- **R** 4.6.1;
- **pacotes:** dplyr 1.2.1, ggplot2 4.0.3, sf 1.1.3, tmap 4.4.1, readr 2.2.0, foreign 0.8.91, writexl 2.0.1, tidytext 0.4.3, knitr 1.52, kableExtra 1.4.1;
- **Quarto** 1.10.18.

O código e o histórico de alterações estão versionados em git (repositório `valentim1979/virus-respiratorios`). O fluxo completo — anonimização, análise, renderização e publicação — é executado automaticamente quando uma nova exportação do SIVEP-Gripe é disponibilizada.

## 10. Limitações

- **Atraso de notificação:** as semanas recentes estão subestimadas até que o nowcasting seja implementado (seção 8.1).
- **Semanas recentes incompletas:** como as séries usam a semana de início dos sintomas, as semanas mais recentes acumulam casos ainda não internados, notificados ou digitados. O efeito é mais intenso do que com a semana de notificação. O painel alerta o leitor, e o nowcasting (seção 8.1) vai corrigir esse viés.
- **Letalidade entre encerrados:** restringir o denominador aos casos encerrados evita a subestimação pelos casos ainda internados. Em contrapartida, pode superestimar a letalidade no ano corrente se os óbitos forem registrados mais rápido que as altas, e exclui casos com evolução ignorada.
- **Denominador fixo:** as taxas usam a população de 2025 em todos os anos.
- **Canal endêmico frágil:** o canal é baseado em poucos anos de referência (pós-2022), o que torna os percentis instáveis. Ele não é ajustado por tendência nem pelo tamanho da população.
- **Qualidade do preenchimento:** comorbidades, vacinação e uso de antiviral dependem da completitude dos campos (seção 6), e o não preenchimento não equivale à ausência da condição.
- **Casos de residentes fora do estado:** casos de residentes da 15ª RS notificados fora do Paraná podem não constar da exportação estadual. Na base aberta de 2026 isso representou 0,4% dos residentes do PR.

## 11. Referências

- BRASIL. Lei nº 13.709, de 14 de agosto de 2018. Lei Geral de Proteção de Dados Pessoais (LGPD).
- BRASIL. Ministério da Saúde. *Guia de Vigilância em Saúde*. 5. ed. Brasília: SVS, 2022.
- BRASIL. Ministério da Saúde. *Instrutivo de preenchimento da ficha de notificação de SRAG hospitalizado*. Brasília: DEVIT/SVS, 2022.
- BRASIL. Ministério da Saúde. *Guia de manejo e tratamento de influenza 2023*. Brasília: MS, 2023.
- MUTHURI, S. G. et al. Effectiveness of neuraminidase inhibitors in reducing mortality in patients admitted to hospital with influenza A H1N1pdm09 virus infection: a meta-analysis of individual participant data. *The Lancet Respiratory Medicine*, v. 2, n. 5, p. 395–404, 2014.
- BASTOS, L. S. et al. Modelling reporting delays for outbreak detection in infectious disease data. *Journal of the Royal Statistical Society: Series A*, v. 182, n. 2, p. 535–555, 2019.
- MEYER, S.; HELD, L.; HÖHLE, M. Spatio-temporal analysis of epidemic phenomena using the R package surveillance. *Journal of Statistical Software*, v. 77, n. 11, 2017.

---

## Histórico de alterações

| Data | Alteração |
|---|---|
| 03/10/2026 | Antiviral: seção passa a separar influenza confirmada e todos os casos de SRAG e ganha o indicador de oportunidade do tratamento (até 2 dias do início dos sintomas). |
| 03/10/2026 | Séries semanais passam da semana de notificação (`SEM_NOT`) para a de início dos sintomas (`SEM_PRI`). Letalidade passa a usar os casos encerrados como denominador (antes: todos os notificados). O painel ganha um quadro "Como ler este painel" e a página Sobre ganha um resumo da metodologia. |
| 03/10/2026 | Documento criado com a metodologia vigente. Inclusão da base estadual do SIVEP-Gripe (DBF) para o ano corrente, com anonimização por lista de permissão; a página descritiva passa a reutilizar os objetos da análise principal. |
