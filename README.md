# 🛍️ Sistema Automatizado de Compilacao e Testes do MONAN-bundle (MONAN+JEDI)

Este repositório contém uma estrutura padronizada e automatizada para compilar e testar o sistema **MONAN-JEDI** nas maquinas o **INPE**, utilizando o Spack-Stack 1.7.0 e os sistema de filas.

---

## Estrutura do Repositório

```bash
.
├── build_and_test.sh              # Script principal (ponto de entrada)
├── docs/                          # Documentação adicional
│   ├── build_modes.md             # Modos de build suportados
│   └── LICENSE.md                 # Detalhes da licença
├── jobs/                          # Jobs SLURM para compilação e testes
│   ├── build_job.slurm            # Submissão do build MONAN-JEDI
│   └── ctest_job.slurm            # Submissão do CTest
├── lib/                           # Scripts auxiliares
│   ├── build_local.sh             # Compilação local leve
│   ├── generate_html_index.sh     # Geração de índice HTML de logs
│   ├── monitor_slurm_job.sh       # Monitoramento de jobs SLURM (opcional)
│   └── submit_jobs.sh             # Enfileiramento de build e test
├── sync_cmakelists.sh             # Sincroniza CMakeLists do mpas-bundle
├── README.md                      # Este documento
├── LICENSE                        # Licença do projeto (LGPL-v3)
└── cmake_versions/                # Armazena os CMakeLists.txt modificados por versão
                                   #   Ex: CMakeLists_3.0.0.txt, CMakeLists_3.0.1.txt
```

---

## Como Usar

Execute **somente** o script principal:

```bash
/bin/bash ./build_and_test.sh [-v <VERSION>] [-m <MODE>] [-p <ON|OFF>] [-h]
```

**Argumentos**

- `-v <VERSAO>` (opcional): Define a tag ou branch da release do `mpas-bundle` a ser utilizada.  
  **Padrão:** `3.0.2`

- `-m <MODO>` (opcional): Modo de execução. Use `local` para rodar no nó de login ou `slurm` para submeter via SLURM.  
  **Padrão:** `local`

- `-p <PRECISAO>` (opcional): Define a precisão numérica da compilação. Use `ON` para precisão dupla ou `OFF` para precisão simples.  
  **Padrão:** `ON`

- `-h`: Exibe esta ajuda e encerra a execução.

---

**Exemplos de uso**

- **Compilar a versão 3.0.1 utilizando SLURM:**
  ```bash
  ./build_and_test.sh -v 3.0.1 -m slurm
  ```

- **Compilar localmente com precisão simples (debug):**
  ```bash
  ./build_and_test.sh -p OFF
  ```

Este script irá:

1. Verificar se o arquivo `CMakeLists_<versao>.txt` está disponível na pasta `cmake_versions`
2. Criar um diretório de build com base na versão e data atual
3. Copiar o `CMakeLists_<versao>.txt` correspondente para o diretório de build
4. Ativar o ambiente Spack configurado no Egeon
5. Executar o `cmake` para configurar os pacotes
6. Submeter automaticamente os jobs de compilação e testes via SLURM

---

## Pré-Requisitos

- Ter o ambiente Spack-Stack 1.7.0 configurado em:
  ```
  <PATH>/mpas-bundle/start_spack_stack.sh
  ```

- Módulos recomendados para carregar antes de iniciar:
  ```bash
  module load gnu9
  ```

---

## Organização dos Logs

Os logs são organizados automaticamente por **data** e **tipo**, e armazenados em:

```bash
$BUILD_DIR/logs/YYYY-MM-DD/
```

Também são copiados para um diretório compartilhado:

```bash
/mnt/beegfs/$USER/relatorios/mpas-jedi/{build,ctest}/YYYY-MM-DD/
```

---

## Monitoramento e Relatórios

- Use `monitor_slurm_job.sh` para acompanhar jobs em tempo real:

  ```bash
  ./lib/monitor_slurm_job.sh <JOBID>
  ```

- Gere um índice HTML com os logs por data:

  ```bash
  ./lib/generate_html_index.sh
  ```

  O índice será salvo em:

  ```
  /mnt/beegfs/$USER/relatorios/mpas-jedi/index.html
  ```

---

## Sobre o sync_cmakelists.sh

O script `sync_cmakelists.sh` automatiza a coleta dos arquivos `CMakeLists.txt` das releases do repositório `mpas-bundle`, aplicando:

- Substituição de `ecbuild_bundle(PROJECT ...)` por `ecbuild_add_bundle_ext(...)`
- Remoção dos argumentos `UPDATE` e `NOREMOTE`
- Inserção da macro `ecbuild_add_bundle_ext` com suporte a `MPAS_BUNDLE_NOREMOTE`

Arquivos modificados ficam salvos em:
```bash
cmake_versions/CMakeLists_<versao>.txt
```

---

### Modos de Compilação

> **Importante:** o MPAS-JEDI **só compila** no nó `egeon-login.cptec.inpe.br`. Executar qualquer script de build no *headnode* não é suportado e resulta em falhas ou degradação severa de desempenho.

Este sistema oferece suporte a dois modos de compilação do MPAS-JEDI:

- `slurm`: Submete a compilação como job SLURM, ideal para builds pesados.
- `local`: Executa a compilação diretamente no nó de login, com limitação automática de recursos (uso máximo de 10% da CPU e prioridade reduzida).

> **Documentação completa**: veja [docs/build_modes.md](docs/build_modes.md)

Para ativar o modo desejado, utilize o script `submit_jobs.sh` com o último argumento como `slurm` ou `local`.

Exemplos:

```bash
./submit_jobs.sh . build-3.0.2 /mnt/beegfs/das.group/spack-envs/mpas-bundle gnu ON slurm
./submit_jobs.sh . build-3.0.2 /mnt/beegfs/das.group/spack-envs/mpas-bundle gnu ON local
```

---

## Licença

Este projeto é licenciado sob os termos da **LGPL v3.0**.  
Consulte o arquivo [LICENSE](./docs/LICENSE.md) para mais detalhes.

---

## Ambiente Compartilhado

Para evitar instalações duplicadas entre usuários do grupo, utilize o ambiente compartilhado:

```bash
source /mnt/beegfs/das.group/spack-envs/mpas-bundle/start_spack_bundle.sh
```

Esse script garante a ativação completa do ambiente com módulos e variáveis necessárias para compilar e rodar o MPAS-JEDI.

---

## Contato

Para dúvidas ou contribuições, entre em contato com **João Gerd**  
Instituto Nacional de Pesquisas Espaciais (INPE)  
📧 joao.gerd [at] inpe.br  
➡️ ou abra uma [issue]([https://github.com/joaogerd/mpas-jedi-egeon](https://github.com/GAD-DIMNT-CPTEC/MONAN-bundle)/issues) neste repositório.


