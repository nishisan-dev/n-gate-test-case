# Evolução do ishin-gateway-test-case: Dashboard + Zipkin VM

Adicionar uma VM dedicada para Zipkin no laboratório Vagrant e habilitar o Dashboard de observabilidade como default em ambos os nós ishin-gateway, com exportação de traces apontando para a VM Zipkin.

## Contexto Técnico

O `TracerService` do ishin-gateway resolve o endpoint Zipkin com a seguinte precedência:
1. Env var `ZIPKIN_ENDPOINT`
2. System property `zipkin.endpoint`
3. Default: `http://zipkin:9411/api/v2/spans`

O `DashboardService` lê `dashboard.zipkin.baseUrl` da `DashboardConfiguration` para o **proxy de consulta** (UI → Zipkin API). São dois mecanismos independentes:
- **TracerService**: envia spans para coleta (Brave → Zipkin)
- **DashboardService**: consulta traces para exibição na UI (proxy reverso)

---

## Proposed Changes

### Infraestrutura Vagrant

#### [MODIFY] [Vagrantfile](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/Vagrantfile)

Adicionar VM `zipkin-1`:
- **IP**: `192.168.56.31` (faixa .3x para serviços de observabilidade)
- **Porta guest**: `9411` (Zipkin HTTP)
- **Port forwarding**: `39411 → 9411`
- **Memória**: `1024 MB`
- **CPUs**: `2`
- **Provisioner**: `scripts/install_zipkin.sh`

Adicionar port forwarding para Dashboard nos nós ishin-gateway:
- `ishin-1`: `19200 → 9200`
- `ishin-2`: `29200 → 9200`

---

#### [NEW] [install_zipkin.sh](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/scripts/install_zipkin.sh)

Script de provisioning para Zipkin:
- Instalar OpenJDK 25 JRE (headless)
- Baixar o JAR do `openzipkin/zipkin` (release latest estável)
- Criar systemd unit `zipkin.service`
- Configurar para escutar em `0.0.0.0:9411`
- Iniciar e habilitar o serviço

---

#### [MODIFY] [common.sh](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/scripts/common.sh)

Adicionar entry para a nova VM no mapeamento de hosts:
```
192.168.56.31 zipkin-1
```

---

### Configuração do ishin-gateway

#### [MODIFY] [install_ishin.sh](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/scripts/install_ishin.sh)

1. Adicionar bloco `dashboard:` habilitado no `adapter.yaml` gerado:

```yaml
dashboard:
  enabled: true
  port: 9200
  bindAddress: "0.0.0.0"
  allowedIps:
    - "127.0.0.1"
    - "::1"
    - "10.0.0.0/8"
    - "192.168.0.0/16"
  storage:
    path: "/var/lib/ishin-gateway"
    retentionHours: 24
    scrapeIntervalSeconds: 15
  zipkin:
    enabled: true
    baseUrl: "http://zipkin-1:9411"
```

2. Adicionar env var `ZIPKIN_ENDPOINT` no systemd override para o `TracerService`:

```ini
Environment=ZIPKIN_ENDPOINT=http://zipkin-1:9411/api/v2/spans
```

3. Adicionar `ReadWritePaths=/var/lib/ishin-gateway` e criar o diretório no provisionamento.

---

### Documentação

#### [MODIFY] [README.md](file:///home/lucas/Projects/ishin-gateway/ishin-gateway-test-case/README.md)

- Atualizar tabela de máquinas e rede com `zipkin-1` e portas do dashboard
- Adicionar seção sobre observabilidade
- Atualizar versão do ishin-gateway na descrição
- Adicionar comandos de teste para dashboard e Zipkin

---

## Verification Plan

### Manual Verification

> [!IMPORTANT]  
> Como o Vagrantfile depende de VMs Vagrant/VirtualBox, a verificação é manual.

1. **Validar sintaxe do Vagrantfile**:
   ```bash
   cd ishin-gateway-test-case && vagrant validate
   ```

2. **Subir ambiente completo** (ordem importa):
   ```bash
   vagrant up web-1
   vagrant up zipkin-1
   vagrant up ishin-1
   vagrant up ishin-2
   ```

3. **Verificar Zipkin**:
   ```bash
   curl http://localhost:39411/health    # deve retornar UP
   curl http://localhost:39411/          # UI do Zipkin
   ```

4. **Verificar Dashboard nos nós ishin-gateway**:
   ```bash
   curl http://localhost:19200/api/dashboard/health   # ishin-1
   curl http://localhost:29200/api/dashboard/health   # ishin-2
   ```

5. **Gerar traces e validar**:
   ```bash
   # Gerar tráfego
   curl http://localhost:19090
   curl http://localhost:29090
   
   # Verificar traces no Zipkin (após ~5s)
   curl "http://localhost:39411/api/v2/traces?serviceName=ishin-gateway&limit=5"
   ```

6. **Verificar proxy Zipkin via Dashboard**:
   ```bash
   curl http://localhost:19200/api/dashboard/traces
   ```
