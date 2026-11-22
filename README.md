# Roteador para iPhone

1. Abra `VivoChip.xcodeproj` no Xcode. Selecione a equipe em Signing & Capabilities e instale no iPhone.
2. No A15, instale o Vivo Chip 2.22, abra **Controle pelo iPhone** e toque em **Ativar**. Confirme que o Shizuku está em execução para desligar o roteador.
3. Para usar fora de casa, conecte o iPhone e o A15 à mesma rede privada Tailscale. Permita conexões de entrada no A15. Para um teste local, use o IP do A15 na mesma rede Wi-Fi.
4. No iPhone, digite o IP do A15 e o código de pareamento exibido no Android. Salve o pareamento e toque em **Testar conexão**.
5. Em **Guardar credenciais existentes**, informe os valores que deseja guardar. Use o botão de olho e autentique-se para consultá-los. Uma troca confirmada pelo A15 atualiza a credencial correspondente no iPhone.

Ao gerar um novo código no A15, repita o pareamento. O A15 precisa estar online para aceitar os comandos. Após reiniciar, a função de desligar depende do Shizuku estar em execução.
