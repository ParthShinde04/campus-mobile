import 'package:campus_mobile_experimental/app_networking.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BarcodeService {
  BarcodeService();
  bool? _isLoading;
  String? _error;

  final NetworkHelper _networkHelper = NetworkHelper();

  Future<bool> uploadResults(Map<String, String> headers, Map<String, dynamic> body) async {
    _error = null; _isLoading = true;
    try {
      final response = await _networkHelper.authorizedPost(
          dotenv.get('BARCODE_SERVICE_ENDPOINT'),
          headers, body
      );
      if (response != null && validateUploadResults(body, response)) {
        return true;
      } else {
        throw (response.toString());
      }
    } catch (e) {
      /// if the authorized fetch failed we know we have to refresh the
      /// token for this service
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /*
    The following conditions are being checked on the client-side before indicating a successful submission:

      - ScanData API responds with a 200/201 status code (checked in networking.dart)
      - ScanData API has not thrown an error
      - The stored value returned by ScanData API matches the value that has actually been scanned
      - The student has a non-empty Account ID, User ID, or Employee ID
  */
  bool validateUploadResults(
      Map<String, dynamic> submit, Map<String, dynamic> response) {
    try {
      return (submit["barcode"] == response["SCAN_CODE_ID"]);
    } catch (e) {
      return false;
    }
  }

  bool isValid(var toCheck) {
    try {
      return (toCheck != null && toCheck.toString().isNotEmpty);
    } catch (e) {
      return false;
    }
  }

  String? get error => _error;
  bool? get isLoading => _isLoading;
}
