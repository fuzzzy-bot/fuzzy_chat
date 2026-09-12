import 'package:flutter_test/flutter_test.dart';
import 'package:fuzzy_chat/lib.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockCryptoCoreService extends Mock implements CryptoCoreService {}

class MockMessageDataRepository extends Mock implements MessageDataRepository {}

const _chatId = '6f1e9b2c-3d4a-4f5b-8c6d-7e8f9a0b1c2d';

MessageData _row(int id) => MessageData(
      id: id,
      chatId: _chatId,
      type: MessageType.text,
      encryptedMessage: 'blob$id',
      decryptedMessage: 'text $id',
      sentAt: DateTime(2026, 9, 12, 12, id),
      isSent: id.isEven,
    );

void main() {
  late MockCryptoCoreService mockService;
  late MockMessageDataRepository mockRepo;

  setUp(() {
    mockService = MockCryptoCoreService();
    mockRepo = MockMessageDataRepository();
    when(() => mockRepo.newMessageUpdates)
        .thenAnswer((_) => const Stream.empty());
    when(
      () => mockRepo.getMessagesForChatPaginated(
        any(),
        pageSize: any(named: 'pageSize'),
        pageIndex: any(named: 'pageIndex'),
      ),
    ).thenAnswer(
      (invocation) async {
        final page = invocation.namedArguments[#pageIndex] as int;
        return List.generate(8, (i) => _row(page * 8 + i));
      },
    );
    when(
      () => mockService.decryptText(
        chatId: any(named: 'chatId'),
        blob: any(named: 'blob'),
      ),
    ).thenAnswer(
      (_) async => const CryptoCoreFailure(CryptoCoreFailureType.corrupt),
    );
  });

  group('shouldToastFailure (the connected chat page listener predicate)', () {
    test(
        'a failed paste toasts once; the loads of the next scroll-up stay '
        'silent although actionStatus is sticky', () async {
      final cubit = ConnectedChatCubit(
        messageDataRepository: mockRepo,
        cryptoCoreService: mockService,
        chatId: _chatId,
      );
      addTearDown(cubit.close);

      // Replay the page's listener over the real state stream.
      final toasts = <String>[];
      var previous = cubit.state;
      final subscription = cubit.stream.listen((current) {
        if (shouldToastFailure(previous, current)) {
          toasts.add(
            current.status.isFailed
                ? 'load'
                : 'action:${current.actionFailure?.type.name}',
          );
        }
        previous = current;
      });
      addTearDown(subscription.cancel);

      await cubit.loadInitialMessages();
      await cubit.receiveMessage(encryptedText: 'garbage');
      await pumpEventQueue();
      expect(toasts, ['action:corrupt']);

      await cubit.loadOlderMessages();
      await cubit.loadOlderMessages();
      await pumpEventQueue();
      expect(cubit.state.messages.length, 24);
      expect(cubit.state.actionStatus, StateStatus.failed, reason: 'sticky');
      expect(toasts, ['action:corrupt'], reason: 'no re-toast on scroll-up');

      // A second failed paste is a new transition into failed → one more.
      await cubit.receiveMessage(encryptedText: 'garbage');
      await pumpEventQueue();
      expect(toasts, ['action:corrupt', 'action:corrupt']);
    });

    test('a load failure toasts on its transition only', () {
      const idle =
          ConnectedChatState(status: StateStatus.success, messages: []);
      const failed =
          ConnectedChatState(status: StateStatus.failed, messages: []);
      const failedAgain = ConnectedChatState(
        status: StateStatus.failed,
        messages: [],
        actionStatus: StateStatus.loading,
      );

      expect(shouldToastFailure(idle, failed), isTrue);
      expect(shouldToastFailure(failed, failedAgain), isFalse);
      expect(shouldToastFailure(failed, idle), isFalse);
    });
  });
}
