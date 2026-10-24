import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';

// Bump when the text changes so every user accepts the new version.
const String kLgpdTermsVersion = '1';
const String kLgpdAcceptedOption = 'confialtiva-lgpd-accepted';

const String _kLgpdTermsText = '''
TERMO DE USO E AVISO DE PRIVACIDADE - CONFIALTIVA REMOTE

1. Finalidade
O Confialtiva Remote permite que a equipe de suporte da Confialtiva acesse este computador remotamente, exclusivamente para prestar suporte técnico, manutenção e atendimento solicitados por você ou pela sua empresa.

2. Dados tratados (Lei nº 13.709/2018 - LGPD)
Durante o uso podem ser tratados: identificador do dispositivo (ID), nome do computador, sistema operacional, endereço IP, data, hora e duração das sessões, identificação do técnico e, enquanto a sessão estiver ativa, as imagens da tela, áudio (se habilitado), arquivos transferidos e conteúdo da área de transferência.

3. Base legal
O tratamento é realizado para a execução de contrato ou de procedimentos preliminares a ele (art. 7º, V), para o cumprimento de obrigação legal ou regulatória (art. 7º, II) e para o legítimo interesse de manutenção da segurança e do suporte (art. 7º, IX), sempre limitado ao necessário.

4. Consentimento a cada acesso
Nenhuma sessão remota é iniciada sem a sua aprovação. A cada pedido de conexão você verá quem está solicitando o acesso e poderá aceitar ou recusar. Você pode encerrar a sessão a qualquer momento.

5. Gravação e registros
As sessões não são gravadas sem aviso prévio. Registros de acesso (quem acessou, quando e por quanto tempo) são mantidos para fins de auditoria e segurança pelo prazo de [PRAZO DE RETENÇÃO] e depois eliminados.

6. Compartilhamento
Os dados não são vendidos nem compartilhados com terceiros, exceto quando exigido por lei ou com prestadores necessários à operação do serviço, sob dever de confidencialidade.

7. Segurança
As conexões são criptografadas de ponta a ponta. Recomendamos fechar documentos e janelas com informações pessoais que não sejam necessárias ao atendimento.

8. Seus direitos
Você pode solicitar confirmação, acesso, correção, anonimização, portabilidade, eliminação de dados e informações sobre compartilhamento, além de revogar este consentimento, pelo contato do Encarregado (DPO): [NOME DO ENCARREGADO] - [E-MAIL DO ENCARREGADO].

9. Controlador
[RAZÃO SOCIAL DA CONFIALTIVA] - CNPJ [CNPJ] - [ENDEREÇO].

Ao clicar em "Aceito", você declara que leu e concorda com este termo.
''';

bool _lgpdDialogShown = false;

bool isLgpdTermsAccepted() {
  final v = bind.mainGetLocalOption(key: kLgpdAcceptedOption);
  return v.split('|').first == kLgpdTermsVersion;
}

Future<void> showLgpdTermsIfNeeded(BuildContext context) async {
  if (_lgpdDialogShown || isLgpdTermsAccepted()) return;
  _lgpdDialogShown = true;
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _LgpdTermsDialog(),
  );
  if (accepted == true) {
    final now = DateTime.now().toUtc().toIso8601String();
    await bind.mainSetLocalOption(
        key: kLgpdAcceptedOption, value: '$kLgpdTermsVersion|$now');
  } else {
    exit(0);
  }
}

class _LgpdTermsDialog extends StatefulWidget {
  const _LgpdTermsDialog();

  @override
  State<_LgpdTermsDialog> createState() => _LgpdTermsDialogState();
}

class _LgpdTermsDialogState extends State<_LgpdTermsDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Termo de Uso e Privacidade (LGPD)'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 12),
                    child: SelectableText(_kLgpdTermsText),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _checked,
                onChanged: (v) => setState(() => _checked = v ?? false),
                title: const Text('Li e concordo com o Termo de Uso e Privacidade'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Recusar e sair'),
          ),
          ElevatedButton(
            onPressed: _checked ? () => Navigator.of(context).pop(true) : null,
            child: const Text('Aceito'),
          ),
        ],
      ),
    );
  }
}
