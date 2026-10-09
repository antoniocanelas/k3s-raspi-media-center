# Certificados TLS externos (telheira.tplinkdns.com)

O Traefik (`base/traefik/traefik-config.yaml`) obtem certificados Let's Encrypt por HTTP-01 (entrypoint `web`) para `telheira.tplinkdns.com`, usado no acesso externo ao Home Assistant (`:8123`, IngressRoute `homeassistant-external`) e nas rotas `media-external` / `plex-external`.

## Estado em 2026-10-09

- O certificado Let's Encrypt expirou a 2026-09-27. Desde entao o Traefik serve o `TRAEFIK DEFAULT CERT` e o browser recusa a ligacao.
- Corrigido nesse dia: `acme.json` passou a viver num PVC (`kube-system/traefik`, `local-path`) em vez de `emptyDir`, por isso os certificados ja nao se perdem a cada reinicio do Traefik. A rota `plex-subdomain` (`plex.telheira.tplinkdns.com`) foi removida: o DDNS da TP-Link nao suporta subdominios, o nome da sempre NXDOMAIN e so gerava pedidos ACME falhados.
- **Ainda sem certificado valido**: a renovacao continua a falhar por causa de bugs nos servidores DNS da TP-Link (abaixo).

Enquanto nao houver certificado, o HA fica acessivel remotamente pelo Tailscale: `http://100.116.252.87:8123` ou `http://192.168.0.100:8123` (rota de subnet `192.168.0.0/24` anunciada pelo `pi-master-00`).

## Diagnostico: bugs no DNS da TP-Link

O Let's Encrypt responde `DNS problem: NXDOMAIN looking up A for telheira.tplinkdns.com` (e o mesmo para AAAA), apesar de o nome resolver normalmente. Consultas diretas aos servidores autoritativos (`dig +norec @nsX.tplinkdns.com`):

| Consulta | ns1 | ns2 | ns4 | ns5 |
|---|---|---|---|---|
| `telheira.tplinkdns.com` A | NOERROR | NOERROR | NOERROR | NOERROR |
| `TELHEIRA.TPLINKDNS.COM` A | NOERROR | NOERROR | **NXDOMAIN** | **NXDOMAIN** |
| `telheira.TpLiNkDnS.cOm` A | NOERROR | NOERROR | **NXDOMAIN** | **NXDOMAIN** |
| `telheira.tplinkdns.com` AAAA | **NXDOMAIN** | **NXDOMAIN** | **NXDOMAIN** | **NXDOMAIN** |

1. **ns4/ns5 sao sensiveis a maiusculas** na parte da zona, contra a norma DNS. O resolver do Let's Encrypt usa aleatorizacao de maiusculas ("0x20") por seguranca, por isso cerca de metade das consultas recebe NXDOMAIN.
2. **AAAA devolve NXDOMAIN** em vez de NOERROR sem dados. Resolvers que aplicam RFC 8020 tratam isso como "o nome nao existe" tambem para A.
3. O Let's Encrypt valida a partir de varios pontos (multi-perspective validation) e exige que quase todos tenham sucesso, o que torna uma emissao muito improvavel. Funcionou no passado; agora falha quase sempre.

Para repetir o diagnostico:

```bash
for n in telheira.tplinkdns.com TELHEIRA.TPLINKDNS.COM; do
  for ns in ns1 ns2 ns4 ns5; do
    printf "%-24s @%s: " $n $ns
    dig +norec +time=3 +tries=1 @$ns.tplinkdns.com $n A | grep -oE "status: [A-Z]+"
  done
done
kubectl --context raspi -n kube-system logs deploy/traefik | grep -i "Unable to obtain"
echo | openssl s_client -connect telheira.tplinkdns.com:8123 -servername telheira.tplinkdns.com 2>/dev/null | openssl x509 -noout -enddate -issuer
```

## Tarefa futura: obter um certificado valido mantendo telheira.tplinkdns.com

- [ ] **Trocar o Let's Encrypt pelo ZeroSSL (recomendado).** Gratuito, mesmo protocolo ACME, suportado diretamente pelo Traefik (`--certificatesresolvers.<nome>.acme.caserver=https://acme.zerossl.com/v2/DV90` com `acme.eab.kid` / `acme.eab.hmacencoded`). O validador deles costuma tolerar melhor estes problemas de DNS, mas so testando se confirma. Precisa de credenciais EAB, obtidas de uma de duas formas:
  - a) criar uma conta gratis em zerossl.com, em *Developer -> EAB Credentials* gerar as credenciais e guarda-las num Secret em `kube-system` (criado a mao, nunca no Git), referenciado no HelmChartConfig;
  - b) pedi-las pela API do ZeroSSL (`POST https://api.zerossl.com/acme/eab-credentials-email` com o email), o que envia o email da conta ao ZeroSSL; so com autorizacao explicita.
- [ ] **Continuar a tentar com o Let's Encrypt.** O Traefik volta a tentar sozinho (verificacao diaria e a cada reinicio). Pode passar por sorte, mas nao e fiavel e o certificado volta a expirar ao fim de 90 dias.
- [ ] **Reportar o bug a TP-Link** (ns4/ns5 sensiveis a maiusculas; AAAA com NXDOMAIN). Vale a pena, mas nao resolve no curto prazo.

Atencao ao limite do Let's Encrypt de 5 validacoes falhadas por hostname por hora: evitar reiniciar o Traefik repetidamente so para forcar tentativas.
