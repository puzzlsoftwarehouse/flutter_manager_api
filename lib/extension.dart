import 'dart:convert';

extension IsValidJson on String {
  bool isValidJson() {
    try {
      jsonDecode(this);
      return true;
    } catch (e) {
      return false;
    }
  }
}
