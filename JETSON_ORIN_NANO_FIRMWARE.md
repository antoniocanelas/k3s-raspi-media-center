# Waveshare Jetson Orin Nano 8 GB: etapa 1 - firmware

Este passo a passo é para o kit do anúncio da [BotnRoll](https://www.botnroll.com/pt/jetson/5866-jetson-orin-nano-8gb-kit-inclui-128gb-nvme-ssd-m-dulo-wifi-e-fonte-de-alimenta-o.html). O anúncio identifica um kit Waveshare com módulo Jetson Orin Nano 8 GB e placa-base `JETSON-ORIN-IO-BASE`; **não é o Developer Kit oficial da NVIDIA**.

Como a placa-base é de outro fabricante, não se deve aplicar automaticamente o fluxo do Developer Kit NVIDIA. A [Wiki da Waveshare](https://www.waveshare.com/wiki/Jetson_Orin_Nano#Jetson_Orin_Nano.2FNX_Upgrade_to_Super) tem uma secção específica de atualização para o Jetson Orin Nano/NX Super. Para os kits com módulo/carrier Waveshare, ela indica o método por script JetPack 6.2; a página diz que o SDK Manager não deve ser usado para esse caso.

## 1. Confirmar o que veio na caixa

1. Modelo da placa-base confirmado: `JETSON-ORIN-IO-BASE`. Ao receber o kit, confira se a inscrição física corresponde a esse modelo e confirme que o módulo é o Orin Nano de 8 GB.
2. Registe a revisão impressa da placa-base e as etiquetas do módulo e da fonte de alimentação.
3. O NVMe incluído no seu kit é de **256 GB**, conforme confirmado pelo comprador e indicado no conteúdo/lista da embalagem do anúncio. O texto `128gb` no URL parece estar desatualizado; confira a etiqueta do SSD quando receber o equipamento.
4. Consulte a [Wiki da Waveshare para Jetson Orin Nano](https://www.waveshare.com/wiki/Jetson_Orin_Nano) e localize as instruções que correspondem à placa-base exata.

O anúncio lista módulo Wi-Fi AW-CB375NF, adaptador de alimentação EU, cabo USB-A para USB-C e jumper. Guarde o cabo e o jumper; podem ser necessários para recovery. **Não faça curto em pinos nem use o jumper sem confirmar o procedimento e os pinos no manual da Waveshare.**

Antes de ligar, confira na etiqueta da fonte a tensão, corrente e polaridade e compare com os requisitos da placa-base no manual. Não assuma que a fonte é de 19 V. A descrição do produto menciona HDMI; use uma ligação de vídeo compatível com as portas reais desta placa, em vez de presumir DisplayPort do kit NVIDIA.

## 2. Verificar a versão UEFI sem gravar firmware

Depois de confirmar que a fonte é compatível:

1. Ligue um monitor à saída HDMI da placa Waveshare e conecte um teclado USB.
2. Ligue a fonte fornecida e pressione `Esc` repetidamente durante o arranque para tentar abrir o menu UEFI.
3. Anote ou fotografe a versão UEFI apresentada. Não altere opções do menu.

O requisito de versão `36.0` citado no Quick Start da NVIDIA é para o fluxo documentado do Developer Kit oficial com JetPack 7.2.1. **Não use esse número, por si só, para decidir que a imagem oficial é compatível com a placa Waveshare.** Se não aparecer imagem ou o menu UEFI não abrir, pare e consulte a Wiki da Waveshare para a revisão da placa.

Se o Jetson já iniciar no Ubuntu, verifique primeiro a versão instalada:

```bash
cat /etc/nv_tegra_release
```

Depois, abra o menu de energia do ambiente gráfico e veja se **MAXN SUPER** está disponível. Se estiver, não é necessário regravar o sistema apenas para ativar o modo SUPER. Se não estiver disponível e quiser o desempenho adicional, siga as etapas de flash abaixo. O k3s não exige MAXN SUPER.

Antes de fazer o flash, confirme que não há dados a preservar no NVMe de 256 GB e que a fonte fornecida atende às especificações da placa. O procedimento completo regrava QSPI e NVMe; não é uma atualização pequena nem preserva o conteúdo do SSD.

## 3. Preparar o computador host

A receita de flash da Waveshare requer um computador Ubuntu 20.04 ou 22.04. Prefira um host x86_64 físico. Um Mac não executa diretamente estas ferramentas; uma VM só serve se for possível passar o dispositivo USB-C do Jetson à VM de forma estável.

No host, prepare:

- Ligação à Internet e espaço livre para os pacotes Jetson Linux e root filesystem.
- O cabo USB-A para USB-C incluído, confirmando que transmite dados.
- A fonte fornecida pelo kit, depois de conferir a etiqueta e confirmar que corresponde à entrada DC da placa.
- O jumper incluído.

Antes de começar, confirme que aceita apagar o NVMe de 256 GB. O método abaixo instala o sistema no NVMe e atualiza a QSPI; não é uma atualização preservando os dados do disco.

## 4. Baixar e preparar o BSP no Ubuntu

A receita publicada pela Waveshare usa JetPack 6.2 / Jetson Linux r36.4.3. Confira a Wiki novamente no dia do flash para ver se a versão recomendada mudou; não misture arquivos de versões diferentes.

No terminal do host Ubuntu:

```bash
mkdir -p ~/orin_nano
cd ~/orin_nano
wget https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Jetson_Linux_r36.4.3_aarch64.tbz2
wget https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Tegra_Linux_Sample-Root-Filesystem_r36.4.3_aarch64.tbz2
tar xf Jetson_Linux_r36.4.3_aarch64.tbz2
sudo tar xpf Tegra_Linux_Sample-Root-Filesystem_r36.4.3_aarch64.tbz2 -C Linux_for_Tegra/rootfs/
cd Linux_for_Tegra
sudo ./tools/l4t_flash_prerequisites.sh
sudo ./apply_binaries.sh
```

Se a Waveshare publicar uma revisão mais recente da receita, use os pacotes e comandos dessa mesma revisão, não os r36.4.3 acima.

## 5. Colocar a placa em Force Recovery

Use a [ilustração de recovery indicada pela Waveshare](https://www.waveshare.com/wiki/File:JETSON-XAVIER-NX-DEV-KIT-re.png) para localizar os pinos na placa real. Não se guie apenas pelo nome impresso no desenho: confirme os sinais `FC REC` e `GND` no manual/serigrafia do `JETSON-ORIN-IO-BASE`.

1. Desligue o Jetson e retire a alimentação.
2. Com o jumper, faça a ligação entre `FC REC` e `GND` conforme o manual da placa.
3. Ligue o USB-C da placa ao host Ubuntu com o cabo de dados.
4. Ligue a fonte à entrada DC da placa e aguarde a conexão USB ser reconhecida.
5. No host, confirme a detecção com `lsusb`. Se o dispositivo NVIDIA não aparecer, pare e reveja cabo, porta e recovery; não execute o flash.

Não remova nem coloque o jumper com a placa alimentada, a menos que a instrução específica da Waveshare diga para fazê-lo.

## 6. Gravar QSPI e NVMe

No host Ubuntu, ainda dentro de `Linux_for_Tegra`, execute o comando da receita Waveshare para a versão r36.4.3:

```bash
sudo ./tools/kernel_flash/l4t_initrd_flash.sh \
	--external-device nvme0n1p1 \
	-p "-c ./bootloader/generic/cfg/flash_t234_qspi.xml" \
	-c ./tools/kernel_flash/flash_l4t_t234_nvme.xml \
	--showlogs --network usb0 \
	jetson-orin-nano-devkit-super external
```

Este comando atualiza a QSPI e grava o sistema no NVMe, apagando os dados do SSD. Confirme que o destino é o NVMe do Jetson e mantenha alimentação e cabo conectados até o processo terminar sem erro. Não interrompa o flash.

Quando terminar:

1. Desligue/desconecte a alimentação do Jetson.
2. Remova o jumper de recovery.
3. Desconecte o cabo USB-C do host; ligue monitor HDMI, teclado e Ethernet.
4. Ligue o Jetson e conclua a configuração inicial do Ubuntu.
5. Na área de trabalho, selecione **Power Mode → MAXN SUPER**, se essa opção estiver disponível.

## 7. Verificar o resultado

No Jetson, abra um terminal e execute:

```bash
uname -m
cat /etc/nv_tegra_release
sudo nvbootctrl dump-slots-info
```

`uname -m` deve mostrar `aarch64`; `/etc/nv_tegra_release` deve identificar o release instalado (a receita atual da Waveshare usa r36.4.3). Guarde também a versão do bootloader indicada por `nvbootctrl` e confirme que o modo MAXN SUPER aparece no menu de energia.

## 8. Próximo passo: preparar o worker k3s

Depois de confirmar o sistema, antes de instalar o agente k3s:

1. Ligue o Jetson à rede por Ethernet e crie uma reserva DHCP para o endereço dele no roteador.
2. Defina o hostname usado no cluster e habilite SSH:

	```bash
	sudo hostnamectl set-hostname jetson-orin-01
	sudo systemctl enable --now ssh
	```

3. Reinicie e confirme que o endereço IP reservado está ativo.
4. Siga a seção de preparação e registro do worker no [guia de integração k3s](JETSON_ORIN_NANO_K3S.md).

O k3s não exige o modo MAXN SUPER. O Jetson entrará inicialmente com taint para impedir que os workloads existentes sejam agendados nele sem uma decisão explícita. O NVMe local também não substitui os volumes NFS já usados pelo cluster.

## Decisão: JetPack 6.2.1 vs 7.x

Em 2026-10-09, o Jetson foi gravado com Jetson Linux r36.4.3 (receita Waveshare) e recebeu `nvidia-jetpack` 6.2.1 via `apt`, a última versão da linha 6.x no repositório `r36.4`.

A versão mais recente da NVIDIA é o [JetPack 7.2.1](https://developer.nvidia.com/embedded/jetpack/downloads) (Jetson Linux r39.2.1), que já suporta o Orin Nano em modo Super. Ainda assim, a integração no k3s é feita com o 6.2.1, porque:

- O JetPack 7.2.1 é distribuído por ISO para o Developer Kit oficial NVIDIA; não há receita Waveshare confirmada para a `JETSON-ORIN-IO-BASE`.
- Passar para 7.x não é um `apt upgrade`: muda L4T (r36 → r39) e Ubuntu, e obriga a regravar o NVMe.
- As imagens de containers para Jetson (llama.cpp, Ollama, DeepStream, `l4t`) estão mais testadas sobre r36.x.
- O JetPack 7.2 exige firmware QSPI da geração 6.x, que é o que este flash instalou; a migração futura continua possível.

**Reavaliar** quando a Waveshare publicar uma receita JetPack 7.2 para esta placa, ou quando um workload precisar de algo que só exista no 7.x.

## Observações

- A Wiki da Waveshare apresenta um fluxo SDK Manager para o Developer Kit oficial, mas também diz que os kits de módulo/carrier Waveshare devem usar o método por script JetPack 6.2. Para este kit, siga o método por script específico do módulo/carrier.
- O Jetson ISO e os passos de firmware do [guia oficial NVIDIA](https://docs.nvidia.com/jetson/orin-nano-devkit/user-guide/latest/quick_start.html) são para o Developer Kit NVIDIA; não os use neste kit customizado sem confirmação explícita da Waveshare.
- A imagem de recovery da Wiki tem um nome de arquivo referente ao Xavier NX. Confirme a localização dos pinos na documentação/serigrafia da placa `JETSON-ORIN-IO-BASE` antes de instalar o jumper.
