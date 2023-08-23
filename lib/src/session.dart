import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'package:talkjs_flutter_inappwebview/talkjs_flutter_inappwebview.dart';

import './user.dart';
import './conversation.dart';
import './webview_common.dart';

/// A session represents a currently active user.
class Session with ChangeNotifier {
  /// Your TalkJS AppId that can be found your TalkJS [dashboard](https://talkjs.com/dashboard).
  final String appId;

  /// The TalkJS [User] associated with the current user in your application.
  User? _me;

  User get me {
    if (_me == null) {
      throw StateError('Set the me property before using the Session object');
    } else {
      return _me!;
    }
  }

  // We have the following moving parts:
  // - We need a `me` User before being able to create the session in the WebView
  // - The `enablePushNotifications` property can change before the WebView is loaded
  // - When the WebView loads or when the `me` user is passed, whichever comes last,
  //   the session is created, and _sessionInitialized gets set to true.
  //   At this point, any change to enablePushNotifications triggers setting or unsetting
  //   the push notifications

  set me(User user) {
    if (_me != null) {
      throw StateError(
          'The me property has already been set for the Session object');
    } else {
      _me = user;

      // If the WebView has loaded the page, but didn't initialize the session because of
      // the missing `me` property, now is the time to initialize the session.
      if ((_webViewController != null) && (!_sessionInitialized)) {
        _sessionInitialized = true;
        _execute('const me = new Talk.User(${me.getJsonString()});');
        createSession(
          execute: _execute,
          session: this,
          variableName: 'me',
        );
      }
    }
  }

  /// A digital signature of the current [User.id]
  ///
  /// This is the HMAC-SHA256 hash of the current user id, signed with your
  /// TalkJS secret key.
  /// DO NOT embed your secret key within your mobile application / frontend
  /// code.
  final String? signature;

  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _webViewController;
  bool _sessionInitialized;

  bool _enablePushNotifications;

  bool get enablePushNotifications {
    return _enablePushNotifications;
  }

  set enablePushNotifications(bool enable) {
    if (enable != _enablePushNotifications) {
      _enablePushNotifications = enable;

      if (_sessionInitialized) {
        setOrUnsetPushRegistration(
            execute: _execute, enablePushNotifications: enable);
      }
    }
  }

  void _onWebViewCreated(InAppWebViewController controller) async {
    if (kDebugMode) {
      print('📗 session._onWebViewCreated');
    }

    String htmlData = await rootBundle
        .loadString('packages/talkjs_flutter/assets/index.html');
    controller.loadData(
        data: htmlData, baseUrl: WebUri("https://app.talkjs.com"));
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) async {
    if (kDebugMode) {
      print('📗 session._onLoadStop ($url)');
    }

    if (_webViewController == null) {
      _webViewController = controller;

      // Wait for TalkJS to be ready
      final js = 'await Talk.ready;';

      if (kDebugMode) {
        print('📗 session callAsyncJavaScript: $js');
      }

      await controller.callAsyncJavaScript(functionBody: js);

      // If the `me` property has already been initialized, then create the user and the session
      if ((_me != null) && (!_sessionInitialized)) {
        _sessionInitialized = true;
        _execute('const me = new Talk.User(${me.getJsonString()});');
        createSession(
          execute: _execute,
          session: this,
          variableName: 'me',
        );
      }
    }
  }

  void _execute(String statement) {
    if (kDebugMode) {
      print('📗 session.execute: $statement');
    }

    _webViewController?.evaluateJavascript(source: statement);
  }

  Session(
      {required this.appId, this.signature, enablePushNotifications = false})
      : _enablePushNotifications = enablePushNotifications,
        _sessionInitialized = false {
    _headlessWebView = new HeadlessInAppWebView(
        onWebViewCreated: _onWebViewCreated,
        onLoadStop: _onLoadStop,
        onConsoleMessage:
            (InAppWebViewController controller, ConsoleMessage message) {
          print("session [${message.messageLevel}] ${message.message}");
        });
  }

  User getUser({
    required String id,
    required String name,
    List<String>? email,
    List<String>? phone,
    String? availabilityText,
    String? locale,
    String? photoUrl,
    String? role,
    Map<String, String?>? custom,
    String? welcomeMessage,
  }) =>
      User(
        session: this,
        id: id,
        name: name,
        email: email,
        phone: phone,
        availabilityText: availabilityText,
        locale: locale,
        photoUrl: photoUrl,
        role: role,
        custom: custom,
        welcomeMessage: welcomeMessage,
      );

  User getUserById(String id) => User.fromId(id, this);

  Conversation getConversation({
    required String id,
    Map<String, String?>? custom,
    List<String>? welcomeMessages,
    String? photoUrl,
    String? subject,
    Set<Participant> participants = const <Participant>{},
  }) =>
      Conversation(
        session: this,
        id: id,
        custom: custom,
        welcomeMessages: welcomeMessages,
        photoUrl: photoUrl,
        subject: subject,
        participants: participants,
      );
}
