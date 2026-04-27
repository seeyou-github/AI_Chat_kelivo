import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/chat/chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatService startup staging', () {
    test('draft conversation is available before Hive init', () async {
      final service = ChatService();

      expect(service.initialized, isFalse);
      expect(service.conversationsReady, isFalse);

      final draft = await service.createDraftConversation(
        title: 'Draft',
        assistantId: 'assistant-1',
      );

      expect(service.initialized, isFalse);
      expect(service.conversationsReady, isFalse);
      expect(service.currentConversationId, draft.id);
      expect(service.getConversation(draft.id)?.title, 'Draft');
      expect(service.getMessages(draft.id), isEmpty);

      final conversations = service.getAllConversations();
      expect(conversations, hasLength(1));
      expect(conversations.single.id, draft.id);
      expect(conversations.single.assistantId, 'assistant-1');
    });
  });
}
