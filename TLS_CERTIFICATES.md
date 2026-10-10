# Certificados TLS

Ha dois caminhos HTTPS para o Home Assistant, independentes um do outro:

| Caminho | Endereco | Certificado | Para quem |
|---|---|---|---|
| **Tailscale** (add-on do HA, modo `serve`) | `https://homeassistant.tailed34f9.ts.net` | Let's Encrypt emitido e renovado pelo Tailscale (DNS do Tailscale) | dispositivos no tailnet |
| **Publico** (Traefik no cluster) | `https://telheira.tplinkdns.com:8123` | **ZeroSSL** por ACME (resolver `zerossl` no Traefik) | qualquer pessoa na internet (porta 8123 encaminhada no router) |
| **Publico DuckDNS** (Traefik no cluster) | `https://telheira.duckdns.org:8123` | **Let's Encrypt** (resolver `letsencrypt`) | qualquer pessoa na internet (mesmas portas do router) |

## Tailscale HTTPS (ativo desde 2026-10-09)

- Na consola do Tailscale: *DNS > HTTPS Certificates > Enable HTTPS* (o nome da maquina fica nos registos publicos de Certificate Transparency; o tailnet `tailed34f9` e aleatorio e o endereco so funciona dentro do tailnet).
- No add-on Tailscale do HA (`a0d7b954_tailscale`): `share_homeassistant: serve`. O add-on publica `https://homeassistant.tailed34f9.ts.net` e faz proxy para `http://127.0.0.1:8123`.
- O HA tem de confiar no proxy `127.0.0.1`. **No HA 2026.10 a configuracao `http:` vive no armazenamento do HA** (`.storage/http`, slots stable/pending): o bloco `http:` do `configuration.yaml` foi importado uma vez e as alteracoes seguintes no YAML sao ignoradas. O `127.0.0.1/32` foi aplicado pela API WebSocket: `http/config` (ler), `http/config/configure` (config completa; o HA reinicia com a config pendente e reverte sozinho em `revert_at` se nao for confirmada) e `http/config/promote`.
- Sintoma quando falta: o add-on repete `FATAL: Unable to connect to Home Assistant as reverse proxy` e o HA regista `Received X-Forwarded-For header from an untrusted proxy 127.0.0.1`.
- Uso: o microfone do Assist no browser exige HTTPS; com este endereco funciona (no `http://192.168.0.100:8123` o browser bloqueia o microfone).

## Publico: ZeroSSL em vez do Let's Encrypt (configurado em 2026-10-09)

O Traefik (`base/traefik/traefik-config.yaml`) tem dois resolvers ACME por HTTP-01 (entrypoint `web`):
- `letsencrypt`: mantido para rollback (`/data/acme.json`);
- **`zerossl`**: `caserver=https://acme.zerossl.com/v2/DV90`, credenciais EAB do Secret `kube-system/traefik-zerossl-eab` (`EAB_KID`, `EAB_HMAC`; criado a mao, nunca no Git) passadas por env (`$(ZEROSSL_EAB_KID)` / `$(ZEROSSL_EAB_HMAC)` expandidos pelo Kubernetes), armazenamento `/data/acme-zerossl.json`.

As rotas `homeassistant-external`, `media-external` e `plex-external` (`base/ingress-routes.yaml`) usam `certResolver: zerossl`. Para voltar ao Let's Encrypt basta trocar para `letsencrypt`.

A conta ZeroSSL e gratuita; o limite "3 certificados de 90 dias" do site so se aplica aos certificados criados pela interface web, nao aos emitidos por ACME.

`acme.json` vive num PVC (`kube-system/traefik`, `local-path`) desde 2026-10-09, por isso os certificados nao se perdem a cada reinicio do Traefik (antes era `emptyDir`).

Verificar:

```bash
kubectl --context raspi -n kube-system logs deploy/traefik | grep -iE "zerossl|acme" | grep -v "Testing certificate renew"
echo | openssl s_client -connect telheira.tplinkdns.com:8123 -servername telheira.tplinkdns.com 2>/dev/null | openssl x509 -noout -issuer -enddate
```

**Resultado em 2026-10-09:** duas tentativas do ZeroSSL (15:19 e 15:37 UTC) terminaram com `the server didn't respond to our request (status=pending)`: a validacao ficou pendente ate o Traefik desistir. A porta 80 responde a partir da internet (teste de fora de casa: `404` do handler ACME do Traefik), por isso a causa provavel e o mesmo DNS da TP-Link. O resolver `zerossl` fica configurado e o Traefik volta a tentar sozinho (diariamente e a cada reinicio).

**Atualizacao (2026-10-10):** uma das novas tentativas automaticas do ZeroSSL acabou por passar: `telheira.tplinkdns.com` tem certificado ZeroSSL valido ate 2027-01-07. A renovacao pode voltar a falhar pelos mesmos bugs do DNS da TP-Link; o endereco principal continua a ser `telheira.duckdns.org` (Let's Encrypt), o tplinkdns fica como alternativa.

**Decisao (2026-10-09):** manter `telheira.tplinkdns.com` por agora, sem certificado publico valido; o acesso seguro do dia a dia e o do Tailscale. **Tailscale Funnel avaliado e rejeitado** (nao se quer o HA publicado por essa via). Registar outro nome no `tplinkdns` nao resolve: os bugs (ns4/ns5 sensiveis a maiusculas na zona, NXDOMAIN para AAAA) afetam toda a zona `tplinkdns.com`. Quando se quiser HTTPS publico fiavel: **DuckDNS + Let's Encrypt** (add-on oficial DuckDNS no HA ou atualizador no cluster; novo endereco `<nome>.duckdns.org`) ou **Tailscale `funnel`** (sem portas abertas no router). Ambas mudam o endereco externo da app e das notificacoes.

## DuckDNS: telheira.duckdns.org (configurado em 2026-10-09)

- **IP:** CronJob `kube-system/duckdns-updater` (`base/duckdns/`) chama `https://www.duckdns.org/update?domains=telheira&token=...&ip=` a cada 5 minutos (a DuckDNS usa o IP de origem do pedido). O token vive no Secret `kube-system/duckdns` (chave `DUCKDNS_TOKEN`, criado a mao, nunca no Git). O router continua a atualizar o `tplinkdns`.
- **Rotas:** `homeassistant-external-duckdns`, `media-external-duckdns` e `plex-external-duckdns` em `base/ingress-routes.yaml`, copias das rotas `tplinkdns` com `Host(\`telheira.duckdns.org\`)` e `certResolver: letsencrypt`. Sao rotas separadas para o pedido de certificado nao incluir o nome `tplinkdns` (que falharia a validacao e bloquearia o certificado inteiro).
- Mesmas portas encaminhadas no router (80 para o HTTP-01, 443, 8123, 32443).
- Certificado Let's Encrypt emitido a 2026-10-09 (a primeira tentativa falhou porque o DNS ainda tinha o IP antigo; reiniciar o Traefik repetiu o pedido).
- HA: *Settings > System > Network > Internet* = `https://telheira.duckdns.org:8123` (sem a porta, o 443 vai para o qBittorrent e a app/notificacoes falham fora de casa).

Verificar:

```bash
kubectl --context raspi -n kube-system create job duckdns-manual --from=cronjob/duckdns-updater
kubectl --context raspi -n kube-system logs job/duckdns-manual   # duckdns: OK
dig +short telheira.duckdns.org
echo | openssl s_client -connect telheira.duckdns.org:8123 -servername telheira.duckdns.org 2>/dev/null | openssl x509 -noout -issuer -enddate
```

## Historico: porque o Let's Encrypt deixou de funcionar

O certificado Let's Encrypt expirou a 2026-09-27 e as renovacoes falhavam com `DNS problem: NXDOMAIN looking up A for telheira.tplinkdns.com` (e o mesmo para AAAA), apesar de o nome resolver normalmente. O problema nao e o Let's Encrypt (o Tailscale tambem o usa), sao os servidores DNS da TP-Link. Consultas diretas aos servidores autoritativos (`dig +norec @nsX.tplinkdns.com`):

| Consulta | ns1 | ns2 | ns4 | ns5 |
|---|---|---|---|---|
| `telheira.tplinkdns.com` A | NOERROR | NOERROR | NOERROR | NOERROR |
| `TELHEIRA.TPLINKDNS.COM` A | NOERROR | NOERROR | **NXDOMAIN** | **NXDOMAIN** |
| `telheira.TpLiNkDnS.cOm` A | NOERROR | NOERROR | **NXDOMAIN** | **NXDOMAIN** |
| `telheira.tplinkdns.com` AAAA | **NXDOMAIN** | **NXDOMAIN** | **NXDOMAIN** | **NXDOMAIN** |

1. **ns4/ns5 sao sensiveis a maiusculas** na parte da zona, contra a norma DNS. O resolver do Let's Encrypt usa aleatorizacao de maiusculas ("0x20") por seguranca, por isso cerca de metade das consultas recebe NXDOMAIN.
2. **AAAA devolve NXDOMAIN** em vez de NOERROR sem dados. Resolvers que aplicam RFC 8020 tratam isso como "o nome nao existe" tambem para A.
3. O Let's Encrypt valida a partir de varios pontos (multi-perspective validation) e exige que quase todos tenham sucesso.

A rota `plex-subdomain` (`plex.telheira.tplinkdns.com`) foi removida: o DDNS da TP-Link nao suporta subdominios.

Repetir o diagnostico:

```bash
for n in telheira.tplinkdns.com TELHEIRA.TPLINKDNS.COM; do
  for ns in ns1 ns2 ns4 ns5; do
    printf "%-24s @%s: " $n $ns
    dig +norec +time=3 +tries=1 @$ns.tplinkdns.com $n A | grep -oE "status: [A-Z]+"
  done
done
```

Pendente: reportar o bug a TP-Link (ns4/ns5 sensiveis a maiusculas; AAAA com NXDOMAIN).
