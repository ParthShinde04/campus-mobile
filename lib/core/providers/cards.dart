import 'package:campus_mobile_experimental/app_constants.dart';
import 'package:campus_mobile_experimental/core/models/cards.dart';
import 'package:campus_mobile_experimental/core/providers/user.dart';
import 'package:campus_mobile_experimental/core/services/cards.dart';
import 'package:campus_mobile_experimental/ui/home/home.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:connectivity/connectivity.dart';

class CardsDataProvider extends ChangeNotifier {
  CardsDataProvider() {
    // Initialize _cardStates with default true values
    for (String card in CardTitleConstants.titleMap.keys.toList()) {
      _cardStates[card] = true;
    }

    _cardOrder.removeWhere((element) => _studentCards.contains(element));
    _cardStates.removeWhere((key, value) => _studentCards.contains(key));
    _cardOrder.removeWhere((element) => _staffCards.contains(element));
    _cardStates.removeWhere((key, value) => _staffCards.contains(key));
  }

  // DEFAULT STATES
  bool _noInternet = false;
  bool _isLoading = false;
  Map<String, bool> _cardStates = {};
  Map<String, CardsModel?> _webCards = {};

  DateTime? _lastUpdated;
  String? _error;

  // Default card order for native cards
  List<String> _cardOrder = [
    'NativeScanner',
    'MyStudentChart',
    'MyUCSDChart',
    'finals',
    'schedule',
    'student_id',
    'employee_id',
    'availability',
    'dining',
    'events',
    'triton_media',
    'shuttle',
    'parking',
    'news',
    'weather',
    'speed_test',
  ];

  // Native student cards
  List<String> _studentCards = [
    'finals',
    'schedule',
    'student_id',
  ];

  // Native staff cards
  List<String> _staffCards = [
    'MyUCSDChart',
    'staff_info',
    'employee_id',
  ];

  Map<String, CardsModel>? _availableCards;
  late Box _cardOrderBox;
  late Box _cardStateBox;

  UserDataProvider? _userDataProvider;

  // Services
  final CardsService _cardsService = CardsService();
  final Connectivity _connectivity = Connectivity();

  Future<void> _loadCardOrder() async {
    if (_userDataProvider == null || _userDataProvider!.isInSilentLogin) {
      return;
    }
    _cardOrderBox = await Hive.openBox(DataPersistence.cardOrder);
    if (_cardOrderBox.get(DataPersistence.cardOrder) == null) {
      // If no saved order exists, save the default order
      await _cardOrderBox.put(DataPersistence.cardOrder, _cardOrder);
    } else {
      // Load the saved card order
      _cardOrder = List<String>.from(_cardOrderBox.get(DataPersistence.cardOrder));
    }
    notifyListeners();
  }

  Future<void> _loadCardStates() async {
    _cardStateBox = await Hive.openBox(DataPersistence.cardStates);
    if (_cardStateBox.get(DataPersistence.cardStates) == null) {
      // If no saved states exist, activate all cards by default
      var activeCards = _cardStates.keys.toList();
      await _cardStateBox.put(DataPersistence.cardStates, activeCards);
    } else {
      // Deactivate all cards first
      _deactivateAllCards();
      // Activate the saved cards
      List<String> activeCards = List<String>.from(_cardStateBox.get(DataPersistence.cardStates));
      for (String activeCard in activeCards) {
        _cardStates[activeCard] = true;
      }
    }
    notifyListeners();
  }

  void _deactivateAllCards() {
    for (String card in _cardStates.keys) {
      _cardStates[card] = false;
    }
  }

  void updateAvailableCards(String? ucsdAffiliation) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    if (await _cardsService.fetchCards(ucsdAffiliation)) {
      _availableCards = _cardsService.cardsModel;
      _lastUpdated = DateTime.now();

      if (_availableCards!.isNotEmpty) {
        // Remove inactive or non-existent cards from _cardOrder
        _cardOrder.removeWhere((card) =>
        _availableCards![card] == null ||
            !(_availableCards![card]!.cardActive ?? false));

        // Remove inactive or non-existent cards from _cardStates
        _cardStates.removeWhere((card, _) =>
        _availableCards![card] == null ||
            !(_availableCards![card]!.cardActive ?? false));

        // Clear _webCards
        _webCards.clear();

        // Add active webCards
        for (String card in _cardStates.keys) {
          if (_availableCards![card]!.isWebCard!) {
            _webCards[card] = _availableCards![card];
          }
        }

        // Add new active cards to _cardOrder and _cardStates
        for (String card in _availableCards!.keys) {
          if (_studentCards.contains(card)) continue;
          if (_staffCards.contains(card)) continue;

          if ((_availableCards![card]!.cardActive ?? false)) {
            if (!_cardOrder.contains(card)) {
              _cardOrder.add(card);
            }
            _cardStates.putIfAbsent(card, () => true);
          }
        }

        // Ensure no duplicates
        _cardOrder = _cardOrder.toSet().toList();
        updateCardOrder();
        updateCardStates();
      }
    } else {
      _error = _cardsService.error;
    }
    _isLoading = false;
    notifyListeners();
  }

  Future changeInternetStatus(noInternet) async {
    _noInternet = noInternet;
  }

  Future<void> initConnectivity() async {
    try {
      var status = await _connectivity.checkConnectivity();
      _noInternet = (status == ConnectivityResult.none);
      notifyListeners();
    } catch (e) {
      print("Encounter $e when monitoring Internet for cards");
    }
  }

  void monitorInternet() async {
    await initConnectivity();
    _connectivity.onConnectivityChanged.listen((result) async {
      _noInternet = (result == ConnectivityResult.none);
      notifyListeners();
    });
  }

  Future loadSavedData() async {
    _cardStateBox = await Hive.openBox(DataPersistence.cardStates);
    _cardOrderBox = await Hive.openBox(DataPersistence.cardOrder);
    await _loadCardOrder();
    await _loadCardStates();
  }

  Future<void> updateCardOrder() async {
    if (_userDataProvider == null || _userDataProvider!.isInSilentLogin) {
      return;
    }
    _cardOrderBox = await Hive.openBox(DataPersistence.cardOrder);
    _cardOrderBox.put(DataPersistence.cardOrder, _cardOrder);
    _lastUpdated = DateTime.now();
    notifyListeners();
  }

  Future<void> updateCardStates() async {
    if (_userDataProvider == null || _userDataProvider!.isInSilentLogin) {
      return;
    }
    var activeCards = _cardStates.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
    _cardStateBox = await Hive.openBox(DataPersistence.cardStates);
    _cardStateBox.put(DataPersistence.cardStates, activeCards);
    _lastUpdated = DateTime.now();
    notifyListeners();
  }

  void activateStudentCards() {
    for (String card in _studentCards) {
      if (!_cardOrder.contains(card)) {
        _cardOrder.add(card);
      }
      _cardStates[card] = true;
    }
    _cardOrder = _cardOrder.toSet().toList();
    updateCardOrder();
    updateCardStates();
  }

  void deactivateStudentCards() {
    for (String card in _studentCards) {
      _cardOrder.remove(card);
      _cardStates[card] = false;
    }
    updateCardOrder();
    updateCardStates();
  }

  // Similar changes for staff cards...

  void toggleCard(String card) {
    if (_availableCards![card]!.isWebCard! && _cardStates[card]!) {
      resetCardHeight(card);
    }
    _cardStates[card] = !_cardStates[card]!;
    updateCardStates();
  }

  set userDataProvider(UserDataProvider value) => _userDataProvider = value;

  ///SIMPLE GETTERS
  bool? get isLoading => _isLoading;
  bool? get noInternet => _noInternet;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;

  Map<String, bool>? get cardStates => _cardStates;
  List<String>? get cardOrder => _cardOrder;
  Map<String, CardsModel?>? get webCards => _webCards;
  Map<String, CardsModel> get availableCards => _availableCards!;
}
