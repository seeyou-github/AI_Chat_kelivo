import 'dart:async';

enum OcrAction {
  captureAndSend,
}

class OcrActionBus {
  OcrActionBus._();
  static final OcrActionBus instance = OcrActionBus._();

  final _controller = StreamController<OcrAction>.broadcast();
  Stream<OcrAction> get stream => _controller.stream;

  void fire(OcrAction action) {
    if (!_controller.isClosed) {
      _controller.add(action);
    }
  }

  void dispose() {
    _controller.close();
  }
}
