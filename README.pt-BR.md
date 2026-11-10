# Finite Rule Provenance

Versão de desenvolvimento 0.1.0: biblioteca offline de Datalog estratificado limitado, com uma derivação por fato e evidência de ausência em estrato inferior. Adoção é hipótese, sem alegação de usuários, certificação ou prontidão de produção. [English](README.md).

A API exporta `program`, `rule`, `literal`, `var-term`, `const-term`, `fact`, `evaluate-datalog`, `run-program-rehearsal` e os acessores de `evaluation-result`. A avaliação semi-ingênua original usa conjuntos relacionais e rodadas diferenciais. Não oferece Prolog geral, agregações, aritmética, termos funcionais, persistência, atualização incremental ou predicados externos. Não é um motor de decisões de autorização, jurídicas, médicas ou financeiras.

## Compilar e instalar

Plataforma nativa qualificada: Linux x86-64, Racket 8.7 CS (Debian `8.7+dfsg1-1`) e SQLite `3.40.1-2+deb12u2`. `json`, `db`, ferramentas de pacote e RackUnit mantidos pelo Racket preservam suas funções. `qualification/` contém os checksums reais de pacotes e artefatos Debian; não existe um lockfile Racket inventado. As etapas offline não baixam dependências.

```sh
docker build --target sdk -t finite-rule-sdk .
docker run --rm --network none --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges --pids-limit 256 --memory 1g --cpus 2 finite-rule-sdk /bin/sh scripts/package-gate.sh
docker build -t finite-rule-provenance .
docker run --rm --network none --user 1000:1000 --cap-drop ALL --security-opt no-new-privileges --pids-limit 256 --memory 1g --cpus 2 finite-rule-provenance demo --assert --json
```

O Dockerfile separa preparação oficial, SDK offline e distribuição executável. A imagem final não inclui compilador Racket, checkout ou resolvedor de pacotes. Em instalação nativa preparada, use `/bin/sh scripts/test-offline.sh`, `/bin/sh scripts/build-offline.sh` e `/bin/sh scripts/demo-offline.sh --assert`. O demo não compila durante sua execução.

Crie o arquivo real com `raco pkg create --source --format zip --dest /seus/artefatos /seu/checkout`. Instale sob HOME explícito com `raco pkg install --scope user --deps fail --batch --no-setup --name finite-rule-provenance /seus/artefatos/checkout.zip`; a distribuição preparada já deve fornecer todas as dependências. O gate verifica os bytes exatos do arquivo, instala em escopo novo e usa um consumidor fora do checkout. Arquivos de controle de versão/workflow são excluídos pelo empacotador e declarados fora do inventário do pacote.

## CLI e API

A atualização de desenvolvimento lê JSON **somente de stdin**; o argumento anterior de caminho foi removido. Redirecionamento é responsabilidade do chamador; o programa não abre caminhos arbitrários.

```sh
printf '%s' '{"edb_facts":[{"predicate":"ready","args":[]}],"rules":[]}' | ./dist/distribution/bin/finite-rule-provenance eval --json
./dist/distribution/bin/finite-rule-provenance replay < examples/program.json
./dist/distribution/bin/finite-rule-provenance oracle < examples/program.json
./dist/distribution/bin/finite-rule-provenance demo --json
```

O exemplo `examples/program.json` está incluído. `eval` calcula; `replay` recalcula e verifica a própria prova; `oracle` também compara com SQLite e exige no máximo oito constantes. Não lê recibos de prova externos. O demo verifica o mesmo exemplo sintético original de oito fatos em texto, `--assert`, `--json` ou ambos. `--help` mostra o uso. Argumentos desconhecidos, repetidos ou deslocados são inválidos.

```racket
#lang racket/base
(require finite-rule-provenance)
(define resultado (evaluate-datalog (program null (list (fact 'ready #())))))
(displayln (evaluation-result-status resultado)) ; COMPLETE
(displayln (evaluation-result->json-string resultado))
```

Estados: `COMPLETE`, `UNKNOWN_BUDGET`, `INVALID_PROGRAM`, `INCOMPLETE`; saídas CLI respectivas 0, 1, 2, 3. Erros de uso/entrada saem 2. Falhas de verificação, cálculo e I/O são incompletas, não negativas matemáticas. Erro de oráculo ou timeout nunca conta como rejeição comprovada. Os wrappers incompletos não expõem fatos/provas parciais. A função de baixo nível `evaluate-program` mantém seu contrato de exceções; normalmente use `evaluate-datalog`.

JSON de saída tem um valor UTF-8, newline e código de saída correspondente. Exija quadro inteiro e código correto: stdout não é atômico e pode truncar em falha. O leitor JSON mantido usa o último membro em chaves duplicadas; propriedades desconhecidas são rejeitadas. Constantes JSON são strings ou inteiros exatos; nomes não vazios; termos têm exatamente `var` ou `const`; IDs de regra são únicos e `edb` é reservado.

## Limites e limitações

Até 16 predicados de aridade 0..3, 32 constantes, 4096 fatos de entrada, 64 regras e seis variáveis/literais por regra. Variáveis do cabeçalho/negação precisam ocorrer positivamente; ciclos negativos são inválidos. Tetos: 32768 fatos, 131072 arestas positivas de prova, 2000000 exames candidatos, 262144 bytes UTF-8 de entrada e 8388608 bytes de saída completa, incluindo newline. API/encoder aceitam orçamento menor de saída entre 512 e 8388608. Falta de orçamento não prova vazio nem publica relação parcial.

Contadores lógicos não limitam alocações do parser, VM, objetos JSON, conversão de strings, SQLite nativo, RSS ou tempo de execução. O destino de bytes confere antes de acrescentar, mas representações internas podem alocar antes. Streams herdados bloqueados são incompletos sob o proprietário externo do contêiner. Exige filesystem Linux local cooperativo, checkout estável e acesso não concorrente a AST/recibos; não promete snapshot hostil nem sandbox profundo de objetos. A aplicação não usa sinais por PID/PGID, subprocessos, rede, telemetria, credenciais ou APIs externas.

Consulte [contrato](docs/contract.md), [design](docs/design.md) e [avisos de terceiros](THIRD_PARTY_NOTICES.md). Código original [MIT](LICENSE), © 2026 Lofrano Tecnologia; dependências preservam suas licenças. Site oficial: https://lofranotecnologia.com.br.
