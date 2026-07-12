import 'package:encrypt/encrypt.dart';

import '../config/api_config.dart';
import '../models/message_model.dart';

class MessageCryptoService {
  static Future<String> _loadPrivateKeyPem() async {
    final cfg = await ApiConfigStore.load();
    final pem = cfg.rescuePrivateKey.trim();
    if (pem.isEmpty) {
      throw StateError('Rescue private key is not configured in settings.');
    }
    return pem;
  }

  static Future<Encrypter> _buildEncrypter() async {
    final pem = await _loadPrivateKeyPem();
    if (!pem.contains('PRIVATE KEY')) {
      throw StateError('Configured key is not a private RSA key.');
    }

    final parsedKey = RSAKeyParser().parse(pem);

    return Encrypter(
      RSA(
        privateKey: parsedKey as dynamic,
        encoding: RSAEncoding.OAEP,
        digest: RSADigest.SHA256,
      ),
    );
  }

  static Future<Message> decryptMessage(Message message) async {
    if (!message.isEncryptedPayload) {
      return message.copyWith(
        decryptedContent: null,
        decryptionError: null,
      );
    }

    try {
      final encrypter = await _buildEncrypter();
      final decrypted = encrypter.decrypt64(message.content);
      return message.copyWith(
        decryptedContent: decrypted,
        decryptionError: null,
      );
    } catch (error) {
      return message.copyWith(
        decryptedContent: null,
        decryptionError: error.toString(),
      );
    }
  }

  static Future<List<Message>> decryptMessages(List<Message> messages) async {
    final results = <Message>[];
    for (final message in messages) {
      results.add(await decryptMessage(message));
    }
    return results;
  }
}
