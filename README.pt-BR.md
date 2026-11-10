# finite-rule-provenance

[![CI](https://github.com/martinlofranodeoliveira/finite-rule-provenance/actions/workflows/ci.yml/badge.svg)](https://github.com/martinlofranodeoliveira/finite-rule-provenance/actions/workflows/ci.yml)
[![Licença: MIT](https://img.shields.io/badge/Licen%C3%A7a-MIT-blue.svg)](LICENSE)
[![Racket](https://img.shields.io/badge/Racket-8.7-blue.svg)](https://racket-lang.org/)

Motor limitado de Datalog estratificado em Racket que calcula pontos fixos relacionais finitos e registra proveniência determinística de derivação com evidências explícitas de ausência em estratos inferiores.

Disponível também em [Inglês](README.md).

## Funcionalidades

- **Avaliação Estratificada**: Analisa grafos de dependência sinalizados e calcula estratos ótimos, rejeitando ciclos negativos como `INVALID_PROGRAM`.
- **Avaliação Semi-Ingênua Indexada**: Minimiza junções redundantes entre rodadas recursivas de ponto fixo utilizando diferenciais $\Delta$.
- **Proveniência Determinística de Prova Única**: Registra exatamente uma derivação imutável por fato derivado com ordinais de premissas estritamente anteriores.
- **Evidência Explícita de Ausência**: Literais negativos em corpos de regras registram testemunhos formais de ausência em estratos inferiores já fechados.
- **Reprodutor Independente de Provas**: Reavalia derivações passo a passo, verificando unificações de variáveis e detectando adulterações de premissas.
- **Oráculo Relacional Isolado (SQLite)**: Valida pontos fixos de forma independente via junções relacionais e cláusulas `NOT EXISTS` em SQLite com nomes de tabelas sintéticos (`rel_0`).
- **Limites Rígidos de Recursos**: Impõe limites para predicados ($\le 16$), constantes ($\le 32$), fatos de entrada ($\le 4096$), regras ($\le 64$), fatos materializados ($\le 32768$) e passos de unificação ($\le 2000000$), retornando `UNKNOWN_BUDGET` em caso de estouro de limites.
- **Zero Dependências Externas**: Implementado integralmente com componentes da biblioteca padrão do Racket (`racket/base`, `json`, `db`, `rackunit`).

## Guia Rápido

### Executar Testes e Afirmações Offline

```bash
# Executar suíte de testes unitários com raco test
./scripts/test-offline.sh

# Executar afirmações analíticas através do executável CLI
./scripts/demo-offline.sh --assert

# Executar demonstração com saída formatada em JSON
./scripts/demo-offline.sh --json
```

### Interface de Linha de Comando (CLI)

```bash
# Avaliar arquivo Datalog em JSON
./dist/finite-rule-provenance eval program.json --json

# Reexaminar e verificar provas de derivação independentemente
./dist/finite-rule-provenance replay program.json

# Validação cruzada com o motor relacional SQLite
./dist/finite-rule-provenance oracle program.json
```

## Uso Programático

```racket
#lang racket/base

(require finite-rule-provenance)

(define prog
  (program
   (list
    (rule 'r_step
          (literal 'path (list (var-term 'X) (var-term 'Y)) #t)
          (list (literal 'edge (list (var-term 'X) (var-term 'Y)) #t)))
    (rule 'r_trans
          (literal 'path (list (var-term 'X) (var-term 'Z)) #t)
          (list (literal 'path (list (var-term 'X) (var-term 'Y)) #t)
                (literal 'edge (list (var-term 'Y) (var-term 'Z)) #t))))
   (list
    (fact 'edge #(a b))
    (fact 'edge #(b c)))))

(define res (run-program-rehearsal prog #:oracle? #t))

(printf "Status: ~a\n" (evaluation-result-status res))
(printf "Total de fatos derivados: ~a\n" (length (evaluation-result-facts res)))
```

## Documentação

- [Contrato e Limites de Recursos](docs/contract.md)
- [Design Arquitetural](docs/design.md)
- [Visão de Produto](PRODUCT.md)

## Licença

Este projeto é distribuído sob a [Licença MIT](LICENSE) © 2026 Lofrano Tecnologia.
