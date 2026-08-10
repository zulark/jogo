# Squad Manager — Documento de Design

## Conceito Central

Um gerenciador de squads de mercenários ("operators") para missões. O jogador contrata, treina, equipa e envia operadores em missões, gerenciando risco, economia e o desenvolvimento de longo prazo de cada membro do roster.

---

## 1. Operadores

- Cada operador tem **personalidade e skills próprias**.
- O jogador contrata operadores, monta squads (definindo **líder** e **papéis**), e os envia em missões de acordo com o tipo de missão.
- **Resolução de missão**: uma probabilidade de sucesso é calculada com base em:
  - Skills individuais
  - Personalidade
  - Composição do squad como um todo
  - Posição/papel de cada membro
  - Risco da missão
- **Resultados possíveis por operador**:
  - Retorna normalmente, ganhando experiência nas skills e/ou um novo trait
  - Fica indisponível por um tempo (ferido, traumatizado, etc.)
  - Morre definitivamente (perma-morte)

### Salário e Custo

- Cada operador recebe um **salário**, descontado do "**diamante**" do jogador (moeda do jogo).
- Diamante é ganho primariamente em missões.

### Treinamento

- Um operador **novato** pode ser treinado por um operador **mais velho**, escolhido pelo jogador.
- O treinado pode ganhar **traits e/ou skills** baseados no treinador.
- Ambos (treinador e treinado) ficam **indisponíveis para missões** durante o treinamento.

### Vínculos Emocionais

- Operadores podem desenvolver links emocionais entre si, positivos ou negativos:
  - **Rivalidade**
  - **Amizade**
  - **Romance** (probabilidade **muito baixa**, para evitar excesso de casais no roster)

### Traits Negativos

- Nem toda skill/trait ganha precisa ser positiva: trauma, medo de um tipo específico de missão, rivalidade com outro operador, etc.
- Cria histórias emergentes e dá peso a decisões de squad.

### Progressão de Patente

- Trilha de campo: **Soldado → Cabo → 3º Sargento → 2º Sargento → 1º Sargento → Subtenente**
- A partir de **Subtenente**, o operador pode:
  - Continuar atuando em campo, ou
  - Se tornar **treinador**
- Trilha de treinador: **Subtenente → ... → Coronel** (patente máxima)
- XP dos operadores é representado através das patentes.

### Cemitério

- Espaço dedicado aos operadores mais famosos que morreram em serviço, preservando sua história (missões, patente alcançada, operadores que treinou, etc.)

---

## 2. Missões

- **Regiões de missão** possuem especificidades próprias (modificadores de risco, contexto, etc.)
- **Especializações táticas por tipo de missão**: cada tipo de missão pode dar bônus/penalidade conforme a composição do squad (ex: missão de infiltração pune squad grande; missão de resgate exige um "medic role").

---

## 3. Facilities (Base)

Áreas utilizáveis, upáveis para melhorar buffs e itens disponíveis:

| Facility | Função |
|---|---|
| **Enfermaria** | Recuperação de operadores feridos |
| **Psicólogo** | Reduz a chance/intensidade e acelera a recuperação de traits negativos — **não remove o trait**, que continua fazendo parte da identidade do operador |
| **Cantina** | Buffs de moral |
| **Academia** | Suporte ao sistema de treinamento |
| **Central de Inteligência** | Concede bônus em missões por meio de "scouting" de locais/alvos antes do envio do squad |
| **Armazém** | Armazenamento geral de itens/recursos |
| **Armeiro** | Fornece armas com base no nível da facility; permite reparo de itens e crafting a partir de blueprints obtidas como loot |
| **Roupeiro** | Fornece equipamentos/vestimentas com base no nível da facility; mesmas funções de reparo/crafting via blueprint |

---

## 4. Economia

### Moeda

- **Diamante**: moeda principal, ganha em missões, gasta em salários, facilities, equipamentos e manutenção.

### Lojas

- **Armeiro / Roupeiro**: fornecem itens com base no **nível da facility**; oferecem reparo de itens e crafting (via blueprints obtidas como loot).
- **Blackmarket**: **A** loja de itens especiais e mais caros — fornece itens com base na **reputação da companhia**.

### Gastos Fixos

- **Munição, comida, remédios** e afins são gastos recorrentes fixos, geridos como uma planilha de orçamento (comparável ao gerenciamento de custos de Cities: Skylines / SimCity).

### Moral e Fadiga

- Usar o mesmo squad em missões consecutivas sem descanso **aumenta o risco de falha**.
- Evita "squad meta" degenerado e força rotação — o que, por sua vez, força o uso de operadores novatos.

### Reputação

- Sistema de reputação com facções/clientes: cada contratante pode ter preferências (ex: só aceita squads discretos).
- A reputação afeta **preço** e **disponibilidade** de missões futuras, além do acesso a itens do blackmarket.

### Fontes de renda adicionais (idle/passivas)

- **Contratos de retenção (retainer)**: clientes/facções pagam um valor fixo periódico por prioridade/exclusividade do squad, mesmo sem missão ativa no ciclo — em troca, o jogador fica de prontidão (ou paga multa se recusar uma convocação).
- **Produção passiva do Armeiro/Roupeiro**: uma vez upadas, essas facilities podem gerar itens extras por ciclo, vendáveis no blackmarket como renda residual.
- **Missões de baixo risco auto-resolvidas**: operadores fora do squad principal podem ser enviados em missões simples resolvidas automaticamente com base no nível deles — baixo retorno, mas dá utilidade a operadores ociosos.

---

## 5. Sistema de Eventos Inesperados

- **Eventos negativos**: ex. um traidor vende informações da base, causando perda de diamante, itens ou outros recursos.
- **Eventos positivos**: ex. surgimento de um recruta prodígio, achado de loot extra, entre outros.
- Ideia de evolução: vincular a chance/severidade dos eventos a fatores existentes (moral do squad/operador, trait de rancor, nível de investimento na Central de Inteligência), tornando os eventos consequência de decisões do jogador e não puro acaso.

---

## Notas de Priorização (MVP → Expansão)

1. **Núcleo jogável**: contratar operador → montar squad → mandar em missão → resultado → salário/diamante → treinamento básico
2. **Camada de profundidade**: patentes, traits (positivos e negativos), vínculos emocionais, moral/fadiga
3. **Camada econômica**: gastos fixos, armeiro/roupeiro, blackmarket, upgrades de facility, fontes de renda passiva
4. **Camada de mundo**: regiões com especificidades, reputação de facções, central de inteligência, eventos inesperados