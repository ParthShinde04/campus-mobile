import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_mobile_experimental/app_provider.dart';
import 'package:campus_mobile_experimental/core/models/authentication.dart';
import 'package:campus_mobile_experimental/core/models/user_profile.dart';
import 'package:campus_mobile_experimental/core/providers/cards.dart';
import 'package:campus_mobile_experimental/core/providers/notifications.dart';
import 'package:campus_mobile_experimental/core/services/authentication.dart';
import 'package:campus_mobile_experimental/core/services/user.dart';
import 'package:campus_mobile_experimental/ui/navigator/bottom.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/pointycastle.dart' as pc;
import '../../ui/home/home.dart';

class UserDataProvider extends ChangeNotifier
{
  ///STATES
  bool _isLoading = false;
  DateTime? _lastUpdated;
  String? _error;
  bool _isInSilentLogin = false;

  ///MODELS
  ///default authentication model and profile is needed in this class
  AuthenticationModel _authenticationModel = AuthenticationModel.fromJson({});
  UserProfileModel _userProfileModel = UserProfileModel.fromJson({});
  FlutterSecureStorage storage = FlutterSecureStorage();

  ///SERVICES
  final AuthenticationService _authenticationService = AuthenticationService();
  final UserProfileService _userProfileService = UserProfileService();

  late PushNotificationDataProvider _pushNotificationDataProvider;
  late CardsDataProvider cardsDataProvider;

  /// Update the [AuthenticationModel] stored in state
  /// overwrite the [AuthenticationModel] in persistent storage with the model passed in
  Future updateAuthenticationModel(AuthenticationModel model) async {
    _authenticationModel = model;
    var box = await Hive.openBox<AuthenticationModel?>('AuthenticationModel');
    await box.put('AuthenticationModel', model);
    _lastUpdated = DateTime.now();
  }

  /// Update the [UserProfileModel] stored in state
  /// overwrite the [UserProfileModel] in persistent storage with the model passed in
  Future updateUserProfileModel(UserProfileModel model) async {
    _userProfileModel = model;
    var box;
    try {
      box = Hive.box<UserProfileModel?>('UserProfileModel');
    } catch (e) {
      box = await Hive.openBox<UserProfileModel?>('UserProfileModel');
    } finally {
      await box.put('UserProfileModel', model);
      _lastUpdated = DateTime.now();
    }
  }

  /// Load data from persistent storage by invoking the following methods:
  /// [_loadSavedAuthenticationModel]
  /// [_loadSavedUserProfile]
  Future loadSavedData() async {
    await _loadSavedAuthenticationModel();
    await _loadSavedUserProfile();
  }

  /// Load [AuthenticationModel] from persistent storage
  /// Will create persistent storage if no data is found
  Future _loadSavedAuthenticationModel() async {
    var authBox =
        await Hive.openBox<AuthenticationModel?>('AuthenticationModel');

    AuthenticationModel temp = AuthenticationModel.fromJson({});
    //check to see if we have added the authentication model into the box already
    if (authBox.get('AuthenticationModel') == null) {
      await authBox.put('AuthenticationModel', temp);
      temp = authBox.get('AuthenticationModel')!;
      _authenticationModel = temp;
    } else {
      await silentLogin();
    }
  }

  /// Load [UserProfileModel] from persistent storage
  /// Will create persistent storage if no data is found
  Future _loadSavedUserProfile() async {
    var userBox = await Hive.openBox<UserProfileModel?>('UserProfileModel');

    // Create new user from temp profile
    UserProfileModel tempUserProfile =
        await _createNewUser(UserProfileModel.fromJson({}));
    if (userBox.get('UserProfileModel') == null) {
      await userBox.put('UserProfileModel', tempUserProfile);
    }
    tempUserProfile = userBox.get('UserProfileModel')!;
    _userProfileModel = tempUserProfile;
    _subscribeToPushNotificationTopics(_userProfileModel.subscribedTopics!.whereType<String>().toList());
    notifyListeners();
  }

  /// Save encrypted password to device
  void _saveEncryptedPasswordToDevice(String encryptedPassword) {
    storage.write(key: 'encrypted_password', value: encryptedPassword);
  }

  /// Get encrypted password that has been saved to device
  Future<String?> _getEncryptedPasswordFromDevice() {
    return storage.read(key: 'encrypted_password');
  }

  /// Save username to device
  void _saveUsernameToDevice(String username) {
    storage.write(key: 'username', value: username);
  }

  /// Get username from device
  Future<String?> getUsernameFromDevice() {
    return storage.read(key: 'username');
  }

  /// Delete username from device
  void _deleteUsernameFromDevice() {
    storage.delete(key: 'username');
  }

  /// Delete password from device
  void _deletePasswordFromDevice() {
    storage.delete(key: 'password');
  }

  /// Encrypt given username and password and store on device
  void _encryptAndSaveCredentials(String username, String password) {
    final String pkString = dotenv.get('USER_CREDENTIALS_PUBLIC_KEY');

    final rsaParser = RSAKeyParser();
    final pc.RSAPublicKey publicKey = rsaParser.parse(pkString) as RSAPublicKey;
    var cipher = OAEPEncoding(pc.AsymmetricBlockCipher('RSA'));
    pc.AsymmetricKeyParameter<pc.RSAPublicKey> keyParametersPublic =
        new pc.PublicKeyParameter(publicKey);
    cipher.init(true, keyParametersPublic);
    Uint8List output = cipher.process(utf8.encode(password));
    var base64EncodedText = base64.encode(output);
    _saveUsernameToDevice(username);
    _saveEncryptedPasswordToDevice(base64EncodedText);
  }

  /// Authenticate a user given an username and password
  /// Upon logging in we should make sure that users has an account
  /// If the user doesn't have an account one will be made by invoking [_createNewUser]
  Future manualLogin(String username, String password) async {
    _error = null; _isLoading = true;
    notifyListeners();

    if (username.isNotEmpty && password.isNotEmpty) {
      _encryptAndSaveCredentials(username, password);

      if (await silentLogin()) {
        if (_userProfileModel.classifications!.student!) {
          cardsDataProvider.showAllStudentCards();
        } else if (_userProfileModel.classifications!.staff!) {
          cardsDataProvider.showAllStaffCards();
        }
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = _authenticationService.error;
        _isLoading = false;
        notifyListeners();
        return false;
      }
    }

    _error = 'Username or password not found';
    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Logs user in with saved credentials on device
  /// If this login mechanism fails then the user is logged out
  Future<bool> silentLogin() async {
    _isInSilentLogin = true;
    notifyListeners();

    String? username = await getUsernameFromDevice();
    String? encryptedPassword = await _getEncryptedPasswordFromDevice();

    /// Allow silentLogin if username, pw are set, and the user is not logged in
    if (username != null && encryptedPassword != null) {
      final String base64EncodedWithEncryptedPassword =
          base64.encode(utf8.encode(username + ':' + encryptedPassword));
      resetHomeScrollOffset();
      resetAllCardHeights();
      resetNotificationsScrollOffset();
      if (await _authenticationService
          .silentLogin(base64EncodedWithEncryptedPassword)) {
        await updateAuthenticationModel(_authenticationService.data!);
        await fetchUserProfile();

        CardsDataProvider _cardsDataProvider = CardsDataProvider();
        _cardsDataProvider
            .updateAvailableCards(_userProfileModel.ucsdaffiliation);

        _subscribeToPushNotificationTopics(List<String>.from(userProfileModel.subscribedTopics!));
        _pushNotificationDataProvider
            .registerDevice(_authenticationService.data!.accessToken);
        await analytics.logEvent(name: 'loggedIn');
        _isInSilentLogin = false;
        notifyListeners();
        return true;
      }
    }

    logout();
    return false;
  }

  /// Logs out user
  /// Unregisters device from direct push notification using [_pushNotificationDataProvider]
  /// Resets all [AuthenticationModel] and [UserProfileModel] data from persistent storage
  void logout() async {
    _error = null;
    _isLoading = true;
    notifyListeners();
    resetHomeScrollOffset();
    resetAllCardHeights();
    resetNotificationsScrollOffset();
    _pushNotificationDataProvider.unregisterDevice(_authenticationModel.accessToken);
    updateAuthenticationModel(AuthenticationModel.fromJson({}));
    updateUserProfileModel(await _createNewUser(UserProfileModel.fromJson({})));
    _deletePasswordFromDevice();
    _deleteUsernameFromDevice();
    CardsDataProvider _cardsDataProvider = CardsDataProvider();
    _cardsDataProvider.updateAvailableCards("");
    var box = await Hive.openBox<AuthenticationModel?>('AuthenticationModel');
    await box.clear();
    await analytics.logEvent(name: 'loggedOut');
    _isLoading = false;
    notifyListeners();
  }

  /// Remove topic from [_userProfileModel.subscribedTopics]
  /// Use [_pushNotificationDataProvider] to un/subscribe device from push notifications
  void toggleNotifications(String topic) {
    if (_userProfileModel.subscribedTopics!.contains(topic)) {
      _userProfileModel.subscribedTopics!.remove(topic);
    } else {
      _userProfileModel.subscribedTopics!.add(topic);
    }
    postUserProfile(_userProfileModel);
    _pushNotificationDataProvider.toggleNotificationsForTopic(topic);
    notifyListeners();
  }

  /// Fetch the [UserProfileModel] from the server if the user is logged in
  /// if the user has no profile in the db then we create on by invoking [_createNewUser]
  /// invoke [postUserProfile] once user profile is created
  /// if user has a profile then we invoke [updateUserProfileModel]
  Future fetchUserProfile() async {
    _error = null; _isLoading = true;
    notifyListeners();

    if (isLoggedIn) {
      /// we fetch the user data now
      final Map<String, String> headers = {
        'Authorization': 'Bearer ' + _authenticationModel.accessToken!
      };
      if (await _userProfileService.downloadUserProfile(headers)) {
        /// if the user profile has no ucsd affiliation then we know the user is new
        /// so create a new profile and upload to DB using [postUserProfile]
        UserProfileModel newModel = _userProfileService.userProfileModel;
        if (newModel.ucsdaffiliation == null) {
          newModel = await _createNewUser(newModel);
          await postUserProfile(newModel);
        } else {
          newModel.username = await getUsernameFromDevice();
          newModel.ucsdaffiliation = _authenticationModel.ucsdaffiliation;
          newModel.pid = _authenticationModel.pid;
          List<String> castSubscriptions =
              newModel.subscribedTopics!.cast<String>();
          newModel.subscribedTopics = castSubscriptions.toSet().toList();

          final studentPattern = RegExp('[BGJMU]');
          final staffPattern = RegExp('[E]');

          if ((newModel.ucsdaffiliation ?? "").contains(studentPattern)) {
            newModel
              ..classifications =
                  Classifications.fromJson({'student': true, 'staff': false});
          } else if ((newModel.ucsdaffiliation ?? "").contains(staffPattern)) {
            newModel
              ..classifications =
                  Classifications.fromJson({'staff': true, 'student': false});
          } else {
            newModel.classifications =
                Classifications.fromJson({'student': false, 'staff': false});
          }
          await updateUserProfileModel(newModel);
          _pushNotificationDataProvider
              .subscribeToTopics(newModel.subscribedTopics!.cast<String>());
        }
      } else {
        _error = _userProfileService.error;
      }
    } else {
      _error = 'not logged in';
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Given a list of topics
  /// invoke [_pushNotificationDataProvider.unsubscribeFromAllTopics()]
  /// invoke [_pushNotificationDataProvider.toggleNotificationsForTopic] on each of the topics
  void _subscribeToPushNotificationTopics(List<String> topics) {
    /// turn on all saved push notifications preferences for user
    _pushNotificationDataProvider.unsubscribeFromAllTopics();
    for (String topic in topics) {
      _pushNotificationDataProvider.toggleNotificationsForTopic(topic);
    }
  }

  /// Create a new user profile based on SSO info
  /// Subscribe students to student topics by appending to [profile]'s [subscribedTopics] list
  /// Subscribe users to public topics appending to [profile]'s [subscribedTopics] list
  /// invokes [_subscribeToPushNotificationTopics] to subscribe user to topics
  /// returns newly created [UserProfileModel]
  Future<UserProfileModel> _createNewUser(UserProfileModel profile) async {
    await _pushNotificationDataProvider.fetchTopicsList();
    try {
      profile.username = await getUsernameFromDevice();
      profile.ucsdaffiliation = _authenticationModel.ucsdaffiliation;
      profile.pid = _authenticationModel.pid;
      profile.subscribedTopics = _pushNotificationDataProvider.publicTopics();
      final studentPattern = RegExp('[BGJMU]');
      final staffPattern = RegExp('[E]');

      if ((profile.ucsdaffiliation ?? "").contains(studentPattern)) {
        profile
          ..classifications =
              Classifications.fromJson({'student': true, 'staff': false})
          ..subscribedTopics!
              .addAll(_pushNotificationDataProvider.studentTopics());
      } else if ((profile.ucsdaffiliation ?? "").contains(staffPattern)) {
        profile
          ..classifications =
              Classifications.fromJson({'staff': true, 'student': false})
          ..subscribedTopics!
              .addAll(_pushNotificationDataProvider.staffTopics());
      } else {
        profile.classifications =
            Classifications.fromJson({'student': false, 'staff': false});
      }
    } catch (e) {
      print(e.toString());
    }
    return profile;
  }

  /// Invoke [updateUserProfileModel] with user profile that was passed in
  /// If user is logged in upload [UserProfileModel] to DB
  Future postUserProfile(UserProfileModel profile) async {
    _error = null; _isLoading = true;
    notifyListeners();

    /// save settings to local storage
    await updateUserProfileModel(profile);

    /// check if user is logged in
    if (_authenticationModel.isLoggedIn(_authenticationService.lastUpdated)) {
      final Map<String, String> headers = {
        'Authorization': "Bearer " + _authenticationModel.accessToken!
      };

      /// we only want to push data that is not null
      var tempJson = Map<String, dynamic>();
      for (var key in profile.toJson().keys) {
        if (profile.toJson()[key] != null) {
          tempJson[key] = profile.toJson()[key];
        }
      }
      if (await _userProfileService.uploadUserProfile(headers, tempJson)) {
        _error = null;
        _isLoading = false;
      } else {
        _error = _userProfileService.error;
      }
    } else {
      _error = 'not logged in';
    }
    _isLoading = false;
    notifyListeners();
  }

  set pushNotificationDataProvider(PushNotificationDataProvider value) {
    _pushNotificationDataProvider = value;
  }

  // TODO: fix this after UserProfileModel's nullability is fixed
  List<String?>? get subscribedTopics => _userProfileModel.subscribedTopics;

  ///GETTERS FOR MODELS
  UserProfileModel get userProfileModel => _userProfileModel;

  AuthenticationModel get authenticationModel => _authenticationModel;

  ///GETTERS FOR STATES
  String? get error => _error;

  bool get isLoggedIn => _authenticationModel.isLoggedIn(_lastUpdated);

  bool get isLoading => _isLoading;

  DateTime? get lastUpdated => _lastUpdated;
  bool get isInSilentLogin => _isInSilentLogin;
}
