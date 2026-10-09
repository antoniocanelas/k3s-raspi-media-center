# Certificados TLS

Ha dois caminhos HTTPS para o Home Assistant, independentes um do outro:

| Caminho | Endereco | Certificado | Para quem |
|---|---|---|---|
| **Tailscale** (add-on do HA, modo `serve`) | `https://homeassistant.tailed34f9.ts.net` | Let's Encrypt emitido e renovado pelo Tailscale (DNS do Tailscale) | dispositivos no tailnet |
| **Publico** (Traefik no cluster) | `https://telheira.tplinkdns.com:8123` | **ZeroSSL** por ACME (resolver `zerossl` no Traefik) | qualquer pessoa na internet (porta 8123 encaminhada no router) |

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

**Por confirmar:** a primeira emissao pelo ZeroSSL (o validador do ZeroSSL tambem consulta o DNS da TP-Link). Se falhar pelos mesmos motivos, as alternativas sao trocar de DNS dinamico (DuckDNS, gratis, com Let's Encrypt) ou publicar o HA com o modo `funnel` do Tailscale (sem portas abertas no router).

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
